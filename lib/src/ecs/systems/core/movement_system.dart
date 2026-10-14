library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';

/// Movement system - Applies velocity to transform
///
/// Entities switched off ([Entity.isActive] false) do not move.
class MovementSystem extends System {
  @override
  int get priority => SystemPriorities.movement;
  @override
  List<Type> get requiredComponents => [TransformComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    // Direct column iteration — avoids per-entity getComponent lookups.
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      // PhysicsSystem owns transform/velocity integration for any entity
      // that also carries a Collider2D (it delegates to Engine.physics,
      // which does its own position integration internally) — integrating
      // here too would double-move them every frame. Only archetypes that
      // actually add Collider2D pay for this check, same opt-in-cost
      // pattern as the CullStateComponent check below. A CharacterBody2D is
      // moved by PhysicsSystem too.
      if (archetype.types.contains(Collider2D) || archetype.types.contains(CharacterBody2D)) continue;

      final transforms = archetype.getColumn(TransformComponent)!;
      final velocities = archetype.getColumn(VelocityComponent)!;
      // Opt-in view culling: only archetypes that actually added
      // CullStateComponent pay for this extra column fetch/check — entities
      // that never opt in are completely unaffected.
      final cullStates = archetype.types.contains(CullStateComponent)
          ? archetype.getColumn(CullStateComponent)
          : null;
      for (int i = 0; i < transforms.length; i++) {
        // An archetype holds switched-off entities too; they stay put.
        if (!archetype.entityAt(i).isActive) continue;
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
