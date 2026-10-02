library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';

/// Boundary behavior options
enum BoundaryBehavior {
  /// Held at the edge: the position is clamped into the bounds.
  clamp,

  /// Clamped to the edge it crossed, with the velocity on that axis
  /// reversed. An entity without a [VelocityComponent] is left alone.
  bounce,

  /// Moved to the opposite edge on crossing one.
  wrap,

  /// Destroyed, through the world's command buffer, once outside.
  destroy,
}

/// Boundary system - Keeps entities within bounds
class BoundarySystem extends System {
  @override
  int get priority => SystemPriorities.boundary;

  /// World boundaries
  Rect bounds;

  /// What to do when hitting boundary
  BoundaryBehavior behavior;

  /// Keeps every entity with a transform — all of them, not only chosen
  /// ones — within [bounds] by [behavior], clamping by default.
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
          transform.setPositionXY(
            transform.position.x.clamp(bounds.left, bounds.right),
            transform.position.y.clamp(bounds.top, bounds.bottom),
          );
          break;

        case BoundaryBehavior.bounce:
          if (velocity != null) {
            if (transform.position.x < bounds.left ||
                transform.position.x > bounds.right) {
              velocity.setVelocityXY(-velocity.velocity.x, velocity.velocity.y);
              transform.setPositionXY(
                transform.position.x.clamp(bounds.left, bounds.right),
                transform.position.y,
              );
            }
            if (transform.position.y < bounds.top ||
                transform.position.y > bounds.bottom) {
              velocity.setVelocityXY(velocity.velocity.x, -velocity.velocity.y);
              transform.setPositionXY(
                transform.position.x,
                transform.position.y.clamp(bounds.top, bounds.bottom),
              );
            }
          }
          break;

        case BoundaryBehavior.wrap:
          var x = transform.position.x;
          var y = transform.position.y;
          if (x < bounds.left) x = bounds.right;
          if (x > bounds.right) x = bounds.left;
          if (y < bounds.top) y = bounds.bottom;
          if (y > bounds.bottom) y = bounds.top;
          transform.setPositionXY(x, y);
          break;

        case BoundaryBehavior.destroy:
          if (!bounds.contains(transform.position.toOffset())) {
            world.commands.destroy(entity);
          }
          break;
      }
    });
  }
}
