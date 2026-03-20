library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';

/// Boundary behavior options
enum BoundaryBehavior { clamp, bounce, wrap, destroy }

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
