/// Built-in Systems
///
/// Common system implementations that work with built-in components.
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'ecs.dart';
import 'components.dart';

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

        // Check collision
        final distance = (transform1.position - transform2.position).distance;
        final minDistance = body1.radius + body2.radius;

        if (distance < minDistance) {
          _resolveCollision(
            entity1,
            entity2,
            transform1,
            transform2,
            body1,
            body2,
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
  ) {
    final velocity1 = entity1.getComponent<VelocityComponent>()!;
    final velocity2 = entity2.getComponent<VelocityComponent>()!;

    // Calculate collision normal
    final delta = transform1.position - transform2.position;
    final distance = delta.distance;
    if (distance == 0) return;

    final normal = delta / distance;

    // Separate bodies
    final overlap = body1.radius + body2.radius - distance;
    if (!body1.isStatic && !body2.isStatic) {
      transform1.position += normal * (overlap / 2);
      transform2.position -= normal * (overlap / 2);
    } else if (!body1.isStatic) {
      transform1.position += normal * overlap;
    } else if (!body2.isStatic) {
      transform2.position -= normal * overlap;
    }

    // Calculate relative velocity
    final relativeVelocity = velocity1.velocity - velocity2.velocity;
    final velocityAlongNormal =
        relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;

    // Don't resolve if velocities are separating
    if (velocityAlongNormal > 0) return;

    // Calculate restitution
    final restitution = math.min(body1.restitution, body2.restitution);

    // Calculate impulse
    final totalMass = body1.isStatic
        ? body2.mass
        : body2.isStatic
        ? body1.mass
        : body1.mass + body2.mass;

    final impulse = -(1 + restitution) * velocityAlongNormal / totalMass;

    // Apply impulse
    if (!body1.isStatic) {
      velocity1.velocity += normal * (impulse * body2.mass);
    }
    if (!body2.isStatic) {
      velocity2.velocity -= normal * (impulse * body1.mass);
    }
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

      canvas.drawCircle(transform.position, body.radius, paint);
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
