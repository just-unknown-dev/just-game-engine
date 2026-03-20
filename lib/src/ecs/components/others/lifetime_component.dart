library;

import '../../ecs.dart';

/// Lifetime component - Entity that expires after time
class LifetimeComponent extends Component {
  /// Time remaining (seconds)
  double timeRemaining;

  /// Initial lifetime
  final double initialLifetime;

  /// Create a lifetime component
  LifetimeComponent(this.initialLifetime) : timeRemaining = initialLifetime;

  /// Check if expired
  bool get isExpired => timeRemaining <= 0;

  /// Get progress (0 to 1)
  double get progress => 1.0 - (timeRemaining / initialLifetime);

  /// Update lifetime
  void update(double deltaTime) {
    timeRemaining -= deltaTime;
  }

  @override
  String toString() => 'Lifetime($timeRemaining / $initialLifetime)';
}
