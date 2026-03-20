library;

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';

import 'entity_signal.dart';

/// A signal that tracks world-level events like entity and system changes.
///
/// WorldSignal provides reactive access to the game world's state,
/// enabling UI to respond to entity creation, destruction, and system changes.
///
/// ```dart
/// final worldSignal = WorldSignal(world);
///
/// // React to entity count changes
/// SignalBuilder(
///   signal: worldSignal.entityCount,
///   builder: (_, count, _) => Text('Entities: $count'),
/// );
///
/// // Query reactive list of entities with specific components
/// final players = worldSignal.query([TransformComponent, TagComponent]);
/// ```
class WorldSignal {
  WorldSignal(this._world, {String? debugLabel})
    : _debugLabel = debugLabel ?? 'WorldSignal' {
    _entityCount = Signal(
      _world.entities.length,
      debugLabel: '$_debugLabel.entityCount',
    );
    _systemCount = Signal(
      _world.systems.length,
      debugLabel: '$_debugLabel.systemCount',
    );
  }

  final World _world;
  final String _debugLabel;

  late final Signal<int> _entityCount;
  late final Signal<int> _systemCount;

  final Map<EntityId, EntitySignal> _entitySignals = {};
  final Signal<List<Entity>> _entitiesSignal = Signal(
    [],
    debugLabel: 'WorldSignal.entities',
  );

  /// The underlying world.
  World get world => _world;

  /// Signal for the total entity count.
  Signal<int> get entityCount => _entityCount;

  /// Signal for the system count.
  Signal<int> get systemCount => _systemCount;

  /// Signal for the list of all entities.
  Signal<List<Entity>> get entities => _entitiesSignal;

  /// Gets or creates an EntitySignal for an entity.
  EntitySignal entitySignal(Entity entity) {
    return _entitySignals.putIfAbsent(
      entity.id,
      () =>
          EntitySignal(entity, debugLabel: '$_debugLabel.entity(${entity.id})'),
    );
  }

  /// Gets an EntitySignal by entity ID.
  EntitySignal? entitySignalById(EntityId id) {
    final entity = _world.getEntity(id);
    if (entity == null) return null;
    return entitySignal(entity);
  }

  /// Creates a computed signal that queries entities with specific components.
  ///
  /// The query updates reactively when entities are added/removed.
  Computed<List<Entity>> query(List<Type> componentTypes) {
    return Computed(() {
      // Reading _entitiesSignal makes this reactive
      _entitiesSignal.value;
      return _world.query(componentTypes).toList();
    }, debugLabel: '$_debugLabel.query');
  }

  /// Creates a computed signal for active entities only.
  Computed<List<Entity>> get activeEntities {
    return Computed(() {
      _entitiesSignal.value;
      return _world.activeEntities.toList();
    }, debugLabel: '$_debugLabel.activeEntities');
  }

  /// Creates a computed signal that finds an entity by name.
  Computed<Entity?> findByName(String name) {
    return Computed(() {
      _entitiesSignal.value;
      return _world.findEntityByName(name);
    }, debugLabel: '$_debugLabel.findByName($name)');
  }

  /// Syncs all signals with the world's current state.
  ///
  /// Call this after the world is modified externally (e.g., after update cycle).
  void sync() {
    final currentEntities = _world.entities.toList();

    _entityCount.value = currentEntities.length;
    _systemCount.value = _world.systems.length;
    _entitiesSignal.value = currentEntities;

    // Clean up signals for destroyed entities
    final currentIds = currentEntities.map((e) => e.id).toSet();
    final staleIds = _entitySignals.keys
        .where((id) => !currentIds.contains(id))
        .toList();

    for (final id in staleIds) {
      _entitySignals[id]?.dispose();
      _entitySignals.remove(id);
    }

    // Sync existing entity signals
    for (final entitySignal in _entitySignals.values) {
      entitySignal.sync();
    }
  }

  /// Notifies that an entity was created.
  void notifyEntityCreated(Entity entity) {
    _entityCount.value = _world.entities.length;
    _entitiesSignal.forceSet(_world.entities.toList());
  }

  /// Notifies that an entity was destroyed.
  void notifyEntityDestroyed(EntityId id) {
    _entitySignals[id]?.dispose();
    _entitySignals.remove(id);
    _entityCount.value = _world.entities.length;
    _entitiesSignal.forceSet(_world.entities.toList());
  }

  /// Notifies that a system was added.
  void notifySystemAdded(System system) {
    _systemCount.value = _world.systems.length;
  }

  /// Notifies that a system was removed.
  void notifySystemRemoved(System system) {
    _systemCount.value = _world.systems.length;
  }

  void dispose() {
    for (final entitySignal in _entitySignals.values) {
      entitySignal.dispose();
    }
    _entitySignals.clear();
    _entityCount.dispose();
    _systemCount.dispose();
    _entitiesSignal.dispose();
  }

  @override
  String toString() => _debugLabel;
}

/// Extension on World to create reactive wrappers.
extension ReactiveWorldExtension on World {
  /// Creates a reactive signal wrapper for this world.
  WorldSignal toSignal({String? debugLabel}) {
    return WorldSignal(this, debugLabel: debugLabel);
  }
}
