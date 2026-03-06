/// Built-in Systems
///
/// Common system implementations that work with built-in components.
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'ecs.dart';
import 'components.dart';
import '../physics/physics_engine.dart';

/// Movement system - Applies velocity to transform
class MovementSystem extends System {
  @override
  List<Type> get requiredComponents => [TransformComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>()!;

      // Clamp velocity to max speed
      velocity.clampToMaxSpeed();

      // Update position
      transform.position += velocity.velocity * deltaTime;
    });
  }
}

/// Render system - Renders entities with renderables
class RenderSystem extends System {
  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    RenderableComponent,
  ];

  @override
  void render(Canvas canvas, Size size) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final renderComp = entity.getComponent<RenderableComponent>()!;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        renderComp.renderable.position = transform.position;
        renderComp.renderable.rotation = transform.rotation;
        renderComp.renderable.scale = transform.scale;
      }

      // Render
      if (renderComp.renderable.visible) {
        renderComp.renderable.render(canvas, size);
      }
    });
  }
}

/// Lifetime system - Destroys expired entities
class LifetimeSystem extends System {
  /// Entities to destroy (deferred)
  final List<Entity> _toDestroy = [];

  @override
  List<Type> get requiredComponents => [LifetimeComponent];

  @override
  void update(double deltaTime) {
    _toDestroy.clear();

    forEach((entity) {
      final lifetime = entity.getComponent<LifetimeComponent>()!;
      lifetime.update(deltaTime);

      if (lifetime.isExpired) {
        _toDestroy.add(entity);
      }
    });

    // Destroy expired entities
    for (final entity in _toDestroy) {
      world.destroyEntity(entity);
    }
  }
}

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

    // ── Positional correction (Linear Projection) ──────────────────────────
    // Push bodies apart weighted by inverse mass so heavier objects move less.
    const correctionPercent = 0.8;
    const slop = 0.05; // ignore tiny overlaps to avoid jitter
    final correctionMag =
        math.max(penetration - slop, 0.0) / invMassSum * correctionPercent;

    transform1.position -= normal * (correctionMag * invMass1);
    transform2.position += normal * (correctionMag * invMass2);

    // ── Impulse resolution ───────────────────────────────────────────────────
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

/// Parent-child system - Updates child transforms based on parents
class HierarchySystem extends System {
  @override
  List<Type> get requiredComponents => [TransformComponent, ParentComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final parent = entity.getComponent<ParentComponent>()!;

      if (parent.parentId != null) {
        final parentEntity = world.getEntity(parent.parentId!);
        if (parentEntity != null && parentEntity.isActive) {
          final parentTransform = parentEntity
              .getComponent<TransformComponent>();
          if (parentTransform != null) {
            // Apply parent transform
            transform.position = parentTransform.position + parent.localOffset;
            transform.rotation =
                parentTransform.rotation + parent.localRotation;
          }
        }
      }
    });
  }
}

/// Health system - Handles death and health regeneration
class HealthSystem extends System {
  /// Health regeneration rate per second
  double regenRate = 0.0;

  /// Entities to destroy when dead
  bool destroyOnDeath = true;

  final List<Entity> _toDie = [];

  @override
  List<Type> get requiredComponents => [HealthComponent];

  @override
  void update(double deltaTime) {
    _toDie.clear();

    forEach((entity) {
      final health = entity.getComponent<HealthComponent>()!;

      // Regeneration
      if (regenRate > 0 && health.isAlive) {
        health.heal(regenRate * deltaTime);
      }

      // Check death
      if (health.isDead && destroyOnDeath) {
        _toDie.add(entity);
      }
    });

    // Destroy dead entities
    for (final entity in _toDie) {
      world.destroyEntity(entity);
    }
  }
}

/// Animation system - Updates animation state
class AnimationSystemECS extends System {
  @override
  List<Type> get requiredComponents => [AnimationStateComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final anim = entity.getComponent<AnimationStateComponent>()!;

      if (anim.isPlaying) {
        anim.time += deltaTime;
        // Loop logic would go here based on animation data
      }
    });
  }
}

/// Boundary system - Keeps entities within bounds
class BoundarySystem extends System {
  /// World boundaries
  Rect bounds;

  /// What to do when hitting boundary
  BoundaryBehavior behavior;

  BoundarySystem({
    required this.bounds,
    this.behavior = BoundaryBehavior.clamp,
  });

  @override
  List<Type> get requiredComponents => [TransformComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>();

      switch (behavior) {
        case BoundaryBehavior.clamp:
          transform.position = Offset(
            transform.position.dx.clamp(bounds.left, bounds.right),
            transform.position.dy.clamp(bounds.top, bounds.bottom),
          );
          break;

        case BoundaryBehavior.bounce:
          if (velocity != null) {
            if (transform.position.dx < bounds.left ||
                transform.position.dx > bounds.right) {
              velocity.velocity = Offset(
                -velocity.velocity.dx,
                velocity.velocity.dy,
              );
              transform.position = Offset(
                transform.position.dx.clamp(bounds.left, bounds.right),
                transform.position.dy,
              );
            }
            if (transform.position.dy < bounds.top ||
                transform.position.dy > bounds.bottom) {
              velocity.velocity = Offset(
                velocity.velocity.dx,
                -velocity.velocity.dy,
              );
              transform.position = Offset(
                transform.position.dx,
                transform.position.dy.clamp(bounds.top, bounds.bottom),
              );
            }
          }
          break;

        case BoundaryBehavior.wrap:
          var x = transform.position.dx;
          var y = transform.position.dy;
          if (x < bounds.left) x = bounds.right;
          if (x > bounds.right) x = bounds.left;
          if (y < bounds.top) y = bounds.bottom;
          if (y > bounds.bottom) y = bounds.top;
          transform.position = Offset(x, y);
          break;

        case BoundaryBehavior.destroy:
          if (!bounds.contains(transform.position)) {
            world.destroyEntity(entity);
          }
          break;
      }
    });
  }
}

/// Boundary behavior options
enum BoundaryBehavior {
  clamp, // Clamp to bounds
  bounce, // Bounce off bounds
  wrap, // Wrap to opposite side
  destroy, // Destroy when out of bounds
}
