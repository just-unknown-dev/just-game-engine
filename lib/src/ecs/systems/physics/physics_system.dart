library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import 'package:just_physics_engine/just_physics_engine.dart';
import 'package:just_dart/just_dart.dart';
import '../../base/system_priorities.dart';
import '../../../subsystems/physics/physics_layers.dart';
import 'collider_geometry.dart';
import 'physics_characters_2d.dart';
import 'physics_events_2d.dart';

/// Physics system — the ECS front end for [PhysicsEngine], in step with
/// the 3-D `PhysicsSystem3D`.
///
/// Owns the [PhysicsBody] lifecycle for every entity with a [Collider2D]:
/// its [RigidBody2D] says how it moves (a collider alone is a static body).
/// Each frame it syncs component state into the body, applies the forces,
/// impulses and velocities gameplay asked for ([RigidBody2D.addForce] and
/// the rest), steps [physics] once, then syncs the result back into
/// [TransformComponent], [VelocityComponent] and the rigid body's runtime
/// fields, and fires [CollisionEnter2DEvent], [CollisionStay2DEvent] (with
/// [reportContactStay]), [CollisionExit2DEvent], [SensorEnter2DEvent] and
/// [SensorExit2DEvent] on [World.events].
///
/// It moves every [CharacterBody2D] too, before stepping
/// ([PhysicsCharacters2D]): a character's own body is a kinematic one, so its
/// events are those of a kinematic body.
///
/// [physics] is stepped *here*, inline, rather than as a separate `Engine`
/// update task — that keeps this frame's gameplay-set velocity (e.g. from a
/// player-control system running earlier in the same ECS pass) reaching the
/// physics step the same frame it was set, instead of lagging a frame behind.
///
/// **Sleep.** A body at rest may fall asleep, as the physics engine decides,
/// and stays asleep until something disturbs it. Anything the ECS does to a
/// body wakes it: a velocity different from the one the last step left
/// (written to [VelocityComponent] or to the body), a teleport through
/// [TransformComponent], a force, impulse or torque waiting to be applied, a
/// changed [RigidBody2D] or [Collider2D] setting, the body coming back from
/// view culling, or a change of gravity. A player pressing a direction or
/// jump therefore always moves at once.
///
/// **Removal.** Taking the system out of its world ([World.removeSystem],
/// [World.clearSystems]) or disposing it removes every body it made from
/// [physics]. The engine is shared, and bodies left behind went on
/// colliding as invisible ghosts.
class PhysicsSystem extends System {
  /// [physics] is the single physics implementation this system drives —
  /// pass `engine.physics`. On native platforms that's the Box2D FFI
  /// backend; on web, the pure-Dart backend. Both share the same API.
  ///
  /// Pass the same [camera] as the `RenderSystem`, or the collider outlines
  /// drawn in debug builds land at their world coordinates read as screen
  /// pixels — away from the entities they outline.
  PhysicsSystem(this.physics, {this.camera, this.reportContactStay = false});

  /// The subsystem physics engine this system steps and syncs against.
  final PhysicsEngine physics;

  /// Whether [CollisionStay2DEvent] is fired, each step, for every pair of
  /// bodies still touching. Off by default: most games need only enter and
  /// exit.
  bool reportContactStay;

  @override
  int get priority => SystemPriorities.physics;

  /// Camera used to apply the world-to-screen transform during debug rendering.
  /// Must match the camera used by [RenderSystem] so collider outlines stay
  /// aligned with their visual counterparts.
  GameCamera? camera;

  @override
  List<Type> get requiredComponents => [TransformComponent, Collider2D];

  /// Below this positional difference (world units), an ECS/body mismatch is
  /// float round-trip noise rather than a deliberate teleport.
  ///
  /// Sync-out writes the body's position straight into the transform, so in
  /// steady state the two agree exactly and this never fires.
  static const double _teleportEpsilon = 1e-4;

  /// Angular counterpart of [_teleportEpsilon], in radians.
  static const double _teleportAngleEpsilon = 1e-5;

  /// The mass, in kg, of a square unit of a body whose own mass is 0: water
  /// 1 m (100 units) deep, as a 3-D body is worked out from its volume. A
  /// 100 × 100 square weighs 1000 kg, as a 1 m cube does.
  static const double autoMassPerSquareUnit = 0.1;

  /// What [rigid] weighs with [shape]: nothing when it is static, its own
  /// [RigidBody2D.mass] when that is set, and otherwise
  /// [autoMassPerSquareUnit] for each square unit of [shape]. A line (a
  /// segment or a chain) counts its bounds, at least a unit each way, as a
  /// 3-D shape with no volume does.
  static double massOf(RigidBody2D rigid, CollisionShape shape) {
    if (rigid.isStatic) return 0.0;
    if (rigid.mass > 0) return rigid.mass;
    var area = shape.area;
    if (!(area > 0)) {
      final bounds = shape.getBounds(Offset.zero);
      area = math.max(bounds.width, 1.0) * math.max(bounds.height, 1.0);
    }
    return area * autoMassPerSquareUnit;
  }

  // Only a dynamic body is slowed by damping, as in 3-D: Box2D would also
  // slow a kinematic one, and a moving platform has to keep the velocity it
  // is given.
  static double _linearDampingOf(RigidBody2D rigid) =>
      rigid.isDynamic ? rigid.linearDamping : 0.0;

  static double _angularDampingOf(RigidBody2D rigid) =>
      rigid.isDynamic ? rigid.angularDamping : 0.0;

  /// Every entity with a transform and a collider, whether or not its body
  /// exists yet — in world order, which is also the order bodies are made
  /// in. Rebuilt only when the world's structure changes.
  final List<_BodyLink> _links = [];

  /// The same links by entity, so a rebuild keeps each entity's body.
  final Map<Entity, _BodyLink> _linkByEntity = {};

  /// [World.structureVersion] when [_links] was last brought up to date.
  int _seenStructureVersion = -1;

  /// Whether the world had no bodies at the last update.
  bool _wasEmpty = false;

  /// Links whose bodies leave the simulation at the end of this sync-in —
  /// after this frame's new bodies are made, the order it has always been.
  final List<_BodyLink> _leaving = [];

  /// Gravity as of the last frame; a change wakes every body.
  double _seenGravityX = double.nan;
  double _seenGravityY = double.nan;

  /// Reverse lookup for translating polled body pairs back to entities.
  final Map<PhysicsBody, Entity> _bodyEntityMap = {};

  // Per-entity count of currently-active ground-normal contacts, so
  // isGrounded stays true for the whole duration a body rests on something
  // (not just the first frame of contact) using only begin/end events —
  // avoids needing a "poll all active contacts every frame" API from
  // [PhysicsEngine].
  final Map<Entity, int> _groundContactCount = {};

  // Which entity a given contact pair grounded, if any — consulted on
  // contact-end to know which counter to decrement.
  final Map<BodyPair, Entity> _groundedEntityForPair = {};

  // The pairs touching, for [CollisionStay2DEvent]: the normal they began
  // with, and whether they began this step.
  final Map<BodyPair, (Offset, bool)> _touching = {};

  /// The entity [body] belongs to while this system keeps it in the
  /// simulation — null for a body it did not make, or one it has removed.
  ///
  /// A body's joints go with it: [PhysicsJointBindingSystem] asks this
  /// before destroying a joint the physics engine has already destroyed.
  Entity? entityForBody(PhysicsBody body) => _bodyEntityMap[body];

  /// The simulated body of [entity], or null while it has none — for a
  /// character, the body sensors and rays see it by.
  PhysicsBody? bodyOf(Entity entity) => _linkByEntity[entity]?.body ?? _characters.bodyOf(entity);

  /// The characters this system moves.
  late final PhysicsCharacters2D _characters = PhysicsCharacters2D(
    physics,
    onBody: (body, entity) => _bodyEntityMap[body] = entity,
    onBodyGone: (body) {
      final entity = _bodyEntityMap.remove(body);
      if (entity != null) _forgetGroundContactsOf(body, entity);
      _touching.removeWhere((pair, _) => identical(pair.a, body) || identical(pair.b, body));
    },
  );

  @override
  void update(double deltaTime) {
    _syncIn();
    if (deltaTime > 0) _characters.move(world, deltaTime, entityForBody);
    // A world with no bodies (a 3-D scene, a menu) is not stepped; the step
    // after the last body goes still runs, so its end events get through.
    final empty = physics.bodyCount == 0;
    if (!(empty && _wasEmpty)) physics.update(deltaTime);
    _wasEmpty = empty;
    _syncOut();
    _dispatchEvents();
  }

  @override
  void onRemovedFromWorld() => _removeAllBodies();

  @override
  void dispose() => _removeAllBodies();

  /// Brings [_links] up to date with the world, when its structure has
  /// changed since the last look: entities that gained a collider are
  /// added, and entities that were destroyed or lost theirs are queued in
  /// [_leaving].
  void _refreshLinks() {
    final version = world.structureVersion;
    if (version == _seenStructureVersion) return;

    _links.clear();
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final ids = archetype.entityIds;
      if (ids.isEmpty) continue;
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(Collider2D)!;
      final rigids = archetype.getColumn(RigidBody2D);
      final velocities = archetype.getColumn(VelocityComponent);
      final culls = archetype.getColumn(CullStateComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = world.getEntity(ids[row]);
        if (entity == null) continue;
        final link = _linkByEntity[entity] ??= _BodyLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..collider = colliders[row] as Collider2D
          ..rigid = rigids?[row] as RigidBody2D?
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

  void _syncIn() {
    _refreshLinks();

    final gx = physics.gravity.x;
    final gy = physics.gravity.y;
    final gravityChanged = gx != _seenGravityX || gy != _seenGravityY;
    _seenGravityX = gx;
    _seenGravityY = gy;
    final definitions = world.context.definitions;

    for (final link in _links) {
      final entity = link.entity;
      // Switched off: out of the simulation until switched back on, when it
      // gets a fresh body where its transform then is.
      if (!entity.isActive) {
        if (link.body != null) _leaving.add(link);
        continue;
      }

      final transform = link.transform;
      final collider = link.collider;
      final rigid = link.settings;
      final velocityComp = link.velocity;
      final culled = link.cull?.isActive == false;

      var body = link.body;
      var wake = gravityChanged;
      // The shape (and everything placing it), the entity's scale, the
      // sensor flag and locked rotation are fixed when a body is made — the
      // native Box2D backend cannot change them on a live body — so a
      // change to any rebuilds it, carrying over how it was moving.
      final (sx, sy) = _scaleKey(collider, transform, link);
      final matchKey = collider.shape == ColliderShape2D.matchShape
          ? ColliderGeometry.visualKeyOf(entity, definitions: definitions)
          : null;
      double? keepVx, keepVy, keepSpin;
      if (body != null &&
          (!link.builtMatches(collider, sx, sy, matchKey) ||
              body.isSensor != rigid.isSensor ||
              body.fixedRotation != rigid.lockRotation)) {
        keepVx = body.velocity.x;
        keepVy = body.velocity.y;
        keepSpin = body.angularVelocity;
        _removeBody(link);
        body = null;
      }
      final layers = world.context.physicsLayers;
      final category = 1 << PhysicsLayers.clampLayer(rigid.layer);
      final mask = (rigid.collidesWith ?? layers.maskOf(rigid.layer)) & PhysicsLayers.all;
      if (body == null) {
        final shape = ColliderGeometry.shapeOf(collider, entity: entity, definitions: definitions);
        // No shape yet — a polygon of too few points, a collider matching
        // the shape of an entity that draws none: no body until it has one.
        if (shape == null) {
          link.remember(collider, sx, sy, matchKey);
          continue;
        }
        final built = ColliderGeometry.build(
          shape,
          offset: collider.offset,
          rotation: collider.rotation,
          sx: sx,
          sy: sy,
        );
        body = PhysicsBody(
          position: Vector2(transform.position.x, transform.position.y),
          shape: built,
          mass: massOf(rigid, built),
          friction: rigid.friction,
          restitution: rigid.restitution,
          drag: _linearDampingOf(rigid),
          angularDamping: _angularDampingOf(rigid),
          angle: transform.angle,
          useGravity: !rigid.isStatic,
          gravityScale: rigid.gravityScale,
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
        final carried = velocityComp?.velocity;
        if (keepVx != null) {
          // Rebuilt: as it was moving.
          body.velocity.setValues(keepVx, keepVy!);
          body.angularVelocity = keepSpin!;
        } else if (carried != null && (carried.x != 0 || carried.y != 0)) {
          body.velocity.setValues(carried.x, carried.y);
          body.angularVelocity = rigid.initialAngularVelocity;
        } else {
          // New: as it was set to start.
          final v = rigid.initialVelocity;
          body.velocity.setValues(v.dx, v.dy);
          body.angularVelocity = rigid.initialAngularVelocity;
          // The velocity component is pushed into the body every frame, so
          // it has to start the same or it stops the body at once.
          velocityComp?.setVelocityXY(v.dx, v.dy);
        }
        physics.addBody(body);
        link
          ..body = body
          ..syncOutPending = true
          ..wasCulled = false
          ..remember(collider, sx, sy, matchKey);
        _bodyEntityMap[body] = entity;
        entity.addComponent(PhysicsBodyRefComponent(body));
      } else {
        // Each setting that changes can matter to a body at rest, so a
        // change wakes it. Routed through the engine rather than written to
        // the body: on the Box2D backend each needs a native call, and a
        // plain field write would only update the Dart mirror. (The shape,
        // its placement, scale, sensor and locked rotation rebuild the body
        // instead; see above.)
        final mass = massOf(rigid, body.shape);
        if (body.mass != mass) {
          body.mass = mass;
          wake = true;
        }
        final useGravity = !rigid.isStatic;
        if (body.useGravity != useGravity) {
          body.useGravity = useGravity;
          wake = true;
        }
        if (body.restitution != rigid.restitution) {
          physics.setBodyRestitution(body, rigid.restitution);
          wake = true;
        }
        if (body.friction != rigid.friction) {
          physics.setBodyFriction(body, rigid.friction);
          wake = true;
        }
        final linearDamping = _linearDampingOf(rigid);
        if (body.drag != linearDamping) {
          physics.setBodyDamping(body, linearDamping);
          wake = true;
        }
        final angularDamping = _angularDampingOf(rigid);
        if (body.angularDamping != angularDamping) {
          physics.setBodyAngularDamping(body, angularDamping);
          wake = true;
        }
        if (body.isBullet != rigid.continuousCollision) {
          physics.setBodyBullet(body, rigid.continuousCollision);
        }
        if (body.canSleep != rigid.canSleep) {
          physics.setBodyCanSleep(body, rigid.canSleep);
          wake = true;
        }
        if (body.isOneWay != collider.oneWay || body.oneWayDirection != collider.oneWayDirection) {
          physics.setBodyOneWay(body, collider.oneWay, direction: collider.oneWayDirection);
          wake = true;
        }
        if (body.bodyType != rigid.bodyType) {
          physics.setBodyType(body, rigid.bodyType);
          wake = true;
        }
        if (body.gravityScale != rigid.gravityScale) {
          physics.setBodyGravityScale(body, rigid.gravityScale);
          wake = true;
        }
        // Layers, the project's grid, or the body's own list changed.
        if (body.categoryBits != category || body.maskBits != mask || body.groupIndex != rigid.groupIndex) {
          physics.setBodyFilter(
            body,
            categoryBits: category,
            maskBits: mask,
            groupIndex: rigid.groupIndex,
          );
          wake = true;
        }
      }

      // Opt-in view culling: freeze the body in place while inactive rather
      // than stepping it, matching the pre-unification behaviour of
      // excluding culled entities from force application/broad-phase.
      body.isActive = !culled;
      link.culled = culled;
      if (culled) {
        link.wasCulled = true;
        continue;
      }
      if (link.wasCulled) {
        link.wasCulled = false;
        wake = true;
      }

      // Push ECS state → body immediately before stepping. This is the only
      // place ECS state flows into the body each frame; sync-out (below) is
      // the only place it flows back out — so within a frame nothing else
      // fights this system for authority over TransformComponent. Pushing
      // position (not just velocity) every frame is what makes an external
      // teleport/spawn write to TransformComponent take effect next step.
      // A position write on the ECS side means a teleport: a respawn, a
      // checkpoint, a level load, a warp. Push it through the engine's
      // setBodyTransform so it actually reaches the native simulation —
      // assigning body.position directly is discarded by the Box2D backend's
      // sync-back after the next step. setBodyTransform also wakes the body.
      //
      // Gated on real divergence, not done unconditionally: Box2D documents
      // SetTransform as expensive (it rebuilds broad-phase proxies and drops
      // the solver's warm start), and this runs for every body every frame.
      // Ordinary motion never trips it, because sync-out wrote this exact
      // value back from the body a moment ago.
      final dx = (transform.position.x - body.position.x).abs();
      final dy = (transform.position.y - body.position.y).abs();
      final dAngle = (transform.angle - body.angle).abs();
      if (dx > _teleportEpsilon || dy > _teleportEpsilon || dAngle > _teleportAngleEpsilon) {
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
      if (wake) {
        body.isAwake = true;
        body.sleepTimer = 0.0;
      }
    }

    for (final link in _leaving) {
      _removeBody(link);
    }
    _leaving.clear();

    // Adding and removing PhysicsBodyRefComponent above changed the world's
    // structure, but not in a way _links needs to see: each link keeps its
    // component objects, which moved with their entity.
    _seenStructureVersion = world.structureVersion;
  }

  /// Applies what gameplay asked of [rigid] since the last step — a
  /// velocity to set, impulses, forces — to [body], and clears it. Whether
  /// anything was asked (which wakes the body).
  bool _flushCommands(RigidBody2D? rigid, PhysicsBody body, VelocityComponent? velocityComp) {
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
  /// the other way by a negative scale is not built again.
  static (double, double) _scaleKey(Collider2D collider, TransformComponent transform, _BodyLink link) {
    final sx = transform.scale.x, sy = transform.scale.y;
    return _isMirrorSymmetric(collider, link.entity) ? (sx.abs(), sy.abs()) : (sx, sy);
  }

  /// Whether mirroring [collider] about its entity's centre leaves it as it
  /// was: an unturned, centred box, circle or capsule — or one matching a
  /// Rectangle, Circle, Capsule or sprite.
  static bool _isMirrorSymmetric(Collider2D collider, Entity entity) {
    if (collider.offset != Offset.zero || collider.rotation != 0) return false;
    return switch (collider.shape) {
      ColliderShape2D.box || ColliderShape2D.circle || ColliderShape2D.capsule => true,
      ColliderShape2D.matchShape => !entity.components.any((c) => c is PolygonComponent || c is LineComponent),
      _ => false,
    };
  }

  void _syncOut() {
    for (final link in _links) {
      final body = link.body;
      if (body == null || link.culled) continue; // culled — body is frozen

      // A static body never moves by itself, so its transform only needs
      // the engine's position once — when it was made or teleported.
      if (!body.isStatic) {
        final transform = link.transform;
        // Capture previous pose for sub-frame render interpolation.
        transform.capturePrevious();
        transform.setPlanarPose(body.position.x, body.position.y, body.angle);
        link.syncOutPending = false;
      } else if (link.syncOutPending) {
        link.transform
          ..setPlanarPose(body.position.x, body.position.y, body.angle)
          ..capturePrevious();
        link.syncOutPending = false;
      } else {
        // Its previous pose has to stay its pose too. Something outside
        // physics can leave it behind — a play snapshot restored over the
        // transform, an editor write — and render interpolation would then
        // keep drawing the body somewhere between there and here.
        final transform = link.transform;
        final prev = transform.prevPosition, now = transform.position;
        if (prev.x != now.x || prev.y != now.y || transform.prevAngle != transform.angle) {
          transform.capturePrevious();
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
        rigid
          ..linearVelocity = Offset(body.velocity.x, body.velocity.y)
          ..angularVelocity = body.angularVelocity
          ..isAwake = body.isAwake;
      }
      link
        ..outVelocityX = body.velocity.x
        ..outVelocityY = body.velocity.y
        ..outAngularVelocity = body.angularVelocity;
    }
  }

  /// Takes [link]'s body out of the simulation, if it has one, and lets go
  /// of every contact it grounded.
  void _removeBody(_BodyLink link) {
    final body = link.body;
    if (body == null) return;
    link
      ..body = null
      ..culled = false
      ..wasCulled = false;
    physics.removeBody(body);
    _bodyEntityMap.remove(body);
    _forgetGroundContactsOf(body, link.entity);
    _touching.removeWhere((pair, _) => identical(pair.a, body) || identical(pair.b, body));
    final rigid = link.rigid;
    if (rigid != null) {
      rigid
        ..isGrounded = false
        ..groundEntity = null
        ..groundNormal = const Offset(0, -1);
    }
    if (link.entity.isAlive) {
      link.entity.removeComponent<PhysicsBodyRefComponent>();
    }
  }

  /// A removed body sends no contact-end events that can still be traced to
  /// an entity, so the contacts it was part of are settled here: whatever it
  /// stood on stops counting, and whatever stood on it loses that ground.
  void _forgetGroundContactsOf(PhysicsBody body, Entity entity) {
    _groundContactCount.remove(entity);
    if (_groundedEntityForPair.isEmpty) return;
    final pairs = [
      for (final pair in _groundedEntityForPair.keys)
        if (identical(pair.a, body) || identical(pair.b, body)) pair,
    ];
    for (final pair in pairs) {
      final grounded = _groundedEntityForPair[pair];
      _removeGroundContact(pair);
      final rigid = grounded?.getComponent<RigidBody2D>();
      if (rigid != null && identical(rigid.groundEntity, entity)) {
        rigid.groundEntity = null;
      }
    }
  }

  void _removeAllBodies() {
    for (final link in [..._linkByEntity.values, ..._leaving]) {
      _removeBody(link);
    }
    _characters.removeAll();
    _leaving.clear();
    _links.clear();
    _linkByEntity.clear();
    _bodyEntityMap.clear();
    _groundContactCount.clear();
    _groundedEntityForPair.clear();
    _touching.clear();
    _seenStructureVersion = -1;
    _seenGravityX = double.nan;
    _seenGravityY = double.nan;
  }

  void _dispatchEvents() {
    final stay = reportContactStay;
    if (stay) {
      // What touched before this step and still does.
      for (final entry in _touching.entries) {
        if (entry.value.$2) continue;
        final a = entry.key.a, b = entry.key.b;
        final entityA = _bodyEntityMap[a], entityB = _bodyEntityMap[b];
        if (entityA == null || entityB == null) continue;
        world.events.fire(
          CollisionStay2DEvent(
            entityA: entityA,
            entityB: entityB,
            point: contactPoint(a, b),
            normal: entry.value.$1,
          ),
        );
      }
    }
    if (_touching.isNotEmpty) {
      _touching.updateAll((_, v) => (v.$1, false));
    }

    physics.pollContactBeginEvents((a, b, nx, ny) {
      final entityA = _bodyEntityMap[a];
      final entityB = _bodyEntityMap[b];
      if (entityA == null || entityB == null) return;

      // Whichever side sits "above" (normal points from A down to B, or
      // from B down to A) is the one resting on the other.
      // The normal points from A to B; the ground's surface normal points
      // from the ground up at whoever stands on it.
      if (ny > 0.5) {
        _addGroundContact(BodyPair(a, b), entityA, entityB, Offset(-nx, -ny));
      } else if (ny < -0.5) {
        _addGroundContact(BodyPair(a, b), entityB, entityA, Offset(nx, ny));
      }
      if (stay) _touching[BodyPair(a, b)] = (Offset(nx, ny), true);

      world.events.fire(
        CollisionEnter2DEvent(
          entityA: entityA,
          entityB: entityB,
          point: contactPoint(a, b),
          normal: Offset(nx, ny),
        ),
      );
    });

    physics.pollContactEndEvents((a, b) {
      final entityA = _bodyEntityMap[a];
      final entityB = _bodyEntityMap[b];
      if (entityA == null || entityB == null) return;

      _removeGroundContact(BodyPair(a, b));
      _touching.remove(BodyPair(a, b));

      world.events.fire(CollisionExit2DEvent(entityA: entityA, entityB: entityB));
    });

    physics.pollSensorBeginEvents((sensorBody, visitorBody) {
      final sensor = _bodyEntityMap[sensorBody];
      final other = _bodyEntityMap[visitorBody];
      if (sensor == null || other == null) return;
      world.events.fire(SensorEnter2DEvent(sensor: sensor, other: other));
    });

    physics.pollSensorEndEvents((sensorBody, visitorBody) {
      final sensor = _bodyEntityMap[sensorBody];
      final other = _bodyEntityMap[visitorBody];
      if (sensor == null || other == null) return;
      world.events.fire(SensorExit2DEvent(sensor: sensor, other: other));
    });
  }

  /// Where [a] and [b] touch, as near as their bounds tell: the middle of
  /// where the two boxes round them meet (neither physics backend reports a
  /// contact's point in 2-D).
  static Offset contactPoint(PhysicsBody a, PhysicsBody b) {
    final ra = a.getCompoundBounds(Offset(a.position.x, a.position.y)).inflate(0.5);
    final rb = b.getCompoundBounds(Offset(b.position.x, b.position.y)).inflate(0.5);
    final left = math.max(ra.left, rb.left), right = math.min(ra.right, rb.right);
    final top = math.max(ra.top, rb.top), bottom = math.min(ra.bottom, rb.bottom);
    if (left <= right && top <= bottom) return Offset((left + right) / 2, (top + bottom) / 2);
    return (ra.center + rb.center) / 2;
  }

  void _addGroundContact(BodyPair pair, Entity grounded, Entity ground, Offset surfaceNormal) {
    _groundedEntityForPair[pair] = grounded;
    final count = (_groundContactCount[grounded] ?? 0) + 1;
    _groundContactCount[grounded] = count;
    final rigid = grounded.getComponent<RigidBody2D>();
    if (rigid == null) return;
    rigid.isGrounded = true;
    // Recorded so a rider can inherit a moving platform's velocity. With
    // several ground contacts at once the most recent wins, which is the
    // right answer when stepping from static ground onto a platform — and
    // from flat ground onto a slope.
    rigid.groundEntity = ground;
    rigid.groundNormal = surfaceNormal;
  }

  void _removeGroundContact(BodyPair pair) {
    final grounded = _groundedEntityForPair.remove(pair);
    if (grounded == null) return;
    final count = (_groundContactCount[grounded] ?? 1) - 1;
    if (count <= 0) {
      _groundContactCount.remove(grounded);
      final rigid = grounded.getComponent<RigidBody2D>();
      if (rigid != null) {
        rigid.isGrounded = false;
        rigid.groundEntity = null;
        rigid.groundNormal = const Offset(0, -1);
      }
    } else {
      _groundContactCount[grounded] = count;
    }
  }

  @override
  void render(Canvas canvas, Size size) {
    // Never draw collider outlines in release builds, regardless of the
    // per-entity showDebugOutline flag.
    if (!kDebugMode) return;

    // Apply the same camera transform that RenderSystem uses so collider
    // outlines are drawn in world space, not screen space.
    if (camera != null) {
      camera!.viewportSize = size;
      canvas.save();
      camera!.applyTransform(canvas, size);
    }

    // Debug rendering: each collider as the simulation has it — offset,
    // scaled and turned with its body — coloured by what kind of body it is.
    final definitions = world.context.definitions;
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final collider = entity.getComponent<Collider2D>()!;
      if (!collider.showDebugOutline) return;
      final body = _linkByEntity[entity]?.body;
      final shape = body?.shape ?? ColliderGeometry.of(collider, transform, entity, definitions);
      if (shape == null) return;
      canvas
        ..save()
        ..translate(transform.position.x, transform.position.y)
        ..rotate(transform.angle);
      ColliderGeometry.paint(canvas, shape, debugPaintFor(entity.getComponent<RigidBody2D>(), body));
      canvas.restore();
    });

    // Characters: their shape where they are, moved yet or not.
    for (final archetype in world.queryArchetypes(const [TransformComponent, CharacterBody2D])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final characters = archetype.getColumn(CharacterBody2D)!;
      for (var row = 0; row < transforms.length; row++) {
        _paintCharacter(canvas, transforms[row] as TransformComponent, characters[row] as CharacterBody2D);
      }
    }

    if (camera != null) {
      canvas.restore();
    }
  }

  /// Draws [character]'s shape where it is: solid on the ground, faded in
  /// the air.
  static void _paintCharacter(Canvas canvas, TransformComponent transform, CharacterBody2D character) {
    final shape = character.moverShape;
    final p = shape.points;
    final at = Offset(transform.position.x + character.offset.dx, transform.position.y + character.offset.dy);
    final outline = p.length == 1
        ? CircleShape(shape.radius)
        : p.length == 2
        ? CapsuleShape(center1: p[0], center2: p[1], radius: shape.radius)
        : RoundedPolygonShape(p, shape.radius);
    canvas
      ..save()
      ..translate(at.dx, at.dy);
    ColliderGeometry.paint(canvas, outline, character.isGrounded ? _debugCharacterPaint : _debugCharacterAirPaint);
    canvas.restore();
  }

  /// How the debug outline draws a body of [rigid] (none: a static body): a
  /// sensor yellow, a static body blue, a kinematic one orange, a dynamic
  /// one green — faded while its [body] sleeps.
  static Paint debugPaintFor(RigidBody2D? rigid, [PhysicsBody? body]) {
    if (rigid == null) return _debugStaticPaint;
    if (rigid.isSensor) return _debugSensorPaint;
    return switch (rigid.bodyType) {
      BodyType.static => _debugStaticPaint,
      BodyType.kinematic => _debugKinematicPaint,
      BodyType.dynamic => body != null && !body.isAwake ? _debugSleepingPaint : _debugDynamicPaint,
    };
  }

  // Cached debug paints
  static Paint _stroke(Color color, [double width = 2.0]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  static final Paint _debugStaticPaint = _stroke(Colors.blue);
  static final Paint _debugKinematicPaint = _stroke(Colors.orange);
  static final Paint _debugDynamicPaint = _stroke(Colors.green);
  static final Paint _debugSleepingPaint = _stroke(Colors.green.withValues(alpha: 0.4));
  static final Paint _debugSensorPaint = _stroke(Colors.yellow, 1.5);
  static final Paint _debugCharacterPaint = _stroke(Colors.lightBlueAccent);
  static final Paint _debugCharacterAirPaint = _stroke(Colors.lightBlueAccent.withValues(alpha: 0.5));
}

/// What [PhysicsSystem] keeps per entity: the components it reads every
/// frame — looked up once, when the world's structure changes, instead of
/// every frame — and the entity's body, once made.
final class _BodyLink {
  _BodyLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late Collider2D collider;
  RigidBody2D? rigid;
  VelocityComponent? velocity;
  CullStateComponent? cull;

  /// What a collider without a rigid body is: a static body.
  late final RigidBody2D _static = RigidBody2D(bodyType: BodyType.static);

  /// How the body moves: its rigid body, or a static body's defaults.
  RigidBody2D get settings => rigid ?? _static;

  /// [World.structureVersion] of the rebuild that last saw [entity].
  int version = -1;

  PhysicsBody? body;

  /// Culled this frame: the body is frozen and nothing is synced out.
  bool culled = false;

  /// Culled last time it was looked at — coming back wakes the body.
  bool wasCulled = false;

  /// The transform still has to take the body's position — once, for a
  /// static body that is otherwise never synced out.
  bool syncOutPending = false;

  // What the body was built from: the collider's shape and placement, the
  // entity's scale ([PhysicsSystem._scaleKey]) and, matching its entity's
  // shape, that shape's key. Any of them changing builds it again.
  ColliderShape2D? _shape;
  double _w = 0, _h = 0, _radius = 0, _height = 0, _corner = 0, _thickness = 0;
  double _ox = 0, _oy = 0, _rotation = 0, _cx = 0, _cy = 0, _sx = 0, _sy = 0;
  bool _loop = false;
  List<Offset> _points = const [];
  Object? _match;

  void remember(Collider2D c, double sx, double sy, Object? match) {
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
    _match = match;
  }

  bool builtMatches(Collider2D c, double sx, double sy, Object? match) {
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
        _sx != sx ||
        _sy != sy ||
        _match != match) {
      return false;
    }
    final points = c.points;
    if (points.length != _points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (points[i] != _points[i]) return false;
    }
    return true;
  }

  /// The body's velocity as the last step left it. Anything different at
  /// the next sync-in was written since, and wakes the body.
  double outVelocityX = 0.0;
  double outVelocityY = 0.0;
  double outAngularVelocity = 0.0;
}
