library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Movement system - Applies velocity to transform
class MovementSystem extends System {
  @override
  int get priority => SystemPriorities.movement;
  @override
  List<Type> get requiredComponents => [TransformComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    // Direct column iteration — avoids per-entity getComponent lookups.
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final velocities = archetype.getColumn(VelocityComponent)!;
      // Opt-in view culling: only archetypes that actually added
      // CullStateComponent pay for this extra column fetch/check — entities
      // that never opt in are completely unaffected.
      final cullStates = archetype.types.contains(CullStateComponent)
          ? archetype.getColumn(CullStateComponent)
          : null;
      for (int i = 0; i < transforms.length; i++) {
        if (cullStates != null &&
            !(cullStates[i] as CullStateComponent).isActive) {
          continue;
        }
        final transform = transforms[i] as TransformComponent;
        final velocity = velocities[i] as VelocityComponent;
        velocity.clampToMaxSpeed();
        transform.translateScaled(velocity.velocity, deltaTime);
      }
    }
  }
}
