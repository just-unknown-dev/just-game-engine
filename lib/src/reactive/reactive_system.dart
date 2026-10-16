library;

import 'dart:ui';

import '../ecs/ecs.dart';

import 'entity_signal.dart';
import 'reactive_component.dart';
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
  ///
  /// From then on the system watches every entity matching
  /// [requiredComponents] — those there already and those that come to
  /// match later, which are marked dirty as they arrive so each is
  /// processed once — and lets go of the ones that are destroyed or stop
  /// matching. A new signal replaces the old one's watches.
  void setWorldSignal(WorldSignal worldSignal) {
    if (identical(_worldSignal, worldSignal)) return;
    unwatchAll();
    _worldSignal = worldSignal;
    _watchedAt = -1;
  }

  /// Watches an entity's components for changes.
  ///
  /// When any watched component changes, the entity is marked dirty.
  /// Watching an entity again replaces its watch — hooking up components
  /// that were replaced since — rather than adding a second.
  void watchEntity(Entity entity) {
    final worldSignal = _worldSignal;
    if (worldSignal == null) return;
    unwatchEntity(entity.id);

    final watch = _Watch();
    _watches[entity.id] = watch;
    final entitySignal = worldSignal.entitySignal(entity);
    for (final type in requiredComponents) {
      _watchComponentType(entitySignal, type, entity, watch);
    }
  }

  /// Stops watching the entity [id]: the listeners [watchEntity] added are
  /// removed.
  void unwatchEntity(EntityId id) => _watches.remove(id)?.dispose();

  /// Stops watching every entity.
  void unwatchAll() {
    for (final watch in _watches.values) {
      watch.dispose();
    }
    _watches.clear();
  }

  /// What each watched entity's watch added, by entity ID.
  final Map<EntityId, _Watch> _watches = {};

  /// [World.queryVersion] of [requiredComponents] when the watches were
  /// last brought up to date; -1 before the first time.
  int _watchedAt = -1;

  void _watchComponentType(
    EntitySignal entitySignal,
    Type type,
    Entity entity,
    _Watch watch,
  ) {
    // 1. If the component uses the ReactiveComponent mixin, listen for
    //    property changes and mark the entity dirty.
    final component = entity.getComponentByType(type);
    if (component is ReactiveComponent) {
      void onChange() => markDirty(entity);
      component.addChangeListener(onChange);
      watch.components.add(component);
      watch.disposers.add(() => component.removeChangeListener(onChange));
    }

    // 2. Watch the EntitySignal's component signal so that adding/removing
    //    the component also marks the entity dirty.
    final signal = entitySignal.componentSignalByType(type);
    if (signal != null) {
      void onSignalChange() => markDirty(entity);
      signal.addListener(onSignalChange);
      watch.disposers.add(() => signal.removeListener(onSignalChange));
    }
  }

  /// With a world signal, brings the watches up to date when the entities
  /// matching [requiredComponents] changed: newcomers are watched, entities
  /// whose watched component was replaced are watched again — both marked
  /// dirty, unless the first run is still to process everything — and
  /// entities that left are let go.
  void _syncWatches() {
    if (_worldSignal == null) return;
    final version = world.queryVersion(requiredComponents);
    if (version == _watchedAt) return;
    final first = _watchedAt == -1;
    _watchedAt = version;

    final matching = <EntityId>{};
    for (final entity in entities) {
      matching.add(entity.id);
      final watch = _watches[entity.id];
      if (watch != null && watch.stillOn(entity)) continue;
      watchEntity(entity);
      if (!first && !processAllOnFirstRun) markDirty(entity);
    }
    final gone = [
      for (final id in _watches.keys)
        if (!matching.contains(id)) id,
    ];
    for (final id in gone) {
      unwatchEntity(id);
      _dirtyEntities.remove(id);
    }
  }

  @override
  void onAddedToWorld() {
    super.onAddedToWorld();
    _watchedAt = -1;
    _syncWatches();
  }

  @override
  void onRemovedFromWorld() {
    super.onRemovedFromWorld();
    unwatchAll();
    _watchedAt = -1;
    _dirtyEntities.clear();
  }

  @override
  void dispose() {
    unwatchAll();
    _watchedAt = -1;
    super.dispose();
  }

  @override
  void update(double deltaTime) {
    _syncWatches();
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
            entity.isActiveInHierarchy &&
            entity.hasComponents(requiredComponents)) {
          processEntity(entity, deltaTime);
        }
      }
    }
  }

  /// Processes a single entity. Override this instead of update().
  void processEntity(Entity entity, double deltaTime);
}

/// What [ReactiveSystem.watchEntity] added for one entity.
class _Watch {
  /// The reactive components it listens to.
  final List<Component> components = [];

  /// Removes each listener it added.
  final List<VoidCallback> disposers = [];

  /// Whether every component it listens to is still [entity]'s.
  bool stillOn(Entity entity) {
    for (final component in components) {
      if (!identical(
        entity.getComponentByType(component.componentType),
        component,
      )) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    for (final remove in disposers) {
      remove();
    }
    disposers.clear();
    components.clear();
  }
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
