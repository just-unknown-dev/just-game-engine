library;

import 'dart:math' as math;

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

/// Physics system - Handles physics simulation for ECS entities
///
/// Uses a spatial grid for broad-phase collision detection to avoid O(n²)
/// pairwise checks across all entities.
class PhysicsSystem extends System {
  @override
  int get priority => SystemPriorities.physics;

  /// Camera used to apply the world-to-screen transform during debug rendering.
  /// Must match the camera used by [RenderSystem] so collider outlines stay
  /// aligned with their visual counterparts.
  GameCamera? camera;

  /// Gravity acceleration (units/s²).  z is ignored by the 2-D physics system.
  Vector3 gravity = Vector3.zero();

  /// Cell size for the spatial grid broad-phase. Tune to roughly match
  /// the size of the largest physics body for best performance.
  double broadPhaseCellSize = 128.0;

  final Map<int, List<Entity>> _gridCells = {};

  /// Reusable entity buffer — avoids per-frame list allocation.
  final List<Entity> _entityBuffer = [];

  /// Tracks active sensor overlaps: pairKey → (sensor entity, visitor entity).
  final Map<int, (Entity, Entity)> _activeSensorPairs = {};

  /// Tracks active solid contacts: pairKey → (entityA, entityB).
  final Map<int, (Entity, Entity)> _activeContactPairs = {};

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    PhysicsBodyComponent,
  ];

  @override
  void update(double deltaTime) {
    // Reset isGrounded every frame so it reflects only the current contacts.
    forEach((entity) {
      entity.getComponent<PhysicsBodyComponent>()!.isGrounded = false;
    });

    // Apply forces
    forEach((entity) {
      final body = entity.getComponent<PhysicsBodyComponent>()!;
      if (body.isStatic) return;

      // Opt-in view culling: entities without a CullStateComponent are
      // unaffected; those with one skip force application while inactive so
      // they don't silently accumulate velocity while "asleep".
      if (entity.getComponent<CullStateComponent>()?.isActive == false) {
        return;
      }

      final velocity = entity.getComponent<VelocityComponent>();
      if (velocity == null) return;

      // Apply gravity
      velocity.addScaled(gravity, deltaTime);

      // Apply drag
      velocity.scale(body.drag);
    });

    // Detect and resolve collisions
    _handleCollisions();
  }

  static int _gridHash(int x, int y) => (x * 73856093) ^ ((y * 19349663) >> 1);

  void _handleCollisions() {
    // --- Broad phase: spatial grid ---
    _gridCells.clear();

    _entityBuffer.clear();
    for (final entity in entities) {
      // Opt-in view culling: inactive entities are excluded from the
      // broad-phase entirely — they can't collide with anything while
      // "asleep" outside the active radius.
      if (entity.getComponent<CullStateComponent>()?.isActive == false) {
        continue;
      }
      _entityBuffer.add(entity);
    }
    for (final entity in _entityBuffer) {
      final transform = entity.getComponent<TransformComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;

      final bounds = body.shape.getBounds(transform.position.toOffset());
      final minX = (bounds.left / broadPhaseCellSize).floor();
      final minY = (bounds.top / broadPhaseCellSize).floor();
      final maxX = (bounds.right / broadPhaseCellSize).floor();
      final maxY = (bounds.bottom / broadPhaseCellSize).floor();

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          final hash = _gridHash(x, y);
          (_gridCells[hash] ??= []).add(entity);
        }
      }
    }

    // --- Narrow phase: only check pairs sharing a cell ---
    final checked = <int>{};
    final currentSensorPairs = <int>{};
    final currentContactPairs = <int>{};

    for (final cell in _gridCells.values) {
      for (int i = 0; i < cell.length; i++) {
        for (int j = i + 1; j < cell.length; j++) {
          final entity1 = cell[i];
          final entity2 = cell[j];

          final pairKey = entity1.id < entity2.id
              ? entity1.id * 100000 + entity2.id
              : entity2.id * 100000 + entity1.id;
          if (!checked.add(pairKey)) continue;

          final transform1 = entity1.getComponent<TransformComponent>()!;
          final transform2 = entity2.getComponent<TransformComponent>()!;
          final body1 = entity1.getComponent<PhysicsBodyComponent>()!;
          final body2 = entity2.getComponent<PhysicsBodyComponent>()!;

          if (body1.isStatic && body2.isStatic) continue;

          if (!body1.canCollideWith(body2.layer) ||
              !body2.canCollideWith(body1.layer)) {
            continue;
          }

          if (body1.isOneWay || body2.isOneWay) {
            final dynEntity = !body1.isStatic ? entity1 : entity2;
            final dynVel = dynEntity.getComponent<VelocityComponent>();
            if ((dynVel?.velocity.y ?? 0.0) <= 0) continue;
          }

          final manifold = body1.shape.getManifold(
            transform1.position.toOffset(),
            body2.shape,
            transform2.position.toOffset(),
          );

          if (!manifold.isColliding) continue;

          // Sensor handling — detect overlaps without resolving physics.
          final eitherSensor = body1.isSensor || body2.isSensor;
          if (eitherSensor) {
            currentSensorPairs.add(pairKey);
            if (!_activeSensorPairs.containsKey(pairKey)) {
              // Determine which entity is the sensor.
              final sensor = body1.isSensor ? entity1 : entity2;
              final visitor = body1.isSensor ? entity2 : entity1;
              _activeSensorPairs[pairKey] = (sensor, visitor);
              world.events.fire(
                SensorEnterEvent(sensor: sensor, visitor: visitor),
              );
            }
            continue;
          }

          // Approximate contact point: midpoint shifted half-penetration.
          final cpx = (transform1.position.x + transform2.position.x) / 2 +
              manifold.normal.dx * manifold.penetration / 2;
          final cpy = (transform1.position.y + transform2.position.y) / 2 +
              manifold.normal.dy * manifold.penetration / 2;

          _resolveCollision(
            entity1,
            entity2,
            transform1,
            transform2,
            body1,
            body2,
            manifold,
          );

          currentContactPairs.add(pairKey);
          if (!_activeContactPairs.containsKey(pairKey)) {
            _activeContactPairs[pairKey] = (entity1, entity2);
          }

          world.events.fire(
            CollisionEvent(
              entityA: entity1,
              entityB: entity2,
              normal: manifold.normal,
              penetration: manifold.penetration,
              contactPoint: Offset(cpx, cpy),
            ),
          );

          if (manifold.normal.dy > 0.5) {
            body1.isGrounded = true;
          } else if (manifold.normal.dy < -0.5) {
            body2.isGrounded = true;
          }
        }
      }
    }

    // Fire SensorExitEvent for pairs that were active last frame but not this one.
    _activeSensorPairs.removeWhere((key, pair) {
      if (!currentSensorPairs.contains(key)) {
        world.events.fire(SensorExitEvent(sensor: pair.$1, visitor: pair.$2));
        return true;
      }
      return false;
    });

    // Fire ContactExitEvent for solid pairs that separated this frame.
    _activeContactPairs.removeWhere((key, pair) {
      if (!currentContactPairs.contains(key)) {
        world.events.fire(
          ContactExitEvent(entityA: pair.$1, entityB: pair.$2),
        );
        return true;
      }
      return false;
    });
  }

  void _resolveCollision(
    Entity entity1,
    Entity entity2,
    TransformComponent transform1,
    TransformComponent transform2,
    PhysicsBodyComponent body1,
    PhysicsBodyComponent body2,
    CollisionManifold manifold,
  ) {
    final velocity1 = entity1.getComponent<VelocityComponent>();
    final velocity2 = entity2.getComponent<VelocityComponent>();

    final normal = manifold.normal;

    final penetration = manifold.penetration;
    if (penetration <= 0) return;

    final inverseMass1 = body1.isStatic
        ? 0.0
        : (body1.mass > 0 ? 1.0 / body1.mass : 0.0);
    final inverseMass2 = body2.isStatic
        ? 0.0
        : (body2.mass > 0 ? 1.0 / body2.mass : 0.0);
    final inverseMassSum = inverseMass1 + inverseMass2;

    if (inverseMassSum == 0) return;

    // Push bodies apart weighted by inverse mass so heavier objects move less.
    const correctionPercent = 0.8;
    const slop = 0.05;
    final correctionMag =
        math.max(penetration - slop, 0.0) / inverseMassSum * correctionPercent;

    final corr1 = correctionMag * inverseMass1;
    transform1.setPositionXY(
      transform1.position.x - normal.dx * corr1,
      transform1.position.y - normal.dy * corr1,
    );
    final corr2 = correctionMag * inverseMass2;
    transform2.setPositionXY(
      transform2.position.x + normal.dx * corr2,
      transform2.position.y + normal.dy * corr2,
    );

    // Calculate relative velocity along normal (scalar, no allocation)
    final relVelDx =
        (velocity2?.velocity.x ?? 0.0) - (velocity1?.velocity.x ?? 0.0);
    final relVelDy =
        (velocity2?.velocity.y ?? 0.0) - (velocity1?.velocity.y ?? 0.0);
    final velocityAlongNormal = relVelDx * normal.dx + relVelDy * normal.dy;

    // Don't resolve if velocities are separating
    if (velocityAlongNormal > 0) return;

    // Use the lesser restitution so collisions are never artificially springy.
    final restitution = math.min(body1.restitution, body2.restitution);

    // Calculate impulse scalar j
    final impulseScalar =
        -(1.0 + restitution) * velocityAlongNormal / inverseMassSum;

    // Apply impulse (skip if the body has no VelocityComponent — static body).
    final imp1 = impulseScalar * inverseMass1;
    if (velocity1 != null) {
      velocity1.setVelocityXY(
        velocity1.velocity.x - normal.dx * imp1,
        velocity1.velocity.y - normal.dy * imp1,
      );
    }
    final imp2 = impulseScalar * inverseMass2;
    if (velocity2 != null) {
      velocity2.setVelocityXY(
        velocity2.velocity.x + normal.dx * imp2,
        velocity2.velocity.y + normal.dy * imp2,
      );
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
