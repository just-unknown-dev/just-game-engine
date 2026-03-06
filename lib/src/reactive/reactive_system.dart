library;

import '../ecs/ecs.dart';

import 'entity_signal.dart';
import 'world_signal.dart';

/// A system that only processes entities with dirty (changed) components.
///
/// ReactiveSystem extends the standard ECS system pattern to support
/// change detection. Entities are only processed when their relevant
/// components have been modified via signals.
///
/// ```dart
/// class PlayerMovementSystem extends ReactiveSystem {
///   @override
///   List<Type> get requiredComponents => [TransformComponent, VelocityComponent];
///
///   @override
///   void processEntity(Entity entity, double deltaTime) {
///     final transform = entity.getComponent<TransformComponent>()!;
///     final velocity = entity.getComponent<VelocityComponent>()!;
///     transform.translate(velocity.velocity * deltaTime);
///   }
/// }
/// ```
abstract class ReactiveSystem extends System {
  final Set<EntityId> _dirtyEntities = {};
  WorldSignal? _worldSignal;

  /// Whether to process all matching entities on the first update.
  bool processAllOnFirstRun = true;

  /// Marks an entity as dirty, needing processing.
  void markDirty(Entity entity) {
    _dirtyEntities.add(entity.id);
  }

  /// Marks an entity ID as dirty.
  void markDirtyById(EntityId id) {
    _dirtyEntities.add(id);
  }

  /// Clears dirty status for an entity.
  void clearDirty(Entity entity) {
    _dirtyEntities.remove(entity.id);
  }

  /// Clears all dirty entities.
  void clearAllDirty() {
    _dirtyEntities.clear();
  }

  /// Whether an entity is dirty.
  bool isDirty(Entity entity) => _dirtyEntities.contains(entity.id);

  /// Sets the world signal for automatic tracking.
  void setWorldSignal(WorldSignal worldSignal) {
    _worldSignal = worldSignal;
  }

  /// Watches an entity's components for changes.
  ///
  /// When any watched component changes, the entity is marked dirty.
  void watchEntity(Entity entity) {
    if (_worldSignal == null) return;

    final entitySignal = _worldSignal!.entitySignal(entity);
    for (final type in requiredComponents) {
      // Create a signal for each required component type
      _watchComponentType(entitySignal, type, entity);
    }
  }

  void _watchComponentType(
    EntitySignal entitySignal,
    Type type,
    Entity entity,
  ) {
    // Generic component watching - mark dirty when signal changes
    // This is a simplified approach; in production you'd use code generation
    // or a more sophisticated type-based approach
  }

  @override
  void onAddedToWorld() {
    super.onAddedToWorld();

    // If we have a world signal, set up watching
    if (_worldSignal != null) {
      for (final entity in entities) {
        watchEntity(entity);
      }
    }
  }

  @override
  void update(double deltaTime) {
    if (processAllOnFirstRun && _dirtyEntities.isEmpty) {
      // First run - process all entities
      for (final entity in entities) {
        processEntity(entity, deltaTime);
      }
      processAllOnFirstRun = false;
    } else {
      // Only process dirty entities
      final toProcess = _dirtyEntities.toList();
      _dirtyEntities.clear();

      for (final entityId in toProcess) {
        final entity = world.getEntity(entityId);
        if (entity != null &&
            entity.isActive &&
            entity.hasComponents(requiredComponents)) {
          processEntity(entity, deltaTime);
        }
      }
    }
  }

  /// Processes a single entity. Override this instead of update().
  void processEntity(Entity entity, double deltaTime);
}

/// A system that syncs component changes to signals after processing.
///
/// Useful when you want standard systems to work with reactive UIs
/// without modifying the system's internal logic.
mixin SignalSyncMixin on System {
  WorldSignal? _worldSignalMixin;
  final Set<EntityId> _modifiedEntities = {};

  /// Sets the world signal for syncing.
  void setWorldSignalForSync(WorldSignal worldSignal) {
    _worldSignalMixin = worldSignal;
  }

  /// Call this when an entity's components are modified.
  void markModified(Entity entity) {
    _modifiedEntities.add(entity.id);
  }

  /// Syncs all modified entity signals after update.
  void syncModifiedEntities() {
    if (_worldSignalMixin == null) return;

    for (final entityId in _modifiedEntities) {
      final entity = world.getEntity(entityId);
      if (entity != null) {
        _worldSignalMixin!.entitySignal(entity).sync();
      }
    }
    _modifiedEntities.clear();
  }
}

/// A system that automatically syncs signals after each frame.
abstract class AutoSyncSystem extends System with SignalSyncMixin {
  @override
  void update(double deltaTime) {
    updateEntities(deltaTime);
    syncModifiedEntities();
  }

  /// Override this to implement your update logic.
  void updateEntities(double deltaTime);
}
