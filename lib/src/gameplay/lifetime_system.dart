library;

import '../ecs/ecs.dart';
import 'lifetime_component.dart';

/// Lifetime system - Destroys expired entities
class LifetimeSystem extends System {
  @override
  int get priority => SystemPriorities.gameplay;

  /// Entities to destroy (deferred)
  final List<Entity> _toDestroy = [];

  @override
  List<Type> get requiredComponents => const [LifetimeComponent];

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
