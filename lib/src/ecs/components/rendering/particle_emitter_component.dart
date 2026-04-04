library;

import '../../ecs.dart';
import '../../../subsystems/particles/particles.dart';

/// ECS component that attaches a [ParticleEmitter] to an entity.
///
/// When used with [ParticleSystemECS], the emitter is updated every frame and
/// can optionally track the entity's [TransformComponent] position.
///
/// ## Example
/// ```dart
/// final entity = world.createEntity();
/// world.addComponent(entity, TransformComponent(position: Offset(100, 200)));
/// world.addComponent(entity, ParticleEmitterComponent(
///   emitter: ParticleEffects.fire(position: Offset.zero),
///   syncPositionFromTransform: true,
///   removeEntityWhenComplete: true,
/// ));
/// ```
class ParticleEmitterComponent extends Component {
  /// The particle emitter managed by this component.
  final ParticleEmitter emitter;

  /// When `true`, [ParticleSystemECS] copies the entity's [TransformComponent]
  /// world position to [emitter.position] each frame before calling
  /// [ParticleEmitter.update].
  ///
  /// Set to `false` if you want to position the emitter manually or if the
  /// emitter position is driven by game logic unrelated to the entity transform.
  final bool syncPositionFromTransform;

  /// When `true` and the emitter has finished (no more emissions and no live
  /// particles), [ParticleSystemECS] destroys the entity via
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
  String toString() =>
      'ParticleEmitterComponent(particles=${emitter.particleCount}, '
      'emitting=${emitter.isEmitting})';
}
