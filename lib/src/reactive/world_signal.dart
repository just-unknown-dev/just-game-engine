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
  /// Signals over the given world, starting from its current entity and
  /// system counts; labelled [debugLabel] (`WorldSignal` by default).
  WorldSignal(this._world, {String? debugLabel})
    : _debugLabel = debugLabel ?? 'WorldSignal' {
    _entityCount = Signal(
      _world.entityCount,
      debugLabel: '$_debugLabel.entityCount',
    );
    _entitiesSignal = _EntityListSignal(
      _world,
      debugLabel: '$_debugLabel.entities',
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
  late final _EntityListSignal _entitiesSignal;

  /// The underlying world.
  World get world => _world;

  /// Signal for the total entity count.
  Signal<int> get entityCount => _entityCount;

  /// Signal for the system count.
  Signal<int> get systemCount => _systemCount;

  /// Signal for the list of all entities.
  ///
  /// The list is [World.entities] — taken when the signal is read, not when
  /// it is notified, so a burst of notifications with nobody reading in
  /// between costs no copies.
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
    _entityCount.value = _world.entityCount;
    _systemCount.value = _world.systems.length;
    _entitiesSignal.refresh();

    // Clean up signals for destroyed entities
    final staleIds = _entitySignals.keys
        .where((id) => _world.getEntity(id) == null)
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
    _entityCount.value = _world.entityCount;
    _entitiesSignal.changed();
  }

  /// Notifies that an entity was destroyed.
  void notifyEntityDestroyed(EntityId id) {
    _entitySignals[id]?.dispose();
    _entitySignals.remove(id);
    _entityCount.value = _world.entityCount;
    _entitiesSignal.changed();
  }

  /// Notifies that a system was added.
  void notifySystemAdded(System system) {
    _systemCount.value = _world.systems.length;
  }

  /// Notifies that a system was removed.
  void notifySystemRemoved(System system) {
    _systemCount.value = _world.systems.length;
  }

  /// Disposes every signal made here, each [EntitySignal] included. The
  /// world is left as it is.
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

/// [World.entities] as a signal: notified at once, read when asked for.
class _EntityListSignal extends Signal<List<Entity>> {
  _EntityListSignal(this._world, {super.debugLabel}) : super(const []);

  final World _world;

  /// Whether [value] must be taken from the world again before it is read.
  bool _stale = true;

  @override
  List<Entity> get value {
    if (_stale) {
      _stale = false;
      setSilent(_world.entities);
    }
    return super.value;
  }

  @override
  set value(List<Entity> newValue) {
    _stale = false;
    super.value = newValue;
  }

  @override
  void forceSet(List<Entity> newValue) {
    _stale = false;
    super.forceSet(newValue);
  }

  /// The world changed: listeners hear of it now, and the list is taken
  /// when one of them reads it.
  void changed() {
    _stale = true;
    super.forceSet(const []);
  }

  /// Notify only if the world's list is not the one last published.
  void refresh() {
    if (_stale || !identical(super.value, _world.entities)) changed();
  }
}

/// Extension on World to create reactive wrappers.
extension ReactiveWorldExtension on World {
  /// Creates a reactive signal wrapper for this world.
  WorldSignal toSignal({String? debugLabel}) {
    return WorldSignal(this, debugLabel: debugLabel);
  }
}
