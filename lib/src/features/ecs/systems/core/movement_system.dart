library;

import '../../ecs.dart';
import '../../components/components.dart';

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
