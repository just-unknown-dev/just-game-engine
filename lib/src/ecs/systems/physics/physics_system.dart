library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import 'package:just_physics_engine/just_physics_engine.dart';
import 'package:just_dart/just_dart.dart';
import '../system_priorities.dart';
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
class PhysicsSystem extends System {
  /// [physics] is the single physics implementation this system drives —
  /// pass `engine.physics`. On native platforms that's the Box2D FFI
  /// backend; on web, the pure-Dart backend. Both share the same API.
  PhysicsSystem(this.physics);

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

  /// entity.id → its mirrored [PhysicsBody].
  final Map<int, PhysicsBody> _entityBodyMap = {};

  /// Reverse lookup for translating polled body pairs back to entities.
  final Map<PhysicsBody, Entity> _bodyEntityMap = {};

  // Per-entity count of currently-active ground-normal contacts, so
  // isGrounded stays true for the whole duration a body rests on something
  // (not just the first frame of contact) using only begin/end events —
  // avoids needing a "poll all active contacts every frame" API from
  // [PhysicsEngine]. entity.id → count.
  final Map<int, int> _groundContactCount = {};

  // Which entity a given contact pair grounded, if any — consulted on
  // contact-end to know which counter to decrement.
  final Map<BodyPair, Entity> _groundedEntityForPair = {};

  @override
  void update(double deltaTime) {
    _syncIn();
    physics.update(deltaTime);
    _syncOut();
    _dispatchEvents();
  }

  void _syncIn() {
    final activeIds = <int>{};

    forEach((entity) {
      if (!entity.isActive) return;
      activeIds.add(entity.id);

      final transform = entity.getComponent<TransformComponent>()!;
      final comp = entity.getComponent<PhysicsBodyComponent>()!;
      final velocityComp = entity.getComponent<VelocityComponent>();
      final culled =
          entity.getComponent<CullStateComponent>()?.isActive == false;

      var body = _entityBodyMap[entity.id];
      if (body == null) {
        body = PhysicsBody(
          position: Vector2(transform.position.x, transform.position.y),
          shape: comp.shape,
          mass: comp.isStatic ? 0.0 : comp.mass,
          restitution: comp.restitution,
          drag: comp.drag,
          angle: transform.rotation,
          useGravity: !comp.isStatic,
          isSensor: comp.isSensor,
          isOneWay: comp.isOneWay,
          categoryBits: comp.categoryBits,
          maskBits: comp.maskBits,
          groupIndex: comp.groupIndex,
        );
        if (velocityComp != null) {
          body.velocity.setValues(
            velocityComp.velocity.x,
            velocityComp.velocity.y,
          );
        }
        physics.addBody(body);
        _entityBodyMap[entity.id] = body;
        _bodyEntityMap[body] = entity;
        entity.addComponent(PhysicsBodyRefComponent(body));
      } else {
        body.shape = comp.shape;
        body.mass = comp.isStatic ? 0.0 : comp.mass;
        body.restitution = comp.restitution;
        body.drag = comp.drag;
        body.useGravity = !comp.isStatic;
        body.isSensor = comp.isSensor;
        body.isOneWay = comp.isOneWay;
        body.categoryBits = comp.categoryBits;
        body.maskBits = comp.maskBits;
        body.groupIndex = comp.groupIndex;
      }

      // Opt-in view culling: freeze the body in place while inactive rather
      // than stepping it, matching the pre-unification behaviour of
      // excluding culled entities from force application/broad-phase.
      body.isActive = !culled;
      if (culled) return;

      // Push ECS state → body immediately before stepping. This is the only
      // place ECS state flows into the body each frame; sync-out (below) is
      // the only place it flows back out — so within a frame nothing else
      // fights this system for authority over TransformComponent. Pushing
      // position (not just velocity) every frame is what makes an external
      // teleport/spawn write to TransformComponent take effect next step.
      body.position.setValues(transform.position.x, transform.position.y);
      body.angle = transform.rotation;
      if (velocityComp != null) {
        body.velocity.setValues(
          velocityComp.velocity.x,
          velocityComp.velocity.y,
        );
      }
      // PhysicsEngine's sleep system is an optimisation for engines where
      // physics is the sole source of truth (bodies only wake via external
      // forces/collisions) — but here ECS pushes fresh state into the body
      // every frame regardless, so a body the sleep system put to bed would
      // otherwise never be picked back up: PhysicsEngine.update()'s per-body
      // loop is gated entirely by `if (body.isAwake)`, so once asleep it
      // stops touching the body altogether — the velocity we just pushed
      // above would sit there forever, un-integrated, no matter how much
      // fresh input keeps arriving. Force-waking unconditionally here is
      // what actually lets this frame's push take effect.
      body.isAwake = true;
      body.sleepTimer = 0.0;
    });

    // Remove bodies for entities that disappeared (destroyed or lost their
    // PhysicsBodyComponent) since last frame.
    final staleIds = _entityBodyMap.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in staleIds) {
      final body = _entityBodyMap.remove(id);
      if (body != null) {
        physics.removeBody(body);
        _bodyEntityMap.remove(body);
        _groundContactCount.remove(id);
      }
      world.getEntity(id)?.removeComponent<PhysicsBodyRefComponent>();
    }
  }

  void _syncOut() {
    _entityBodyMap.forEach((id, body) {
      final entity = world.getEntity(id);
      if (entity == null) return;
      if (entity.getComponent<CullStateComponent>()?.isActive == false) {
        return; // culled — body is frozen, nothing new to sync
      }

      final transform = entity.getComponent<TransformComponent>();
      if (transform != null) {
        // Capture previous positions for sub-frame render interpolation.
        transform.prevPosition.setFrom(transform.position);
        transform.prevRotation = transform.rotation;
        transform.setPositionXY(body.position.x, body.position.y);
        transform.rotation = body.angle;
      }

      final velocityComp = entity.getComponent<VelocityComponent>();
      if (velocityComp != null) {
        velocityComp.setVelocityXY(body.velocity.x, body.velocity.y);
        // MovementSystem skips PhysicsBodyComponent entities (this system
        // owns their integration instead), so its maxSpeed clamp never
        // reaches them unless applied here too.
        velocityComp.clampToMaxSpeed();
      }
    });
  }

  void _dispatchEvents() {
    physics.pollContactBeginEvents((a, b, nx, ny) {
      final entityA = _bodyEntityMap[a];
      final entityB = _bodyEntityMap[b];
      if (entityA == null || entityB == null) return;

      // Whichever side sits "above" (normal points from A down to B, or
      // from B down to A) is the one resting on the other.
      if (ny > 0.5) {
        _addGroundContact(BodyPair(a, b), entityA);
      } else if (ny < -0.5) {
        _addGroundContact(BodyPair(a, b), entityB);
      }

      world.events.fire(
        CollisionEvent(
          entityA: entityA,
          entityB: entityB,
          normal: Offset(nx, ny),
          // Penetration/contact point aren't exposed by the native Box2D
          // contact-begin event (only the normal is) — defaulted so this
          // works uniformly across backends. Neither field is read by any
          // known consumer today.
          penetration: 0.0,
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

  void _addGroundContact(BodyPair pair, Entity grounded) {
    _groundedEntityForPair[pair] = grounded;
    final count = (_groundContactCount[grounded.id] ?? 0) + 1;
    _groundContactCount[grounded.id] = count;
    grounded.getComponent<PhysicsBodyComponent>()?.isGrounded = true;
  }

  void _removeGroundContact(BodyPair pair) {
    final grounded = _groundedEntityForPair.remove(pair);
    if (grounded == null) return;
    final count = (_groundContactCount[grounded.id] ?? 1) - 1;
    if (count <= 0) {
      _groundContactCount.remove(grounded.id);
      grounded.getComponent<PhysicsBodyComponent>()?.isGrounded = false;
    } else {
      _groundContactCount[grounded.id] = count;
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

    // Debug rendering
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;
      if (!body.showDebugOutline) return;

      final paint = body.isStatic ? _debugStaticPaint : _debugDynamicPaint;

      final shape = body.shape;
      final sensorPaint = body.isSensor ? _debugSensorPaint : paint;
      if (shape is CircleShape) {
        canvas.drawCircle(
          transform.position.toOffset(),
          shape.radius,
          sensorPaint,
        );
      } else if (shape is CapsuleShape) {
        final wa1 = Offset(
          transform.position.x + shape.center1.dx,
          transform.position.y + shape.center1.dy,
        );
        final wa2 = Offset(
          transform.position.x + shape.center2.dx,
          transform.position.y + shape.center2.dy,
        );
        canvas.drawCircle(wa1, shape.radius, sensorPaint);
        canvas.drawCircle(wa2, shape.radius, sensorPaint);
        canvas.drawLine(wa1, wa2, sensorPaint);
      } else if (shape is ChainShape) {
        for (int i = 0; i < shape.vertices.length - 1; i++) {
          canvas.drawLine(
            Offset(
              transform.position.x + shape.vertices[i].dx,
              transform.position.y + shape.vertices[i].dy,
            ),
            Offset(
              transform.position.x + shape.vertices[i + 1].dx,
              transform.position.y + shape.vertices[i + 1].dy,
            ),
            sensorPaint,
          );
        }
        if (shape.loop && shape.vertices.length > 1) {
          canvas.drawLine(
            Offset(
              transform.position.x + shape.vertices.last.dx,
              transform.position.y + shape.vertices.last.dy,
            ),
            Offset(
              transform.position.x + shape.vertices.first.dx,
              transform.position.y + shape.vertices.first.dy,
            ),
            sensorPaint,
          );
        }
      } else if (shape is SegmentShape) {
        canvas.drawLine(
          Offset(
            transform.position.x + shape.point1.dx,
            transform.position.y + shape.point1.dy,
          ),
          Offset(
            transform.position.x + shape.point2.dx,
            transform.position.y + shape.point2.dy,
          ),
          sensorPaint,
        );
      } else if (shape is PolygonShape) {
        final path = Path();
        if (shape.vertices.isNotEmpty) {
          path.moveTo(
            transform.position.x + shape.vertices[0].dx,
            transform.position.y + shape.vertices[0].dy,
          );
          for (int i = 1; i < shape.vertices.length; i++) {
            path.lineTo(
              transform.position.x + shape.vertices[i].dx,
              transform.position.y + shape.vertices[i].dy,
            );
          }
          path.close();
        }
        canvas.drawPath(path, sensorPaint);
      }
    });

    if (camera != null) {
      canvas.restore();
    }
  }

  // Cached debug paints
  static final Paint _debugStaticPaint = Paint()
    ..color = Colors.blue
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _debugDynamicPaint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _debugSensorPaint = Paint()
    ..color = Colors.yellow
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
}
