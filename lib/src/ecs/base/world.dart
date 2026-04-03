part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// World
// ════════════════════════════════════════════════════════════════════════════

/// ECS World - Manages all entities and systems
///
/// The central manager for the Entity-Component System.
/// Entities are stored in [Archetype] tables grouped by component signature,
/// giving systems cache-friendly iteration over matching entities.
class World {
  /// O(1) insert / O(1) remove entity set (preserves insertion order).
  final LinkedHashSet<Entity> _entities = LinkedHashSet<Entity>();

  /// Fast entity lookup by ID.
  final Map<EntityId, Entity> _entityMap = {};

  /// Generation counter per entity-id slot for use-after-destroy detection.
  final Map<EntityId, int> _generations = {};

  /// All systems in the world
  final List<System> _systems = [];

  /// Entity ID counter
  int _nextEntityId = 0;

  /// Whether the world is initialized
  bool _initialized = false;

  /// Last measured per-system update costs in milliseconds.
  final Map<String, double> _lastSystemTimesMs = <String, double>{};
  double _lastUpdateTimeMs = 0.0;
  int _lastCommandFlushCount = 0;

  /// Deferred command buffer for safe structural mutations during iteration.
  late final CommandBuffer commands = CommandBuffer(this);

  /// Event bus for decoupled inter-system communication.
  final EventBus events = EventBus();

  // ── Archetype storage ───────────────────────────────────────────────────
  final Map<String, Archetype> _archetypes = {};

  Archetype _getOrCreateArchetype(Set<Type> types) {
    final sig = Archetype._computeSignature(types);
    return _archetypes.putIfAbsent(sig, () => Archetype(types));
  }

  // ── Query cache ─────────────────────────────────────────────────────────
  //
  // Queries are cached by an integer key derived from the requested component
  // types. The cache is invalidated selectively: only queries whose required
  // types intersect the changed type are evicted.

  final Map<int, UnmodifiableListView<Entity>> _queryCache = {};

  /// Maps each cached query key → the set of component types it requires.
  final Map<int, Set<Type>> _queryCacheTypes = {};

  /// Invalidate only the query cache entries that involve [changedType].
  void _invalidateQueryCacheFor(Type changedType) {
    final keysToRemove = <int>[];
    for (final entry in _queryCacheTypes.entries) {
      if (entry.value.contains(changedType)) {
        keysToRemove.add(entry.key);
      }
    }
    for (final k in keysToRemove) {
      _queryCache.remove(k);
      _queryCacheTypes.remove(k);
    }
  }

  /// Invalidate **all** query cache entries (entity create / destroy).
  void _invalidateQueryCache() {
    _queryCache.clear();
    _queryCacheTypes.clear();
  }

  /// Fast integer key for a query. Uses XOR of type hashes (order-independent)
  /// combined with the count to reduce collisions between subsets.
  static int _queryCacheKey(List<Type> componentTypes) {
    int h = componentTypes.length;
    for (final t in componentTypes) {
      h ^= t.hashCode * 0x9e3779b9;
    }
    return h;
  }

  // ── Structural mutations (called by Entity) ────────────────────────────

  void _addComponentToEntity(Entity entity, Component component) {
    final type = component.componentType;

    // Collect current components (removing entity from current archetype).
    Map<Type, Component> comps;
    if (entity._archetype != null) {
      comps = entity._archetype!.removeEntity(entity.id, _entityMap);
    } else {
      comps = {};
    }

    comps[type] = component;

    // Place into the (possibly new) archetype.
    final archetype = _getOrCreateArchetype(comps.keys.toSet());
    final row = archetype.addEntity(entity.id, comps);
    entity._archetype = archetype;
    entity._archetypeRow = row;

    // Lifecycle callback.
    component.onAttach(entity.id);

    _invalidateQueryCacheFor(type);
  }

  void _removeComponentFromEntity<T extends Component>(Entity entity) {
    if (entity._archetype == null) return;
    if (!entity._archetype!.types.contains(T)) return;

    final comps = entity._archetype!.removeEntity(entity.id, _entityMap);
    final removed = comps.remove(T);

    // Lifecycle callback.
    removed?.onDetach(entity.id);

    if (comps.isEmpty) {
      entity._archetype = null;
      entity._archetypeRow = -1;
    } else {
      final archetype = _getOrCreateArchetype(comps.keys.toSet());
      final row = archetype.addEntity(entity.id, comps);
      entity._archetype = archetype;
      entity._archetypeRow = row;
    }

    _invalidateQueryCacheFor(T);
  }

  /// Type-erased component removal (used by [CommandBuffer]).
  void _removeComponentFromEntity2(Entity entity, Type type) {
    if (entity._archetype == null) return;
    if (!entity._archetype!.types.contains(type)) return;

    final comps = entity._archetype!.removeEntity(entity.id, _entityMap);
    final removed = comps.remove(type);

    // Lifecycle callback.
    removed?.onDetach(entity.id);

    if (comps.isEmpty) {
      entity._archetype = null;
      entity._archetypeRow = -1;
    } else {
      final archetype = _getOrCreateArchetype(comps.keys.toSet());
      final row = archetype.addEntity(entity.id, comps);
      entity._archetype = archetype;
      entity._archetypeRow = row;
    }

    _invalidateQueryCacheFor(type);
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Get all entities
  UnmodifiableListView<Entity> get entities =>
      UnmodifiableListView(_entities.toList());

  /// Get all systems
  UnmodifiableListView<System> get systems => UnmodifiableListView(_systems);

  /// Get active entities
  Iterable<Entity> get activeEntities => _entities.where((e) => e.isActive);

  /// Initialize the world
  void initialize() {
    if (_initialized) return;

    for (final system in _systems) {
      system.initialize();
    }

    _initialized = true;
    debugPrint('ECS World initialized with ${_systems.length} systems');
  }

  /// Create a new entity
  Entity createEntity({String? name}) {
    final id = _nextEntityId++;
    final gen = (_generations[id] ?? 0);
    _generations[id] = gen;
    final entity = Entity(id, generation: gen, name: name);
    entity._world = this;
    _entities.add(entity);
    _entityMap[entity.id] = entity;
    _invalidateQueryCache();
    return entity;
  }

  /// Create an entity with components (batch — avoids per-component archetype
  /// migrations).
  Entity createEntityWithComponents(
    List<Component> components, {
    String? name,
  }) {
    final id = _nextEntityId++;
    final gen = (_generations[id] ?? 0);
    _generations[id] = gen;
    final entity = Entity(id, generation: gen, name: name);
    entity._world = this;
    _entities.add(entity);
    _entityMap[entity.id] = entity;

    if (components.isNotEmpty) {
      final compMap = <Type, Component>{};
      for (final c in components) {
        compMap[c.componentType] = c;
      }
      final archetype = _getOrCreateArchetype(compMap.keys.toSet());
      final row = archetype.addEntity(entity.id, compMap);
      entity._archetype = archetype;
      entity._archetypeRow = row;

      // Lifecycle callbacks for batch-created components.
      for (final c in components) {
        c.onAttach(entity.id);
      }
    }

    _invalidateQueryCache();
    return entity;
  }

  /// Destroy an entity
  void destroyEntity(Entity entity) {
    entity.isActive = false;

    // Remove from archetype storage.
    if (entity._archetype != null) {
      entity._archetype!.removeEntity(entity.id, _entityMap);
      entity._archetype = null;
      entity._archetypeRow = -1;
    }

    entity._world = null;
    _entityMap.remove(entity.id);
    _entities.remove(entity); // O(1) — LinkedHashSet
    // Bump generation so stale references are detectable.
    _generations[entity.id] = (entity.generation) + 1;
    _invalidateQueryCache();
  }

  /// Check whether [entity] is still the live instance for its id slot.
  ///
  /// Returns `false` if the entity has been destroyed and its slot recycled.
  bool isEntityAlive(Entity entity) {
    return _entityMap[entity.id] == entity;
  }

  /// Destroy all entities
  void destroyAllEntities() {
    for (final entity in _entities) {
      entity._world = null;
      entity._archetype = null;
      entity._archetypeRow = -1;
    }
    _entities.clear();
    _entityMap.clear();
    _archetypes.clear();
    _nextEntityId = 0;
    _generations.clear();
    _invalidateQueryCache();
  }

  /// Add a system to the world
  void addSystem(System system) {
    system.world = this;
    _systems.add(system);
    _systems.sort((a, b) => b.priority.compareTo(a.priority));

    if (_initialized) {
      system.initialize();
    }

    system.onAddedToWorld();
  }

  /// Remove a system from the world
  void removeSystem(System system) {
    system.onRemovedFromWorld();
    _systems.remove(system);
    system.dispose();
  }

  /// Remove **all** systems from the world.
  ///
  /// Each system's [System.onRemovedFromWorld] and [System.dispose] are
  /// called in reverse-priority order so that higher-priority systems
  /// (e.g. [PostProcessSystem]) clean up their external state (shader
  /// passes, etc.) before lower-priority ones release entity references.
  ///
  /// Call this before rebuilding a scene to prevent stale systems from a
  /// previous screen visit accumulating in the shared [Engine] singleton.
  void clearSystems() {
    // Iterate a copy so removal mutations on _systems are safe.
    for (final system in List.of(_systems)) {
      system.onRemovedFromWorld();
      system.dispose();
    }
    _systems.clear();
  }

  /// Get a system by type
  T? getSystem<T extends System>() {
    return _systems.whereType<T>().firstOrNull;
  }

  /// Update all active systems
  void update(double deltaTime) {
    final totalStopwatch = Stopwatch()..start();
    final systemStopwatch = Stopwatch();
    var flushCount = 0;

    _lastSystemTimesMs.clear();

    for (final system in _systems) {
      if (system.isActive) {
        systemStopwatch
          ..reset()
          ..start();
        try {
          system.update(deltaTime);
        } finally {
          systemStopwatch.stop();
          _lastSystemTimesMs[system.runtimeType.toString()] =
              systemStopwatch.elapsedMicroseconds / 1000.0;
        }
      }
      // Flush deferred commands between system ticks so later systems
      // see up-to-date entity state.
      if (commands.isNotEmpty) {
        commands.flush();
        flushCount++;
      }
    }

    totalStopwatch.stop();
    _lastUpdateTimeMs = totalStopwatch.elapsedMicroseconds / 1000.0;
    _lastCommandFlushCount = flushCount;
  }

  /// Render all active systems
  void render(Canvas canvas, Size size) {
    for (final system in _systems) {
      if (system.isActive) {
        system.render(canvas, size);
      }
    }
  }

  /// Find entities with specific components.
  ///
  /// Results are cached per query-key and selectively invalidated when
  /// components of matching types change. Uses archetype-based iteration —
  /// only archetypes whose type-set is a superset of [componentTypes] are
  /// scanned, skipping unrelated entities.
  List<Entity> query(List<Type> componentTypes) {
    final key = _queryCacheKey(componentTypes);
    final cached = _queryCache[key];
    if (cached != null) return cached;

    final required = componentTypes.toSet();
    final result = <Entity>[];

    for (final archetype in _archetypes.values) {
      if (archetype.types.containsAll(required)) {
        for (final id in archetype.entityIds) {
          final entity = _entityMap[id];
          if (entity != null && entity.isActive) {
            result.add(entity);
          }
        }
      }
    }

    final unmodifiable = UnmodifiableListView(result);
    _queryCache[key] = unmodifiable;
    _queryCacheTypes[key] = required;
    return unmodifiable;
  }

  /// Return all [Archetype]s whose component set is a superset of
  /// [componentTypes].
  ///
  /// This allows systems to iterate dense component columns directly for
  /// maximum cache-friendliness instead of going through per-entity
  /// [getComponent] lookups.
  Iterable<Archetype> queryArchetypes(List<Type> componentTypes) {
    final required = componentTypes.toSet();
    return _archetypes.values.where((a) => a.types.containsAll(required));
  }

  /// Find entity by name
  Entity? findEntityByName(String name) {
    return _entities.where((e) => e.name == name).firstOrNull;
  }

  /// Get entity by ID (O(1) lookup).
  Entity? getEntity(EntityId id) {
    return _entityMap[id];
  }

  /// Create a new entity from a [prefab] blueprint.
  ///
  /// Each component factory in the prefab is called to produce a fresh
  /// component instance, then the entity is created via the optimised
  /// batch path ([createEntityWithComponents]).
  Entity instantiate(EntityPrefab prefab) {
    final components = [for (final factory in prefab.factories) factory()];
    return createEntityWithComponents(components, name: prefab.name);
  }

  /// Dispose the world and all systems
  void dispose() {
    for (final system in _systems) {
      system.dispose();
    }
    _systems.clear();
    for (final entity in _entities) {
      entity._world = null;
      entity._archetype = null;
      entity._archetypeRow = -1;
    }
    _entities.clear();
    _entityMap.clear();
    _archetypes.clear();
    _queryCache.clear();
    _queryCacheTypes.clear();
    _generations.clear();
    events.clear();
    _initialized = false;
    debugPrint('ECS World disposed');
  }

  /// Get statistics
  Map<String, dynamic> get stats => {
    'totalEntities': _entities.length,
    'activeEntities': activeEntities.length,
    'systems': _systems.length,
    'activeSystems': _systems.where((s) => s.isActive).length,
    'archetypes': _archetypes.length,
    'lastUpdateMs': _lastUpdateTimeMs,
    'lastCommandFlushes': _lastCommandFlushCount,
    'systemTimesMs': Map<String, double>.unmodifiable(_lastSystemTimesMs),
  };
}
