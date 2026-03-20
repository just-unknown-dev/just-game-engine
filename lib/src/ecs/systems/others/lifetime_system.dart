library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Lifetime system - Destroys expired entities
class LifetimeSystem extends System {
  @override
  int get priority => SystemPriorities.gameplay;

  /// Entities to destroy (deferred)
  final List<Entity> _toDestroy = [];

  @override
  List<Type> get requiredComponents => [LifetimeComponent];

  @override
  void update(double deltaTime) {
    _toDestroy.clear();

    forEach((entity) {
      final lifetime = entity.getComponent<LifetimeComponent>()!;
      lifetime.update(deltaTime);

      if (lifetime.isExpired) {
        _toDestroy.add(entity);
      }
    });

    // Destroy expired entities
    for (final entity in _toDestroy) {
      world.destroyEntity(entity);
    }
  }
}
