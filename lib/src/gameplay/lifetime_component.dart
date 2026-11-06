library;

import '../ecs/ecs.dart';

/// Lifetime component - Entity that expires after time
class LifetimeComponent extends Component {
  /// Time remaining (seconds)
  double timeRemaining;

  /// Initial lifetime
  double initialLifetime;

  /// Create a lifetime component
  LifetimeComponent(this.initialLifetime) : timeRemaining = initialLifetime;

  /// Check if expired
  bool get isExpired => timeRemaining <= 0;

  /// How far through its life it is, from 0 to 1 — 1 for a lifetime of 0
  /// or less.
  double get progress => initialLifetime <= 0
      ? 1.0
      : (1.0 - timeRemaining / initialLifetime).clamp(0.0, 1.0);

  /// Update lifetime
  void update(double deltaTime) {
    timeRemaining -= deltaTime;
  }

  @override
  String toString() => 'Lifetime($timeRemaining / $initialLifetime)';
}
