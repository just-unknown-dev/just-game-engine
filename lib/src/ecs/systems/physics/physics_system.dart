library;

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
import 'collision_event.dart';
import 'sensor_event.dart';

/// Physics system — the ECS front end for [PhysicsEngine].
///
/// Owns the [PhysicsBody] lifecycle for every [PhysicsBodyComponent] entity:
/// each frame it syncs component state into the body, steps [physics] once,
/// then syncs the result back into [TransformComponent]/[VelocityComponent]
/// and fires [CollisionEvent]/[ContactExitEvent]/[SensorEnterEvent]/
/// [SensorExitEvent] on [World.events].
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
/// [TransformComponent], a force or torque waiting to be applied, a changed
/// [PhysicsBodyComponent] setting, the body coming back from view culling,
/// or a change of gravity. A player pressing a direction or jump therefore
/// always moves at once.
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
  PhysicsSystem(this.physics, {this.camera});

  /// The subsystem physics engine this system steps and syncs against.
  final PhysicsEngine physics;

  @override
  int get priority => SystemPriorities.physics;

  /// Camera used to apply the world-to-screen transform during debug rendering.
  /// Must match the camera used by [RenderSystem] so collider outlines stay
  /// aligned with their visual counterparts.
  GameCamera? camera;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    PhysicsBodyComponent,
  ];

  /// Below this positional difference (world units), an ECS/body mismatch is
  /// float round-trip noise rather than a deliberate teleport.
  ///
  /// Sync-out writes the body's position straight into the transform, so in
  /// steady state the two agree exactly and this never fires.
  static const double _teleportEpsilon = 1e-4;

  /// Angular counterpart of [_teleportEpsilon], in radians.
  static const double _teleportAngleEpsilon = 1e-5;

  /// Every entity with a transform and a body component, whether or not its
  /// body exists yet — in world order, which is also the order bodies are
  /// made in. Rebuilt only when the world's structure changes.
  final List<_BodyLink> _links = [];

  /// The same links by entity, so a rebuild keeps each entity's body.
  final Map<Entity, _BodyLink> _linkByEntity = {};

  /// [World.structureVersion] when [_links] was last brought up to date.
  int _seenStructureVersion = -1;

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

  /// The entity [body] belongs to while this system keeps it in the
  /// simulation — null for a body it did not make, or one it has removed.
  ///
  /// A body's joints go with it: [PhysicsJointBindingSystem] asks this
  /// before destroying a joint the physics engine has already destroyed.
  Entity? entityForBody(PhysicsBody body) => _bodyEntityMap[body];

  @override
  void update(double deltaTime) {
    _syncIn();
    physics.update(deltaTime);
    _syncOut();
    _dispatchEvents();
  }

  @override
  void onRemovedFromWorld() => _removeAllBodies();

  @override
  void dispose() => _removeAllBodies();

  /// Brings [_links] up to date with the world, when its structure has
  /// changed since the last look: entities that gained a body component are
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
      final bodies = archetype.getColumn(PhysicsBodyComponent)!;
      final velocities = archetype.getColumn(VelocityComponent);
      final culls = archetype.getColumn(CullStateComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = world.getEntity(ids[row]);
        if (entity == null) continue;
        final link = _linkByEntity[entity] ??= _BodyLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..comp = bodies[row] as PhysicsBodyComponent
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

    for (final link in _links) {
      final entity = link.entity;
      // Switched off: out of the simulation until switched back on, when it
      // gets a fresh body where its transform then is.
      if (!entity.isActive) {
        if (link.body != null) _leaving.add(link);
        continue;
      }

      final transform = link.transform;
      final comp = link.comp;
      final velocityComp = link.velocity;
      final culled = link.cull?.isActive == false;

      var body = link.body;
      var wake = gravityChanged;
      // The shape, its offset, the entity's scale and the sensor flag are
      // fixed when a body is made — the native Box2D backend cannot change
      // them on a live body — so a change to any rebuilds it, carrying over
      // how it was moving.
      final (sx, sy) = _scaleKey(comp, transform);
      double? keepVx, keepVy, keepSpin;
      if (body != null &&
          (!identical(link.builtFrom, comp.shape) ||
              link.builtOffset != comp.offset ||
              link.builtSx != sx ||
              link.builtSy != sy ||
              body.isSensor != comp.isSensor)) {
        keepVx = body.velocity.x;
        keepVy = body.velocity.y;
        keepSpin = body.angularVelocity;
        _removeBody(link);
        body = null;
      }
      final layers = world.context.physicsLayers;
      final category = 1 << PhysicsLayers.clampLayer(comp.layer);
      final mask =
          (comp.collidesWith ?? layers.maskOf(comp.layer)) & PhysicsLayers.all;
      if (body == null) {
        body = PhysicsBody(
          position: Vector2(transform.position.x, transform.position.y),
          shape: ColliderGeometry.build(
            comp.shape,
            offset: comp.offset,
            sx: sx,
            sy: sy,
          ),
          mass: comp.isStatic ? 0.0 : comp.mass,
          friction: comp.friction,
          restitution: comp.restitution,
          drag: comp.drag,
          angularDamping: comp.angularDamping,
          angle: transform.angle,
          useGravity: !comp.isStatic,
          gravityScale: comp.gravityScale,
          bodyType: comp.bodyType,
          isSensor: comp.isSensor,
          isOneWay: comp.isOneWay,
          oneWayDirection: comp.oneWayDirection,
          fixedRotation: comp.fixedRotation,
          isBullet: comp.isBullet,
          canSleep: comp.canSleep,
          categoryBits: category,
          maskBits: mask,
          groupIndex: comp.groupIndex,
        );
        final carried = velocityComp?.velocity;
        if (keepVx != null) {
          // Rebuilt: as it was moving.
          body.velocity.setValues(keepVx, keepVy!);
          body.angularVelocity = keepSpin!;
        } else if (carried != null && (carried.x != 0 || carried.y != 0)) {
          body.velocity.setValues(carried.x, carried.y);
          body.angularVelocity = comp.initialAngularVelocity;
        } else {
          // New: as it was set to start.
          final v = comp.initialVelocity;
          body.velocity.setValues(v.dx, v.dy);
          body.angularVelocity = comp.initialAngularVelocity;
          // The velocity component is pushed into the body every frame, so
          // it has to start the same or it stops the body at once.
          velocityComp?.setVelocityXY(v.dx, v.dy);
        }
        physics.addBody(body);
        link
          ..body = body
          ..builtFrom = comp.shape
          ..builtOffset = comp.offset
          ..builtSx = sx
          ..builtSy = sy
          ..syncOutPending = true
          ..wasCulled = false;
        _bodyEntityMap[body] = entity;
        entity.addComponent(PhysicsBodyRefComponent(body));
      } else {
        // Each setting that changes can matter to a body at rest, so a
        // change wakes it. Routed through the engine rather than written to
        // the body: on the Box2D backend each needs a native call, and a
        // plain field write would only update the Dart mirror. (Shape,
        // offset, scale and sensor rebuild the body instead; see above.)
        final mass = comp.isStatic ? 0.0 : comp.mass;
        if (body.mass != mass) {
          body.mass = mass;
          wake = true;
        }
        final useGravity = !comp.isStatic;
        if (body.useGravity != useGravity) {
          body.useGravity = useGravity;
          wake = true;
        }
        if (body.restitution != comp.restitution) {
          physics.setBodyRestitution(body, comp.restitution);
          wake = true;
        }
        if (body.friction != comp.friction) {
          physics.setBodyFriction(body, comp.friction);
          wake = true;
        }
        if (body.drag != comp.drag) {
          physics.setBodyDamping(body, comp.drag);
          wake = true;
        }
        if (body.angularDamping != comp.angularDamping) {
          physics.setBodyAngularDamping(body, comp.angularDamping);
          wake = true;
        }
        if (body.isBullet != comp.isBullet) {
          physics.setBodyBullet(body, comp.isBullet);
        }
        if (body.canSleep != comp.canSleep) {
          physics.setBodyCanSleep(body, comp.canSleep);
          wake = true;
        }
        if (body.isOneWay != comp.isOneWay ||
            body.oneWayDirection != comp.oneWayDirection) {
          physics.setBodyOneWay(
            body,
            comp.isOneWay,
            direction: comp.oneWayDirection,
          );
          wake = true;
        }
        if (body.bodyType != comp.bodyType) {
          physics.setBodyType(body, comp.bodyType);
          wake = true;
        }
        if (body.gravityScale != comp.gravityScale) {
          physics.setBodyGravityScale(body, comp.gravityScale);
          wake = true;
        }
        // Layers, the project's grid, or the body's own list changed.
        if (body.categoryBits != category ||
            body.maskBits != mask ||
            body.groupIndex != comp.groupIndex) {
          physics.setBodyFilter(
            body,
            categoryBits: category,
            maskBits: mask,
            groupIndex: comp.groupIndex,
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
      if (dx > _teleportEpsilon ||
          dy > _teleportEpsilon ||
          dAngle > _teleportAngleEpsilon) {
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
        body.velocity.setValues(
          velocityComp.velocity.x,
          velocityComp.velocity.y,
        );
      }

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

  /// The entity's scale as the collider is built with it: its sign dropped
  /// for a shape a mirror leaves as it was, so a character turning to face
  /// the other way by a negative scale is not built again.
  static (double, double) _scaleKey(
    PhysicsBodyComponent comp,
    TransformComponent transform,
  ) {
    final sx = transform.scale.x, sy = transform.scale.y;
    if (ColliderGeometry.isMirrorSymmetric(comp.shape, comp.offset)) {
      return (sx.abs(), sy.abs());
    }
    return (sx, sy);
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
        if (prev.x != now.x ||
            prev.y != now.y ||
            transform.prevAngle != transform.angle) {
          transform.capturePrevious();
        }
      }

      final velocityComp = link.velocity;
      if (velocityComp != null) {
        velocityComp.setVelocityXY(body.velocity.x, body.velocity.y);
        // MovementSystem skips PhysicsBodyComponent entities (this system
        // owns their integration instead), so its maxSpeed clamp never
        // reaches them unless applied here too.
        velocityComp.clampToMaxSpeed();
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
    final comp = link.comp;
    comp.isGrounded = false;
    comp.groundEntity = null;
    comp.groundNormal = const Offset(0, -1);
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
      final comp = grounded?.getComponent<PhysicsBodyComponent>();
      if (comp != null && identical(comp.groundEntity, entity)) {
        comp.groundEntity = null;
      }
    }
  }

  void _removeAllBodies() {
    for (final link in [..._linkByEntity.values, ..._leaving]) {
      _removeBody(link);
    }
    _leaving.clear();
    _links.clear();
    _linkByEntity.clear();
    _bodyEntityMap.clear();
    _groundContactCount.clear();
    _groundedEntityForPair.clear();
    _seenStructureVersion = -1;
    _seenGravityX = double.nan;
    _seenGravityY = double.nan;
  }

  void _dispatchEvents() {
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

      world.events.fire(
        CollisionEvent(
          entityA: entityA,
          entityB: entityB,
          // Only the normal: neither backend's contact-begin event says
          // how deep or where (CollisionEvent.penetration and
          // .contactPoint are deprecated for it).
          normal: Offset(nx, ny),
        ),
      );
    });

    physics.pollContactEndEvents((a, b) {
      final entityA = _bodyEntityMap[a];
      final entityB = _bodyEntityMap[b];
      if (entityA == null || entityB == null) return;

      _removeGroundContact(BodyPair(a, b));

      world.events.fire(ContactExitEvent(entityA: entityA, entityB: entityB));
    });

    physics.pollSensorBeginEvents((sensorBody, visitorBody) {
      final sensor = _bodyEntityMap[sensorBody];
      final visitor = _bodyEntityMap[visitorBody];
      if (sensor == null || visitor == null) return;
      world.events.fire(SensorEnterEvent(sensor: sensor, visitor: visitor));
    });

    physics.pollSensorEndEvents((sensorBody, visitorBody) {
      final sensor = _bodyEntityMap[sensorBody];
      final visitor = _bodyEntityMap[visitorBody];
      if (sensor == null || visitor == null) return;
      world.events.fire(SensorExitEvent(sensor: sensor, visitor: visitor));
    });
  }

  void _addGroundContact(
    BodyPair pair,
    Entity grounded,
    Entity ground,
    Offset surfaceNormal,
  ) {
    _groundedEntityForPair[pair] = grounded;
    final count = (_groundContactCount[grounded] ?? 0) + 1;
    _groundContactCount[grounded] = count;
    final comp = grounded.getComponent<PhysicsBodyComponent>();
    if (comp == null) return;
    comp.isGrounded = true;
    // Recorded so a rider can inherit a moving platform's velocity. With
    // several ground contacts at once the most recent wins, which is the
    // right answer when stepping from static ground onto a platform — and
    // from flat ground onto a slope.
    comp.groundEntity = ground;
    comp.groundNormal = surfaceNormal;
  }

  void _removeGroundContact(BodyPair pair) {
    final grounded = _groundedEntityForPair.remove(pair);
    if (grounded == null) return;
    final count = (_groundContactCount[grounded] ?? 1) - 1;
    if (count <= 0) {
      _groundContactCount.remove(grounded);
      final comp = grounded.getComponent<PhysicsBodyComponent>();
      if (comp != null) {
        comp.isGrounded = false;
        comp.groundEntity = null;
        comp.groundNormal = const Offset(0, -1);
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
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final comp = entity.getComponent<PhysicsBodyComponent>()!;
      if (!comp.showDebugOutline) return;
      final body = _linkByEntity[entity]?.body;
      final shape = body?.shape ?? ColliderGeometry.of(comp, transform);
      canvas
        ..save()
        ..translate(transform.position.x, transform.position.y)
        ..rotate(transform.angle);
      ColliderGeometry.paint(canvas, shape, debugPaintFor(comp, body));
      canvas.restore();
    });

    if (camera != null) {
      canvas.restore();
    }
  }

  /// How the debug outline draws [comp]: a sensor yellow, a static body
  /// blue, a kinematic one orange, a dynamic one green — faded while its
  /// [body] sleeps.
  static Paint debugPaintFor(PhysicsBodyComponent comp, [PhysicsBody? body]) {
    if (comp.isSensor) return _debugSensorPaint;
    return switch (comp.bodyType) {
      BodyType.static => _debugStaticPaint,
      BodyType.kinematic => _debugKinematicPaint,
      BodyType.dynamic =>
        body != null && !body.isAwake
            ? _debugSleepingPaint
            : _debugDynamicPaint,
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
  static final Paint _debugSleepingPaint = _stroke(
    Colors.green.withValues(alpha: 0.4),
  );
  static final Paint _debugSensorPaint = _stroke(Colors.yellow, 1.5);
}

/// What [PhysicsSystem] keeps per entity: the components it reads every
/// frame — looked up once, when the world's structure changes, instead of
/// every frame — and the entity's body, once made.
final class _BodyLink {
  _BodyLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late PhysicsBodyComponent comp;
  VelocityComponent? velocity;
  CullStateComponent? cull;

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

  /// What the body was built from: its component's shape (by identity), its
  /// offset and the entity's scale ([PhysicsSystem._scaleKey]). Any of them
  /// changing builds it again.
  CollisionShape? builtFrom;
  Offset builtOffset = Offset.zero;
  double builtSx = 1;
  double builtSy = 1;

  /// The body's velocity as the last step left it. Anything different at
  /// the next sync-in was written since, and wakes the body.
  double outVelocityX = 0.0;
  double outVelocityY = 0.0;
  double outAngularVelocity = 0.0;
}
