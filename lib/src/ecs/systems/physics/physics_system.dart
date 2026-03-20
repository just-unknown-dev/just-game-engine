library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../subsystems/physics/physics_engine.dart';
import '../system_priorities.dart';
import 'collision_event.dart';

/// Physics system - Handles physics simulation for ECS entities
///
/// Uses a spatial grid for broad-phase collision detection to avoid O(n²)
/// pairwise checks across all entities.
class PhysicsSystem extends System {
  @override
  int get priority => SystemPriorities.physics;

  /// Gravity
  Offset gravity = const Offset(0, 0);

  /// Cell size for the spatial grid broad-phase. Tune to roughly match
  /// the size of the largest physics body for best performance.
  double broadPhaseCellSize = 128.0;

  final Map<int, List<Entity>> _gridCells = {};

  /// Reusable entity buffer — avoids per-frame list allocation.
  final List<Entity> _entityBuffer = [];

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    VelocityComponent,
    PhysicsBodyComponent,
  ];

  @override
  void update(double deltaTime) {
    // Apply forces
    forEach((entity) {
      final velocity = entity.getComponent<VelocityComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;

      if (!body.isStatic) {
        // Apply gravity
        velocity.addScaled(gravity, deltaTime);

        // Apply drag
        velocity.scale(body.drag);
      }
    });

    // Detect and resolve collisions
    _handleCollisions();
  }

  static int _gridHash(int x, int y) => (x * 73856093) ^ ((y * 19349663) >> 1);

  void _handleCollisions() {
    // --- Broad phase: spatial grid ---
    _gridCells.clear();

    _entityBuffer.clear();
    _entityBuffer.addAll(entities);
    for (final entity in _entityBuffer) {
      final transform = entity.getComponent<TransformComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;

      final bounds = body.shape.getBounds(transform.position);
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

    for (final cell in _gridCells.values) {
      for (int i = 0; i < cell.length; i++) {
        for (int j = i + 1; j < cell.length; j++) {
          final entity1 = cell[i];
          final entity2 = cell[j];

          // Deduplicate pairs across cells using entity IDs
          final pairKey = entity1.id < entity2.id
              ? entity1.id * 100000 + entity2.id
              : entity2.id * 100000 + entity1.id;
          if (!checked.add(pairKey)) continue;

          final transform1 = entity1.getComponent<TransformComponent>()!;
          final transform2 = entity2.getComponent<TransformComponent>()!;
          final body1 = entity1.getComponent<PhysicsBodyComponent>()!;
          final body2 = entity2.getComponent<PhysicsBodyComponent>()!;

          // Skip if both static
          if (body1.isStatic && body2.isStatic) continue;

          // Skip if collision layers don't match
          if (!body1.canCollideWith(body2.layer) ||
              !body2.canCollideWith(body1.layer)) {
            continue;
          }

          // Check collision using SAT
          final manifold = body1.shape.getManifold(
            transform1.position,
            body2.shape,
            transform2.position,
          );

          if (manifold.isColliding) {
            _resolveCollision(
              entity1,
              entity2,
              transform1,
              transform2,
              body1,
              body2,
              manifold,
            );

            // Publish collision event so other systems can react.
            world.events.fire(
              CollisionEvent(
                entityA: entity1,
                entityB: entity2,
                normal: manifold.normal,
                penetration: manifold.penetration,
              ),
            );
          }
        }
      }
    }
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
    final velocity1 = entity1.getComponent<VelocityComponent>()!;
    final velocity2 = entity2.getComponent<VelocityComponent>()!;

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
      transform1.position.dx - normal.dx * corr1,
      transform1.position.dy - normal.dy * corr1,
    );
    final corr2 = correctionMag * inverseMass2;
    transform2.setPositionXY(
      transform2.position.dx + normal.dx * corr2,
      transform2.position.dy + normal.dy * corr2,
    );

    // Calculate relative velocity along normal (scalar, no Offset allocation)
    final relVelDx = velocity2.velocity.dx - velocity1.velocity.dx;
    final relVelDy = velocity2.velocity.dy - velocity1.velocity.dy;
    final velocityAlongNormal = relVelDx * normal.dx + relVelDy * normal.dy;

    // Don't resolve if velocities are separating
    if (velocityAlongNormal > 0) return;

    // Use the lesser restitution so collisions are never artificially springy.
    final restitution = math.min(body1.restitution, body2.restitution);

    // Calculate impulse scalar j
    final impulseScalar =
        -(1.0 + restitution) * velocityAlongNormal / inverseMassSum;

    // Apply impulse
    final imp1 = impulseScalar * inverseMass1;
    velocity1.setVelocityXY(
      velocity1.velocity.dx - normal.dx * imp1,
      velocity1.velocity.dy - normal.dy * imp1,
    );
    final imp2 = impulseScalar * inverseMass2;
    velocity2.setVelocityXY(
      velocity2.velocity.dx + normal.dx * imp2,
      velocity2.velocity.dy + normal.dy * imp2,
    );
  }

  @override
  void render(Canvas canvas, Size size) {
    // Debug rendering
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;

      final paint = body.isStatic ? _debugStaticPaint : _debugDynamicPaint;

      final shape = body.shape;
      if (shape is CircleShape) {
        canvas.drawCircle(transform.position, shape.radius, paint);
      } else if (shape is PolygonShape) {
        final path = Path();
        if (shape.vertices.isNotEmpty) {
          path.moveTo(
            transform.position.dx + shape.vertices[0].dx,
            transform.position.dy + shape.vertices[0].dy,
          );
          for (int i = 1; i < shape.vertices.length; i++) {
            path.lineTo(
              transform.position.dx + shape.vertices[i].dx,
              transform.position.dy + shape.vertices[i].dy,
            );
          }
          path.close();
        }
        canvas.drawPath(path, paint);
      }
    });
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
}
