library;

import '../../ecs.dart';
import '../../components/components.dart';

/// Health system - Handles death and health regeneration
class HealthSystem extends System {
  /// Health regeneration rate per second
  double regenRate = 0.0;

  /// Entities to destroy when dead
  bool destroyOnDeath = true;

  final List<Entity> _toDie = [];

  @override
  List<Type> get requiredComponents => [HealthComponent];

  @override
  void update(double deltaTime) {
    _toDie.clear();

    forEach((entity) {
      final health = entity.getComponent<HealthComponent>()!;

      // Regeneration
      if (regenRate > 0 && health.isAlive) {
        health.heal(regenRate * deltaTime);
      }

      // Check death
      if (health.isDead && destroyOnDeath) {
        _toDie.add(entity);
      }
    });

    // Destroy dead entities
    for (final entity in _toDie) {
      world.destroyEntity(entity);
    }
  }
}
