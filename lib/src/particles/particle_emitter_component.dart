library;

import '../ecs/ecs.dart';
import 'particle_emitter.dart';

/// ECS component that attaches a [ParticleEmitter] to an entity.
///
/// When used with [ParticleSystem], the emitter is updated every frame and
/// can optionally track the entity's [TransformComponent] position.
///
/// When the component leaves its entity — removed, replaced, or the
/// entity destroyed — it disposes its emitter ([ParticleEmitter.dispose]),
/// releasing the images its renderer made.
///
/// ## Example
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(position: Vector3(100, 200, 0)),
///   ParticleEmitterComponent(
///     emitter: ParticleEffects.fire(position: Vector3.zero()),
///     syncPositionFromTransform: true,
///     removeEntityWhenComplete: true,
///   ),
/// ]);
/// ```
class ParticleEmitterComponent extends Component {
  /// The particle emitter managed by this component.
  final ParticleEmitter emitter;

  /// When `true`, [ParticleSystem] copies the entity's [TransformComponent]
  /// world position to `emitter.position` each frame before calling
  /// [ParticleEmitter.update].
  ///
  /// Set to `false` if you want to position the emitter manually or if the
  /// emitter position is driven by game logic unrelated to the entity transform.
  final bool syncPositionFromTransform;

  /// When `true` and the emitter has finished (no more emissions and no live
  /// particles), [ParticleSystem] destroys the entity via
  /// `world.commands.destroy(entity)`.
  ///
  /// Useful for one-shot effects like explosions that should be cleaned up
  /// automatically.
  final bool removeEntityWhenComplete;

  /// Create a [ParticleEmitterComponent].
  ParticleEmitterComponent({
    required this.emitter,
    this.syncPositionFromTransform = true,
    this.removeEntityWhenComplete = false,
  });

  @override
  void onDetach(EntityId entityId) => emitter.dispose();

  @override
  String toString() =>
      'ParticleEmitterComponent(particles=${emitter.particleCount}, '
      'emitting=${emitter.isEmitting})';
}
