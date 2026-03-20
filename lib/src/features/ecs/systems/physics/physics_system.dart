library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../physics/physics_engine.dart';

/// Physics system - Handles physics simulation for ECS entities
class PhysicsSystem extends System {
  /// Gravity
  Offset gravity = const Offset(0, 0);

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
        velocity.velocity += gravity * deltaTime;

        // Apply drag
        velocity.velocity *= body.drag;
      }
    });

    // Detect and resolve collisions
    _handleCollisions();
  }

  void _handleCollisions() {
    final entitiesList = entities.toList();

    for (int i = 0; i < entitiesList.length; i++) {
      for (int j = i + 1; j < entitiesList.length; j++) {
        final entity1 = entitiesList[i];
        final entity2 = entitiesList[j];

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

    final invMass1 = body1.isStatic
        ? 0.0
        : (body1.mass > 0 ? 1.0 / body1.mass : 0.0);
    final invMass2 = body2.isStatic
        ? 0.0
        : (body2.mass > 0 ? 1.0 / body2.mass : 0.0);
    final invMassSum = invMass1 + invMass2;

    if (invMassSum == 0) return;

    // Push bodies apart weighted by inverse mass so heavier objects move less.
    const correctionPercent = 0.8;
    const slop = 0.05;
    final correctionMag =
        math.max(penetration - slop, 0.0) / invMassSum * correctionPercent;

    transform1.position -= normal * (correctionMag * invMass1);
    transform2.position += normal * (correctionMag * invMass2);

    // Calculate relative velocity
    final relativeVelocity = velocity2.velocity - velocity1.velocity;
    final velocityAlongNormal =
        relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;

    // Don't resolve if velocities are separating
    if (velocityAlongNormal > 0) return;

    // Use the lesser restitution so collisions are never artificially springy.
    final restitution = math.min(body1.restitution, body2.restitution);

    // Calculate impulse scalar j
    final impulseScalar =
        -(1.0 + restitution) * velocityAlongNormal / invMassSum;

    // Apply impulse
    velocity1.velocity -= normal * (impulseScalar * invMass1);
    velocity2.velocity += normal * (impulseScalar * invMass2);
  }

  @override
  void render(Canvas canvas, Size size) {
    // Debug rendering
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final body = entity.getComponent<PhysicsBodyComponent>()!;

      final paint = Paint()
        ..color = body.isStatic ? Colors.blue : Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

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
}
