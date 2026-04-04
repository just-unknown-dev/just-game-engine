library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// ECS system that drives [ParticleEmitterComponent] entities every frame.
///
/// Register this system when constructing the [World] to automatically:
///
/// 1. Sync each emitter's position from the entity's [TransformComponent]
///    (when [ParticleEmitterComponent.syncPositionFromTransform] is `true`).
/// 2. Call [ParticleEmitter.update] with the current delta-time.
/// 3. Destroy the entity via `world.commands.destroy(entity)` when the emitter
///    has finished all emissions and all particles have expired
///    (when [ParticleEmitterComponent.removeEntityWhenComplete] is `true`).
///
/// ## Registration
/// ```dart
/// final world = World();
/// world.addSystem(ParticleSystemECS());
/// // Also add RenderSystem so the emitter renders each frame.
/// ```
///
/// ## Priority
/// Runs at [SystemPriorities.particles] (48), which is:
///   - **after** [hierarchy] (50) — so parent-propagated positions are final
///   - **before** [render] (40) — so particle state is current when drawn
class ParticleSystemECS extends System {
  @override
  int get priority => SystemPriorities.particles;

  @override
  List<Type> get requiredComponents => [ParticleEmitterComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final comp = entity.getComponent<ParticleEmitterComponent>()!;

      // Sync position from transform if requested
      if (comp.syncPositionFromTransform) {
        final transform = entity.getComponent<TransformComponent>();
        if (transform != null) {
          comp.emitter.position = transform.position;
        }
      }

      // Advance the emitter
      comp.emitter.update(deltaTime);

      // Clean up one-shot emitters
      if (comp.removeEntityWhenComplete && comp.emitter.isComplete) {
        world.commands.destroy(entity);
      }
    });
  }
}
