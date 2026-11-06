/// The bodies side of `Physics2DSystem`: a body for each entity with a
/// [Collider2DComponent], made, kept in step and taken away.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_dart/just_dart.dart' show Vector2;
import 'package:just_physics_engine/just_physics_engine.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../../foundation/solid_shape_2d.dart';
import '../../rendering/culling/cull_state_component.dart';
import '../body_rebuild.dart';
import '../physics_context.dart';
import '../physics_layers.dart';
import 'collider_2d_geometry.dart';
import 'physics_2d_components.dart';
import 'physics_2d_body_ref_component.dart';

/// The bodies `Physics2DSystem` keeps: one for every entity with a
/// [TransformComponent] and a [Collider2DComponent], whose
/// [RigidBody2DComponent] says how it moves (none: a static body).
///
/// [syncIn] makes, rebuilds and updates them from their components before
/// the step; [syncOut] writes where the step left them back into the
/// components. An entity's [Physics2DBodyRefComponent] names its body for as
/// long as it has one — the same component when the body is made again.
@internal
final class Physics2DBodies {
  /// Bodies in [physics]; [entities] gets each body's entity while it is
  /// in the simulation. [onBodyGone] hears of each body taken out —
  /// `rebuilt` when a new one takes its place at once.
  Physics2DBodies(this.physics, this.entities, {required this.onBodyGone});

  /// The physics engine the bodies are in.
  final Physics2DEngine physics;

  /// Each body's entity — shared with the characters' bodies.
  final Map<Physics2DBody, Entity> entities;

  /// [body], [entity]'s, left the simulation.
  final void Function(
    Physics2DBody body,
    Entity entity, {
    required bool rebuilt,
  })
  onBodyGone;

  static const List<Type> _query = [TransformComponent, Collider2DComponent];

  /// Below this positional difference (world units), an ECS/body mismatch is
  /// float round-trip noise rather than a deliberate teleport.
  ///
  /// Sync-out writes the body's position straight into the transform, so in
  /// steady state the two agree exactly and this never fires.
  static const double _teleportEpsilon = 1e-4;

  /// Angular counterpart of [_teleportEpsilon], in radians.
  static const double _teleportAngleEpsilon = 1e-5;

  // Only a dynamic body is slowed by damping, as in 3-D: Box2D would also
  // slow a kinematic one, and a moving platform has to keep the velocity it
  // is given.
  static double _linearDampingOf(RigidBody2DComponent rigid) =>
      rigid.isDynamic ? rigid.linearDamping : 0.0;

  static double _angularDampingOf(RigidBody2DComponent rigid) =>
      rigid.isDynamic ? rigid.angularDamping : 0.0;

  /// Every entity with a transform and a collider, whether or not its body
  /// exists yet — in world order, which is also the order bodies are made
  /// in. Rebuilt only when the world's structure changes.
  final List<_BodyLink> _links = [];

  /// The same links by entity, so a rebuild keeps each entity's body.
  final Map<Entity, _BodyLink> _linkByEntity = {};

  /// [World.queryVersion] of [_query] when [_links] was last brought up to
  /// date.
  int _seenStructureVersion = -1;

  /// Links whose bodies leave the simulation at the end of this sync-in —
  /// after this frame's new bodies are made, the order it has always been.
  final List<_BodyLink> _leaving = [];

  /// Gravity as of the last frame; a change wakes every body.
  double _seenGravityX = double.nan;
  double _seenGravityY = double.nan;

  /// This update's time, which a kinematic body moved by its transform has
  /// to get where it was put in ([_stepTime]).
  double _frameTime = 0;

  /// [entity]'s body, or null while it has none.
  Physics2DBody? bodyOf(Entity entity) => _linkByEntity[entity]?.body;

  /// Brings every body up to date with its entity before a step of
  /// [frameTime] seconds: makes the new, makes again the changed, pushes
  /// settings, teleports and carries what gameplay moved, applies what
  /// gameplay asked of a rigid body, and takes out what left.
  void syncIn(World world, double frameTime) {
    _frameTime = frameTime;
    _refreshLinks(world);

    final gx = physics.gravity.x;
    final gy = physics.gravity.y;
    final gravityChanged = gx != _seenGravityX || gy != _seenGravityY;
    _seenGravityX = gx;
    _seenGravityY = gy;
    final context = world.context;
    final definitions = context.definitions;
    // Read once: the project's grid is the same for every body this frame.
    final layers = context.physicsLayers;

    for (final link in _links) {
      // Switched off: out of the simulation until switched back on, when it
      // gets a fresh body where its transform then is.
      if (!link.entity.isActiveInHierarchy) {
        if (link.body != null) _leaving.add(link);
        continue;
      }
      final rigid = link.settings;
      final culled = link.cull?.isActive == false;
      final category = 1 << PhysicsLayers.clampLayer(rigid.layer);
      // What it collides with now: its saved list, or the grid, unless
      // gameplay switched its collisions off for a while.
      final mask =
          (rigid.effectiveCollidesWith ?? layers.maskOf(rigid.layer)) &
          PhysicsLayers.all;

      final before = link.body;
      final body = _bodyFor(link, definitions, category, mask);
      if (body == null) continue;
      var wake = gravityChanged;
      // A body just made has every setting already.
      if (identical(body, before) &&
          !culled &&
          _pushSettings(link, body, category, mask)) {
        wake = true;
      }

      // Opt-in view culling: the body is out of the simulation while its
      // entity is culled, on both backends — held where it is, keeping its
      // velocity, touching and sensed by nothing — and put back, awake,
      // when it is not. Its settings above wait until it is back.
      physics.setBodyActive(body, !culled);
      link.culled = culled;
      if (culled) continue;

      if (_follow(link, body)) wake = true;

      // Woken only when the ECS side has really changed something since the
      // last step — never merely because another frame began. Forcing every
      // body awake every frame kept anything from ever sleeping (and cost a
      // native velocity write per body per step on Box2D).
      if (!wake) {
        wake =
            body.velocity.x != link.outVelocityX ||
            body.velocity.y != link.outVelocityY ||
            body.angularVelocity != link.outAngularVelocity ||
            body.acceleration.x != 0.0 ||
            body.acceleration.y != 0.0 ||
            body.torque != 0.0;
      }
      if (wake) physics.wakeBody(body);
    }

    for (final link in _leaving) {
      _removeBody(link);
    }
    _leaving.clear();

    // Removing Physics2DBodyRefComponent above changed the world's structure,
    // but not in a way _links needs to see: each link keeps its component
    // objects, which moved with their entity.
    _seenStructureVersion = world.queryVersion(_query);
  }

  /// Brings [_links] up to date with [world], when its structure has
  /// changed since the last look: entities that gained a collider are
  /// added, and entities that were destroyed or lost theirs are queued in
  /// [_leaving].
  void _refreshLinks(World world) {
    final version = world.queryVersion(_query);
    if (version == _seenStructureVersion) return;

    _links.clear();
    for (final archetype in world.queryArchetypes(_query)) {
      final ids = archetype.entityIds;
      if (ids.isEmpty) continue;
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(Collider2DComponent)!;
      final rigids = archetype.getColumn(RigidBody2DComponent);
      final velocities = archetype.getColumn(VelocityComponent);
      final culls = archetype.getColumn(CullStateComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final link = _linkByEntity[entity] ??= _BodyLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..collider = colliders[row] as Collider2DComponent
          ..rigid = rigids?[row] as RigidBody2DComponent?
          ..velocity = velocities?[row] as VelocityComponent?
          ..cull = culls?[row] as CullStateComponent?
          ..version = version;
        _links.add(link);
      }
    }

    // Destroyed, or no longer carrying both components.
    _linkByEntity.removeWhere((entity, link) {
      if (link.version == version) return false;
      _leaving.add(link);
      return true;
    });
  }

  /// [link]'s body, made — or made again, moving as it was, when what it
  /// was made from changed: the shape and everything placing it, the
  /// entity's scale, the shape a matching collider follows and the sensor
  /// flag are fixed when a body is made (the native Box2D backend cannot
  /// change them on a live body). Null while it has no shape.
  Physics2DBody? _bodyFor(
    _BodyLink link,
    ComponentDefinitionRegistry definitions,
    int category,
    int mask,
  ) {
    final collider = link.collider;
    final rigid = link.settings;
    final matching = collider.shape == Collider2DShape.matchShape;
    SolidShape2D? look;
    if (matching) {
      link.findLook(definitions);
      look = link.solidNow();
    }
    final (sx, sy) = _scaleKey(collider, link.transform, look);
    var body = link.body;
    double? keepVx, keepVy, keepSpin;
    if (body != null &&
        (!link.builtMatches(collider, sx, sy) ||
            (matching && !link.sameLook(look)) ||
            body.isSensor != rigid.isSensor)) {
      keepVx = body.velocity.x;
      keepVy = body.velocity.y;
      keepSpin = body.angularVelocity;
      _removeBody(link, rebuilt: true);
      body = null;
    }
    if (body != null) return body;

    final entity = link.entity;
    final transform = link.transform;
    final shape = Collider2DGeometry.shapeOf(
      collider,
      entity: entity,
      definitions: definitions,
    );
    // No shape yet — a polygon of too few points, a collider matching the
    // shape of an entity that draws none: no body until it has one.
    if (shape == null) {
      link.remember(collider, sx, sy, look: look, matching: matching);
      // Made again into nothing: its link to the old body goes too.
      if (keepVx != null && entity.isAlive) {
        entity.removeComponent<Physics2DBodyRefComponent>();
      }
      return null;
    }
    final built = Collider2DGeometry.build(
      shape,
      offset: collider.offset,
      rotation: collider.rotation,
      sx: sx,
      sy: sy,
    );
    final mass = Collider2DGeometry.massOf(rigid, built);
    final made = Physics2DBody(
      position: Vector2(transform.position.x, transform.position.y),
      shape: built,
      mass: mass,
      inertia: Collider2DGeometry.inertiaOf(built, mass),
      friction: rigid.friction,
      restitution: rigid.restitution,
      drag: _linearDampingOf(rigid),
      angularDamping: _angularDampingOf(rigid),
      angle: transform.angle,
      useGravity: !rigid.isStatic,
      gravityScale: rigid.effectiveGravityScale,
      bodyType: rigid.bodyType,
      isSensor: rigid.isSensor,
      isOneWay: collider.oneWay,
      oneWayDirection: collider.oneWayDirection,
      fixedRotation: rigid.lockRotation,
      isBullet: rigid.continuousCollision,
      canSleep: rigid.canSleep,
      categoryBits: category,
      maskBits: mask,
      groupIndex: rigid.groupIndex,
    );
    final velocityComp = link.velocity;
    final carried = velocityComp?.velocity;
    if (keepVx != null) {
      // Rebuilt: as it was moving.
      made.velocity.setValues(keepVx, keepVy!);
      made.angularVelocity = keepSpin!;
    } else if (carried != null && (carried.x != 0 || carried.y != 0)) {
      made.velocity.setValues(carried.x, carried.y);
      made.angularVelocity = rigid.initialAngularVelocity;
    } else {
      // New: as it was set to start.
      final v = rigid.initialVelocity;
      made.velocity.setValues(v.dx, v.dy);
      made.angularVelocity = rigid.initialAngularVelocity;
      // The velocity component is pushed into the body every frame, so
      // it has to start the same or it stops the body at once.
      velocityComp?.setVelocityXY(v.dx, v.dy);
    }
    physics.addBody(made);
    link
      ..body = made
      ..automaticMass = rigid.mass <= 0 && !rigid.isStatic
      ..syncOutPending = true
      ..remember(collider, sx, sy, look: look, matching: matching);
    entities[made] = entity;
    // The same component for a body made again: the entity's structure —
    // and every query over it, the render list's too — stays as it was.
    final ref = entity.getComponent<Physics2DBodyRefComponent>();
    if (ref == null) {
      entity.addComponent(Physics2DBodyRefComponent(made));
    } else {
      ref.body = made;
    }
    return made;
  }

  /// Routes each setting of [link]'s live [body] that changed to the engine
  /// — on the Box2D backend each needs a native call, and a plain field
  /// write would only update the Dart mirror. (The shape, its placement,
  /// scale and sensor flag make the body again instead.)
  /// Whether one changed: each can matter to a body at rest, so a change
  /// wakes it.
  bool _pushSettings(
    _BodyLink link,
    Physics2DBody body,
    int category,
    int mask,
  ) {
    final rigid = link.settings;
    final collider = link.collider;
    var changed = false;
    // The automatic mass is worked out from the shape, which only a
    // rebuild changes: again only when the rigid body's own mass or type
    // changed.
    final automatic = rigid.mass <= 0 && !rigid.isStatic;
    if (!automatic || !link.automaticMass || body.mass == 0) {
      final mass = Collider2DGeometry.massOf(rigid, body.shape);
      if (body.mass != mass) {
        body
          ..mass = mass
          ..inertia = Collider2DGeometry.inertiaOf(body.shape, mass);
        changed = true;
      }
    }
    link.automaticMass = automatic;
    final useGravity = !rigid.isStatic;
    if (body.useGravity != useGravity) {
      body.useGravity = useGravity;
      changed = true;
    }
    if (body.restitution != rigid.restitution) {
      physics.setBodyRestitution(body, rigid.restitution);
      changed = true;
    }
    if (body.friction != rigid.friction) {
      physics.setBodyFriction(body, rigid.friction);
      changed = true;
    }
    final linearDamping = _linearDampingOf(rigid);
    if (body.drag != linearDamping) {
      physics.setBodyDamping(body, linearDamping);
      changed = true;
    }
    final angularDamping = _angularDampingOf(rigid);
    if (body.angularDamping != angularDamping) {
      physics.setBodyAngularDamping(body, angularDamping);
      changed = true;
    }
    if (body.isBullet != rigid.continuousCollision) {
      physics.setBodyBullet(body, rigid.continuousCollision);
    }
    if (body.canSleep != rigid.canSleep) {
      physics.setBodyCanSleep(body, rigid.canSleep);
      changed = true;
    }
    if (body.isOneWay != collider.oneWay ||
        body.oneWayDirection != collider.oneWayDirection) {
      physics.setBodyOneWay(
        body,
        collider.oneWay,
        direction: collider.oneWayDirection,
      );
      changed = true;
    }
    if (body.bodyType != rigid.bodyType) {
      physics.setBodyType(body, rigid.bodyType);
      changed = true;
    }
    // The scale gameplay gave it for now, or else its saved one.
    final gravityScale = rigid.effectiveGravityScale;
    if (body.gravityScale != gravityScale) {
      physics.setBodyGravityScale(body, gravityScale);
      changed = true;
    }
    if (body.fixedRotation != rigid.lockRotation) {
      physics.setBodyFixedRotation(body, rigid.lockRotation);
      changed = true;
    }
    // Layers, the project's grid, or the body's own list changed.
    if (body.categoryBits != category ||
        body.maskBits != mask ||
        body.groupIndex != rigid.groupIndex) {
      physics.setBodyFilter(
        body,
        categoryBits: category,
        maskBits: mask,
        groupIndex: rigid.groupIndex,
      );
      changed = true;
    }
    return changed;
  }

  /// Pushes ECS state → [body] immediately before stepping. This is the
  /// only place ECS state flows into the body each frame; sync-out is the
  /// only place it flows back out — so within a frame nothing else fights
  /// for authority over [TransformComponent]. Whether gameplay asked for
  /// something that wakes the body.
  bool _follow(_BodyLink link, Physics2DBody body) {
    final transform = link.transform;
    final velocityComp = link.velocity;
    var wake = false;
    // A position write on the ECS side means a teleport: a respawn, a
    // checkpoint, a level load, a warp. Pushed through the engine's
    // setBodyTransform so it actually reaches the native simulation —
    // assigning body.position directly is discarded by the Box2D backend's
    // sync-back after the next step. setBodyTransform also wakes the body.
    //
    // Gated on real divergence, not done unconditionally: Box2D documents
    // SetTransform as expensive (it rebuilds broad-phase proxies and drops
    // the solver's warm start), and this runs for every body every frame.
    // Ordinary motion never trips it, because sync-out wrote this exact
    // value back from the body a moment ago.
    final dx = transform.position.x - body.position.x;
    final dy = transform.position.y - body.position.y;
    // A turn apart is the same angle: the native backend keeps its angles
    // within ±π, the transform does not.
    final dAngle = angleBetween(transform.angle, body.angle);
    final moved =
        dx.abs() > _teleportEpsilon ||
        dy.abs() > _teleportEpsilon ||
        dAngle.abs() > _teleportAngleEpsilon;
    // A kinematic body moved there by gameplay — a platform on a path — is
    // carried there by the physics over this frame's steps, as 3-D moves
    // one: what it carries goes with it, and a character on it reads its
    // velocity.
    final carry = moved && link.settings.bodyType == Body2DType.kinematic;
    if (moved && !carry) {
      physics.setBodyTransform(
        body,
        transform.position.x,
        transform.position.y,
        angle: transform.angle,
      );
      // A static body is not synced out every frame; this once, so its
      // transform takes the position the engine actually stored.
      link.syncOutPending = true;
    }
    if (velocityComp != null) {
      body.velocity.setValues(velocityComp.velocity.x, velocityComp.velocity.y);
    }
    if (_flushCommands(link.rigid, body, velocityComp)) wake = true;
    if (carry) {
      final time = _stepTime;
      body.velocity.setValues(dx / time, dy / time);
      body.angularVelocity = dAngle / time;
      velocityComp?.setVelocityXY(body.velocity.x, body.velocity.y);
      link.carried = true;
      wake = true;
    } else if (link.carried) {
      // Gameplay stopped moving it: it stops too, rather than going on
      // with the velocity its last move gave it.
      link.carried = false;
      body.velocity.setZero();
      body.angularVelocity = 0;
      velocityComp?.setVelocityXY(0, 0);
    }
    return wake;
  }

  /// How long this frame's steps last, together: what a kinematic body
  /// moved by its transform has to get there in. A fixed-step frame that
  /// runs none counts as one step; the next frame starts again from where
  /// the body really is.
  double get _stepTime {
    if (!physics.fixedTimestep) return math.max(_frameTime, 1e-6);
    const fixed = Physics2DEngine.fixedDeltaTime;
    final pending = math.min(
      physics.alpha * fixed + _frameTime,
      fixed * Physics2DEngine.maxSubSteps,
    );
    return math.max((pending / fixed + 1e-9).floor(), 1) * fixed;
  }

  /// [a] − [b], a whole number of turns taken off it: between −π and π.
  static double angleBetween(double a, double b) {
    final d = a - b;
    if (d.abs() <= math.pi) return d;
    return d - (d / (2 * math.pi)).roundToDouble() * 2 * math.pi;
  }

  /// Applies what gameplay asked of [rigid] since the last step — a
  /// velocity to set, impulses, forces — to [body], and clears it. Whether
  /// anything was asked (which wakes the body).
  bool _flushCommands(
    RigidBody2DComponent? rigid,
    Physics2DBody body,
    VelocityComponent? velocityComp,
  ) {
    if (rigid == null) return false;
    var asked = rigid.pendingWake;
    final velocity = rigid.pendingVelocity;
    if (velocity != null) {
      body.velocity.setValues(velocity.dx, velocity.dy);
      // The velocity component is pushed into the body every frame: it has
      // to say the same, or it takes the velocity back next frame.
      velocityComp?.setVelocityXY(velocity.dx, velocity.dy);
      asked = true;
    }
    final spin = rigid.pendingAngularVelocity;
    if (spin != null) {
      body.angularVelocity = spin;
      asked = true;
    }
    final impulse = rigid.pendingImpulse;
    if (impulse != Offset.zero) {
      physics.applyLinearImpulse(body, impulse.dx, impulse.dy);
      velocityComp?.setVelocityXY(body.velocity.x, body.velocity.y);
      asked = true;
    }
    if (rigid.pendingAngularImpulse != 0) {
      body.angularVelocity += rigid.pendingAngularImpulse * body.inverseInertia;
      asked = true;
    }
    final force = rigid.pendingForce;
    if (force != Offset.zero) {
      body.applyForce(Vector2(force.dx, force.dy));
      asked = true;
    }
    if (rigid.pendingTorque != 0) {
      body.applyTorque(rigid.pendingTorque);
      asked = true;
    }
    if (!asked) return false;
    rigid
      ..pendingVelocity = null
      ..pendingAngularVelocity = null
      ..pendingImpulse = Offset.zero
      ..pendingAngularImpulse = 0
      ..pendingForce = Offset.zero
      ..pendingTorque = 0
      ..pendingWake = false;
    return true;
  }

  /// The entity's scale as the collider is built with it: its sign dropped
  /// for a shape a mirror leaves as it was, so a character turning to face
  /// the other way by a negative scale is not built again. [look] is the
  /// outline a matching collider follows.
  static (double, double) _scaleKey(
    Collider2DComponent collider,
    TransformComponent transform,
    SolidShape2D? look,
  ) {
    final sx = transform.scale.x, sy = transform.scale.y;
    return _isMirrorSymmetric(collider, look) ? (sx.abs(), sy.abs()) : (sx, sy);
  }

  /// Whether mirroring [collider] about its entity's centre leaves it as it
  /// was: an unturned, centred box, circle or capsule — or one matching an
  /// outline a mirror leaves as it is ([look]; a sprite's box too).
  static bool _isMirrorSymmetric(
    Collider2DComponent collider,
    SolidShape2D? look,
  ) {
    if (collider.offset != Offset.zero || collider.rotation != 0) return false;
    return switch (collider.shape) {
      Collider2DShape.box ||
      Collider2DShape.circle ||
      Collider2DShape.capsule => true,
      Collider2DShape.matchShape =>
        look == null || !Collider2DGeometry.solidMirrors(look),
      _ => false,
    };
  }

  /// Writes where the step left each moving body into its components —
  /// [TransformComponent] (after `capturePrevious`, so a render can
  /// interpolate), [VelocityComponent] and the rigid body's runtime fields.
  ///
  /// When no step ran ([stepped] false — a fixed-step engine on a frame
  /// shorter than its step), a kinematic body that gameplay is moving by its
  /// transform is left where gameplay put it: the body has not gone
  /// anywhere yet, and writing its pose back threw the move away. The next
  /// sync-in carries it over both frames' moves.
  void syncOut({required bool stepped}) {
    for (final link in _links) {
      final body = link.body;
      if (body == null || link.culled) continue; // culled: out of the step
      if (!stepped && link.carried) continue;

      // A static body never moves by itself, so its transform only needs
      // the engine's position once — when it was made or teleported.
      if (!body.isStatic) {
        final transform = link.transform;
        // Capture previous pose for sub-frame render interpolation.
        transform.capturePrevious();
        transform.setPlanarPose(
          body.position.x,
          body.position.y,
          // Within half a turn of where it was, so a body spinning past ±π
          // is drawn going on round, not turning back the long way.
          transform.angle + angleBetween(body.angle, transform.angle),
        );
        link.syncOutPending = false;
      } else if (link.syncOutPending) {
        // Placed, not stepped: drawn where it is, not between two poses.
        final transform = link.transform;
        transform
          ..setPlanarPose(
            body.position.x,
            body.position.y,
            transform.angle + angleBetween(body.angle, transform.angle),
          )
          ..settlePrevious();
        link.syncOutPending = false;
      } else {
        // Its previous pose has to stay its pose too. Something outside
        // physics can leave it behind — a play snapshot restored over the
        // transform, an editor write — and render interpolation would then
        // keep drawing the body somewhere between there and here.
        final transform = link.transform;
        final prev = transform.prevPosition, now = transform.position;
        if (prev.x != now.x ||
            prev.y != now.y ||
            transform.prevAngle != transform.angle) {
          transform.settlePrevious();
        }
      }

      final velocityComp = link.velocity;
      if (velocityComp != null) {
        velocityComp.setVelocityXY(body.velocity.x, body.velocity.y);
        // MovementSystem skips entities with a collider (this system owns
        // their integration instead), so its maxSpeed clamp never reaches
        // them unless applied here too.
        velocityComp.clampToMaxSpeed();
      }
      final rigid = link.rigid;
      if (rigid != null) {
        final vx = body.velocity.x, vy = body.velocity.y;
        // A new Offset only when it changed: most bodies are at rest, or
        // move as they did.
        final v = rigid.linearVelocity;
        if (v.dx != vx || v.dy != vy) rigid.linearVelocity = Offset(vx, vy);
        rigid
          ..angularVelocity = body.angularVelocity
          ..isAwake = body.isAwake;
      }
      link
        ..outVelocityX = body.velocity.x
        ..outVelocityY = body.velocity.y
        ..outAngularVelocity = body.angularVelocity;
    }
  }

  /// Takes [link]'s body out of the simulation, if it has one — [rebuilt]
  /// when a new body takes its place at once, which keeps the entity's
  /// [Physics2DBodyRefComponent] for it.
  void _removeBody(_BodyLink link, {bool rebuilt = false}) {
    final body = link.body;
    if (body == null) return;
    link
      ..body = null
      ..culled = false;
    physics.removeBody(body);
    entities.remove(body);
    onBodyGone(body, link.entity, rebuilt: rebuilt);
    final rigid = link.rigid;
    if (rigid != null) {
      rigid
        ..isGrounded = false
        ..groundEntity = null
        ..groundNormal = const Offset(0, -1);
    }
    if (!rebuilt && link.entity.isAlive) {
      link.entity.removeComponent<Physics2DBodyRefComponent>();
    }
  }

  /// Takes every body out of the simulation and forgets every entity.
  void removeAll() {
    for (final link in [..._linkByEntity.values, ..._leaving]) {
      _removeBody(link);
    }
    _leaving.clear();
    _links.clear();
    _linkByEntity.clear();
    _seenStructureVersion = -1;
    _seenGravityX = double.nan;
    _seenGravityY = double.nan;
  }
}

/// What [Physics2DBodies] keeps per entity: the components it reads every
/// frame — looked up once, when the world's structure changes, instead of
/// every frame — and the entity's body, once made.
final class _BodyLink {
  _BodyLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late Collider2DComponent collider;
  RigidBody2DComponent? rigid;
  VelocityComponent? velocity;
  CullStateComponent? cull;

  /// What a collider without a rigid body is: a static body.
  late final RigidBody2DComponent _static = RigidBody2DComponent(
    bodyType: Body2DType.static,
  );

  /// How the body moves: its rigid body, or a static body's defaults.
  RigidBody2DComponent get settings => rigid ?? _static;

  /// [World.queryVersion] of the rebuild that last saw [entity].
  int version = -1;

  Physics2DBody? body;

  /// Whether the body's mass was worked out from its shape when it was
  /// last weighed: then only a rebuild, or a change of the rigid body's own
  /// mass or type, weighs it again.
  bool automaticMass = false;

  /// Culled this frame: the body is out of the simulation and nothing is
  /// synced out.
  bool culled = false;

  /// The transform still has to take the body's position — once, for a
  /// static body that is otherwise never synced out.
  bool syncOutPending = false;

  // What the body was built from: the collider's shape and placement and
  // the entity's scale (Physics2DBodies._scaleKey) — the scale within
  // BodyRebuild.scaleTolerance of it. Any of them changing builds it
  // again, as does the look a matching collider follows ([sameLook]).
  Collider2DShape? _shape;
  double _w = 0, _h = 0, _radius = 0, _height = 0, _corner = 0, _thickness = 0;
  double _ox = 0, _oy = 0, _rotation = 0, _cx = 0, _cy = 0, _sx = 0, _sy = 0;
  bool _loop = false;
  List<Offset> _points = const [];

  void remember(
    Collider2DComponent c,
    double sx,
    double sy, {
    required SolidShape2D? look,
    required bool matching,
  }) {
    _shape = c.shape;
    _w = c.size.x;
    _h = c.size.y;
    _radius = c.radius;
    _height = c.height;
    _corner = c.cornerRadius;
    _thickness = c.thickness;
    _loop = c.loop;
    _ox = c.offset.dx;
    _oy = c.offset.dy;
    _rotation = c.rotation;
    _cx = c.scale.x;
    _cy = c.scale.y;
    _sx = sx;
    _sy = sy;
    _points = List.of(c.points);
    if (matching) _rememberLook(look);
  }

  bool builtMatches(Collider2DComponent c, double sx, double sy) {
    if (_shape != c.shape ||
        _w != c.size.x ||
        _h != c.size.y ||
        _radius != c.radius ||
        _height != c.height ||
        _corner != c.cornerRadius ||
        _thickness != c.thickness ||
        _loop != c.loop ||
        _ox != c.offset.dx ||
        _oy != c.offset.dy ||
        _rotation != c.rotation ||
        _cx != c.scale.x ||
        _cy != c.scale.y ||
        !BodyRebuild.sameScale(_sx, sx) ||
        !BodyRebuild.sameScale(_sy, sy)) {
      return false;
    }
    final points = c.points;
    if (points.length != _points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (points[i] != _points[i]) return false;
    }
    return true;
  }

  // The look of the entity, for a collider matching it — its components
  // that are outlines ([SolidShape2DSource]), in its order, and those with
  // a size (a sprite) — found when [version] was [_lookVersion]: again only
  // after the world's structure changes, not every frame.
  int _lookVersion = -2;
  List<SolidShape2DSource> _lookSources = const [];
  List<(Component, ComponentExtent)> _lookSized = const [];

  /// Finds what the entity draws, unless it was found since the world's
  /// structure last changed.
  void findLook(ComponentDefinitionRegistry definitions) {
    if (_lookVersion == version) return;
    _lookVersion = version;
    final sources = <SolidShape2DSource>[];
    final sized = <(Component, ComponentExtent)>[];
    for (final c in entity.components) {
      if (c is Collider2DComponent || c is RigidBody2DComponent) continue;
      if (c is SolidShape2DSource) sources.add(c as SolidShape2DSource);
      final extent = definitions.definitionFor(c)?.extent;
      if (extent != null) sized.add((c, extent));
    }
    _lookSources = sources.isEmpty ? const [] : sources;
    _lookSized = sized.isEmpty ? const [] : sized;
  }

  /// The outline a matching collider takes now, as
  /// [Collider2DGeometry.visualShapeOf] finds it: the first of the entity's
  /// outlines that has one; null for none (then its largest size).
  SolidShape2D? solidNow() {
    for (final source in _lookSources) {
      final solid = source.solidShape2D;
      if (solid != null) return solid;
    }
    return null;
  }

  /// The largest size among the entity's sized components into [_sizeW]
  /// and [_sizeH], as [Collider2DGeometry.largestSize] takes it; false for
  /// none.
  bool _largestSize() {
    var found = false;
    for (final (c, extent) in _lookSized) {
      final size = extent.sizeOf(c);
      if (size == null || size.width <= 0 || size.height <= 0) continue;
      if (!found || size.width * size.height > _sizeW * _sizeH) {
        _sizeW = size.width;
        _sizeH = size.height;
        found = true;
      }
    }
    return found;
  }

  double _sizeW = 0, _sizeH = 0;

  // The look the body was built from: the outline, or else the box of the
  // largest size ([_builtSized]), or nothing.
  SolidShape2D? _builtSolid;
  bool _builtSized = false;
  double _builtW = 0, _builtH = 0;

  /// Whether [look] — the entity's outline now ([solidNow]) — or, with
  /// none, its largest size is what the body was built from.
  bool sameLook(SolidShape2D? look) {
    final built = _builtSolid;
    if (look != null || built != null) {
      return identical(look, built) || look == built;
    }
    if (!_largestSize()) return !_builtSized;
    return _builtSized && _builtW == _sizeW && _builtH == _sizeH;
  }

  void _rememberLook(SolidShape2D? look) {
    _builtSolid = look;
    _builtSized = look == null && _largestSize();
    _builtW = _builtSized ? _sizeW : 0;
    _builtH = _builtSized ? _sizeH : 0;
  }

  /// Moved by its transform last frame, as a kinematic body is carried.
  bool carried = false;

  /// The body's velocity as the last step left it. Anything different at
  /// the next sync-in was written since, and wakes the body.
  double outVelocityX = 0.0;
  double outVelocityY = 0.0;
  double outAngularVelocity = 0.0;
}
