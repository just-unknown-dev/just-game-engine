library;

import '../../../ecs/ecs.dart';

/// Per-tick execution context for [DeterministicEffect.applyTick].
///
/// Provides typed, safe access to an entity's ECS components so effects can
/// read and mutate component state without holding direct world references.
class EffectContext {
  /// The entity this effect is currently acting on.
  final Entity entity;

  /// Absolute tick number for this advance cycle (0-based since engine start).
  ///
  /// Two peers running the same effect with the same [currentTick] sequence
  /// will produce identical component mutations — this is the determinism
  /// guarantee.
  final int currentTick;

  const EffectContext({required this.entity, required this.currentTick});

  /// Retrieve component [T] from the owning entity, or `null` if absent.
  ///
  /// When the component is absent the effect should no-op gracefully.
  T? getComponent<T extends Component>() => entity.getComponent<T>();
}
