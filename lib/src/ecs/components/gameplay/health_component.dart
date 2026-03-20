library;

import '../../ecs.dart';

/// Health component - HP system
class HealthComponent extends Component {
  /// Current health
  double health;

  /// Maximum health
  double maxHealth;

  /// Is entity invulnerable
  bool isInvulnerable;

  /// Create a health component
  HealthComponent({
    required this.maxHealth,
    double? health,
    this.isInvulnerable = false,
  }) : health = health ?? maxHealth;

  /// Check if alive
  bool get isAlive => health > 0;

  /// Check if dead
  bool get isDead => health <= 0;

  /// Get health percentage (0 to 1)
  double get healthPercent => (health / maxHealth).clamp(0.0, 1.0);

  /// Damage the entity
  void damage(double amount) {
    if (!isInvulnerable) {
      health = (health - amount).clamp(0.0, maxHealth);
    }
  }

  /// Heal the entity
  void heal(double amount) {
    health = (health + amount).clamp(0.0, maxHealth);
  }

  /// Reset to full health
  void reset() {
    health = maxHealth;
  }

  @override
  String toString() => 'Health($health / $maxHealth)';
}
