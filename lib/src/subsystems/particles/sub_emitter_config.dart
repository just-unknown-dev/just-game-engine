part of 'particles.dart';

/// When a sub-emitter should be spawned.
enum SubEmitterTrigger {
  /// Spawn when the triggering particle's age reaches [lifetime].
  onDeath,

  /// Spawn when the triggering particle reaches a specific normalized life
  /// fraction (see [SubEmitterConfig.lifetimeFraction]).
  onLifetimeFraction,
}

/// Describes a child particle emitter that is spawned by a parent emitter's
/// particles.
///
/// Attach one or more [SubEmitterConfig] objects to [ParticleEmitter.subEmitters]
/// to create cascading effects such as fireworks, chain explosions, or
/// sparkle trails that burst from dying particles.
///
/// ## Example — Explosion with spark showers
/// ```dart
/// final firework = ParticleEmitter(
///   ...
///   subEmitters: [
///     SubEmitterConfig(
///       trigger: SubEmitterTrigger.onDeath,
///       maxInstances: 50,
///       factory: (pos) => ParticleEffects.sparkle(position: pos),
///     ),
///   ],
/// );
/// ```
class SubEmitterConfig {
  /// When this sub-emitter is spawned.
  final SubEmitterTrigger trigger;

  /// Normalized lifetime fraction at which to trigger (only used when
  /// [trigger] == [SubEmitterTrigger.onLifetimeFraction]).  Must be in [0, 1].
  final double lifetimeFraction;

  /// Factory that creates a [ParticleEmitter] at [position].
  ///
  /// The position is the world-space position of the triggering particle at
  /// the moment of the trigger.
  final ParticleEmitter Function(Offset position) factory;

  /// Maximum number of simultaneously active sub-emitters from this config.
  ///
  /// Once this limit is reached, additional trigger events are silently ignored
  /// until existing sub-emitters complete.  This prevents infinite heap growth
  /// in high-frequency scenarios.
  final int maxInstances;

  const SubEmitterConfig({
    required this.trigger,
    required this.factory,
    this.lifetimeFraction = 0.5,
    this.maxInstances = 20,
  }) : assert(lifetimeFraction >= 0.0 && lifetimeFraction <= 1.0);
}
