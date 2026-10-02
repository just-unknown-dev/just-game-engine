part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// World
// ════════════════════════════════════════════════════════════════════════════

/// ECS World - Manages all entities and systems
///
/// The central manager for the Entity-Component System.
/// Entities are stored in [Archetype] tables grouped by component signature,
/// giving systems cache-friendly iteration over matching entities.
///
/// Entity ids count up for the life of the world and are never reused, so
/// state a system keeps by id cannot attach itself to a newer entity.
///
/// Every world reads its components, loaders and hooks from a [context].
/// The engine's world is given `engine.context`; so should any other world
/// that works with the engine's scenes (the interface's screens, an editor's
/// preview). `World()` with no context makes a fresh one — core definitions
/// registered — and disposes it with the world.
class World {
  /// A world reading from [context]; a fresh [EngineContext], owned by this
  /// world, when null.
  World({EngineContext? context})
    : context = context ?? EngineContext(),
      _ownsContext = context == null;

  /// Where this world's component definitions, loaders and hooks come from.
  /// Systems read it (`world.context`) rather than anything process-wide.
  final EngineContext context;

  /// Whether [context] was made for this world, and goes with it.
  final bool _ownsContext;

  /// O(1) insert / O(1) remove entity set (preserves insertion order).
  final LinkedHashSet<Entity> _entities = LinkedHashSet<Entity>();

  /// Fast entity lookup by ID.
  final Map<EntityId, Entity> _entityMap = {};

  /// Name → entities with that name, oldest first, for [findEntityByName].
  final Map<String, List<Entity>> _byName = {};

  /// What [entities] returns until the next create or destroy.
  UnmodifiableListView<Entity>? _entityList;

  /// How many live entities are switched off.
  int _inactiveCount = 0;

  /// All systems in the world
  final List<System> _systems = [];

  /// Entity ID counter. Only ever goes up.
  int _nextEntityId = 0;

  /// Whether the world is initialized
  bool _initialized = false;

  /// Last measured per-system update costs in milliseconds.
  final Map<String, double> _lastSystemTimesMs = <String, double>{};
  double _lastUpdateTimeMs = 0.0;
  int _lastCommandFlushCount = 0;

  // Persistent Stopwatch instances — reused every frame to avoid heap allocation.
  final Stopwatch _totalStopwatch = Stopwatch();
  final Stopwatch _systemStopwatch = Stopwatch();

  /// Deferred command buffer for safe structural mutations during iteration.
  late final CommandBuffer commands = CommandBuffer(this);

  /// Keeps children's world transforms in step with their parents'.
  ///
  /// Part of every world rather than a registered system — it cannot be
  /// forgotten or cleared away with [clearSystems]. [update] runs it once a
  /// frame at [SystemPriorities.hierarchy]; set
  /// [TransformHierarchy.enabled] to false for a world whose parent links
  /// are only organisational.
  late final TransformHierarchy transformHierarchy = TransformHierarchy(this);

  /// Event bus for decoupled inter-system communication.
  final EventBus events = EventBus();

  /// Tag → entities, for [findTagged] and [allTagged].
  final _TagIndex _tagIndex = _TagIndex();

  // ── Archetype storage ───────────────────────────────────────────────────
  //
  // Archetypes in the order they were made (query results follow it), and
  // by the hash of their type set. A hash is only a hash: a hit is checked
  // against the set itself.

  final List<Archetype> _archetypeList = [];
  final Map<int, List<Archetype>> _archetypesByKey = {};

  /// Reused while moving a row between archetypes, so a migration does not
  /// build a map per move.
  final List<Component> _moveScratch = [];

  /// The archetype holding exactly [types] (distinct), made if need be.
  Archetype _archetypeOf(List<Type> types) {
    final key = _typeSetKey(types);
    final bucket = _archetypesByKey[key];
    if (bucket != null) {
      for (final archetype in bucket) {
        if (archetype._hasExactly(types, types.length)) return archetype;
      }
    }
    final created = Archetype._(List<Type>.of(types, growable: false));
    (_archetypesByKey[key] ??= []).add(created);
    _archetypeList.add(created);
    _registerWithQueries(created);
    return created;
  }

  /// Where an entity in [from] goes when it gains a [type] component —
  /// [from] itself when it already has one.
  Archetype _withType(Archetype? from, Type type) {
    if (from == null) return _archetypeOf([type]);
    return from._addEdges[type] ??= from._typeSet.contains(type)
        ? from
        : _archetypeOf([...from._typeList, type]);
  }

  /// Where an entity in [from] goes when it loses its [type] component —
  /// null when that was its last one.
  Archetype? _withoutType(Archetype from, Type type) {
    if (from._removeEdges.containsKey(type)) return from._removeEdges[type];
    final rest = [
      for (final t in from._typeList)
        if (t != type) t,
    ];
    final to = rest.isEmpty ? null : _archetypeOf(rest);
    from._removeEdges[type] = to;
    return to;
  }

  // ── Query cache ─────────────────────────────────────────────────────────
  //
  // One entry per distinct query: the archetypes it matches, kept up to
  // date as archetypes are made, and its result, dropped whenever one of
  // those archetypes gains or loses an entity or one of its entities is
  // switched on or off. Unrelated queries keep their results.

  final Map<int, List<_QueryCacheEntry>> _queryCache = {};
  final List<_QueryCacheEntry> _queryEntries = [];

  int _structureVersion = 0;

  /// Bumped whenever an entity is created or destroyed, switched on or off
  /// ([Entity.isActive]), or a component is added to or removed from one.
  /// A system that keeps its own per-entity state can compare it with the
  /// value it last saw and prune only when it changed, instead of rebuilding
  /// a set of live entities every frame.
  int get structureVersion => _structureVersion;

  /// The cache entry for [componentTypes], made on first use.
  _QueryCacheEntry _queryEntryFor(List<Type> componentTypes) {
    final key = _typeSetKey(componentTypes);
    final bucket = _queryCache[key];
    if (bucket != null) {
      for (final entry in bucket) {
        if (entry.matches(componentTypes)) return entry;
      }
    }
    final entry = _QueryCacheEntry(Set<Type>.of(componentTypes));
    final matching = <Archetype>[];
    for (final archetype in _archetypeList) {
      if (archetype._typeSet.containsAll(entry.types)) {
        matching.add(archetype);
        archetype._queries.add(entry);
      }
    }
    entry.archetypes = UnmodifiableListView(matching);
    (_queryCache[key] ??= []).add(entry);
    _queryEntries.add(entry);
    return entry;
  }

  /// Tell every cached query a new [archetype] can hold its entities.
  void _registerWithQueries(Archetype archetype) {
    for (final entry in _queryEntries) {
      if (!archetype._typeSet.containsAll(entry.types)) continue;
      // A new list, never the old one grown: a caller may be walking it.
      entry.archetypes = UnmodifiableListView([...entry.archetypes, archetype]);
      entry.entities = null;
      archetype._queries.add(entry);
    }
  }

  /// [archetype]'s rows changed: the queries it matches must look again.
  void _touch(Archetype archetype) {
    for (final entry in archetype._queries) {
      entry.entities = null;
    }
  }

  /// Fast integer key for a set of types using Zobrist hashing.
  ///
  /// Each [Type] is lazily assigned a random 31-bit value on first encounter
  /// (31 bits so the keys are the same integers on the web); the key is the
  /// XOR of all participating types. Order-independent, and only a hash:
  /// every lookup by it confirms the type set on a hit.
  ///
  /// Fixed-seed [Random] makes keys deterministic within a process run.
  static final Map<Type, int> _zobristKeys = {};
  static final Random _zodRng = Random(0x4a6f79ce);

  static int _zobristKeyFor(Type t) =>
      _zobristKeys[t] ?? (_zobristKeys[t] = _zodRng.nextInt(0x7fffffff));

  static int _typeSetKey(Iterable<Type> types) {
    var h = 0;
    for (final t in types) {
      h ^= _zobristKeyFor(t);
    }
    return h;
  }

  // ── Structural mutations (called by Entity) ────────────────────────────

  /// Move [entity]'s row to [to] (null: no components left), putting
  /// [added] in its [addType] column. Rows keep the order they always had:
  /// out of the old archetype by swap-and-pop, onto the end of the new one.
  void _move(Entity entity, Archetype? to, Type? addType, Component? added) {
    final from = entity._archetype;
    final row = entity._archetypeRow;
    final scratch = _moveScratch..clear();
    if (to != null) {
      for (final type in to._typeList) {
        scratch.add(type == addType ? added! : from!._columns[type]![row]);
      }
    }
    from?._removeRow(row);
    if (to == null) {
      entity._archetype = null;
      entity._archetypeRow = -1;
    } else {
      entity._archetype = to;
      entity._archetypeRow = to._appendRow(entity, scratch);
    }
    scratch.clear();
  }

  void _addComponentToEntity(Entity entity, Component component) {
    final type = component.componentType;
    final from = entity._archetype;
    final to = _withType(from, type);
    // A component of the same type is replaced — and detached.
    final replaced = identical(to, from)
        ? from!._columns[type]![entity._archetypeRow]
        : null;

    _move(entity, to, type, component);
    if (from != null && !identical(from, to)) _touch(from);
    _touch(to);
    _structureVersion++;

    if (replaced != null && !identical(replaced, component)) {
      _detached(entity, replaced, replacedBy: component);
    }
    _attached(entity, component);
  }

  void _removeComponentFromEntity(Entity entity, Type type) {
    final from = entity._archetype;
    if (from == null || !from._typeSet.contains(type)) return;
    final removed = from._columns[type]![entity._archetypeRow];
    final to = _withoutType(from, type);

    _move(entity, to, null, null);
    _touch(from);
    if (to != null) _touch(to);
    _structureVersion++;

    _detached(entity, removed);
  }

  /// [component] is now [entity]'s.
  void _attached(Entity entity, Component component) {
    if (component is TagComponent) _tagIndex.attach(entity, component);
    if (component is ParentComponent) {
      component.bindRelink((from, to) => _relinkChild(entity, from, to));
      _relinkChild(entity, null, component.parentId);
    }
    component.onAttach(entity.id);
  }

  /// [component] is no longer [entity]'s — removed, replaced (by
  /// [replacedBy]), or its entity destroyed.
  void _detached(Entity entity, Component component, {Component? replacedBy}) {
    if (component is TagComponent) _tagIndex.detach(entity, component);
    if (component is ParentComponent) {
      component.bindRelink(null);
      // A new link to the same parent keeps the child's place in its list.
      final sameParent =
          replacedBy is ParentComponent &&
          replacedBy.parentId == component.parentId;
      if (!sameParent) _relinkChild(entity, component.parentId, null);
    }
    component.onDetach(entity.id);
  }

  /// [child]'s `ParentComponent` went from naming [from] to naming [to]:
  /// the old parent's `ChildrenComponent` lets it go, and the new one's
  /// lists it — at the end, unless it is there already — made for the new
  /// parent when it has none. A parent that is not in this world, or the
  /// child itself, is left alone.
  void _relinkChild(Entity child, EntityId? from, EntityId? to) {
    if (from == to) return;
    if (from != null) {
      _entityMap[from]?.getComponent<ChildrenComponent>()?.removeChild(
        child.id,
      );
    }
    if (to == null) return;
    final parent = _entityMap[to];
    if (parent == null || identical(parent, child)) return;
    var children = parent.getComponent<ChildrenComponent>();
    if (children == null) {
      children = ChildrenComponent();
      parent.addComponent(children);
    }
    children.addChild(child.id);
  }

  /// [entity] was switched on or off (called by [Entity.isActive]).
  void _activeChanged(Entity entity) {
    _inactiveCount += entity._isActive ? -1 : 1;
    final archetype = entity._archetype;
    if (archetype != null) {
      _touch(archetype);
      if (archetype._typeSet.contains(TagComponent)) {
        _tagIndex.activeChanged(entity);
      }
    }
    _structureVersion++;
  }

  /// [entity] was renamed from [old] (called by [Entity.name]).
  void _renamed(Entity entity, String? old) {
    if (old != null) _unindexName(entity, old);
    _indexName(entity);
  }

  void _indexName(Entity entity) {
    final name = entity._name;
    if (name == null) return;
    _insertById(_byName[name] ??= [], entity);
  }

  void _unindexName(Entity entity, String name) {
    final list = _byName[name];
    if (list == null) return;
    _removeById(list, entity);
    if (list.isEmpty) _byName.remove(name);
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Every entity, oldest first.
  ///
  /// A snapshot: creating or destroying entities while walking it is safe,
  /// and it is reused until the next create or destroy, so asking twice in
  /// a frame costs nothing. For a count, use [entityCount].
  UnmodifiableListView<Entity> get entities =>
      _entityList ??= UnmodifiableListView(_entities.toList(growable: false));

  /// How many entities the world holds, switched off or not.
  int get entityCount => _entities.length;

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

  /// Takes a new [entity] in.
  void _adopt(Entity entity) {
    entity._world = this;
    _entities.add(entity);
    _entityMap[entity.id] = entity;
    _indexName(entity);
    _entityList = null;
    _structureVersion++;
  }

  /// Create a new entity
  Entity createEntity({String? name}) {
    final entity = Entity(_nextEntityId++, name: name);
    _adopt(entity);
    return entity;
  }

  /// Create an entity with components (batch — avoids per-component archetype
  /// migrations).
  ///
  /// Given two components of one type, the later one is kept.
  Entity createEntityWithComponents(
    List<Component> components, {
    String? name,
  }) {
    final entity = Entity(_nextEntityId++, name: name);
    _adopt(entity);

    if (components.isNotEmpty) {
      final compMap = <Type, Component>{};
      for (final c in components) {
        compMap[c.componentType] = c;
      }
      final archetype = _archetypeOf(compMap.keys.toList(growable: false));
      final scratch = _moveScratch..clear();
      for (final type in archetype._typeList) {
        scratch.add(compMap[type]!);
      }
      entity._archetype = archetype;
      entity._archetypeRow = archetype._appendRow(entity, scratch);
      scratch.clear();
      _touch(archetype);

      // Lifecycle callbacks for batch-created components.
      for (final c in compMap.values) {
        _attached(entity, c);
      }
    }
    return entity;
  }

  /// Destroy an entity, and — unless [withChildren] is false — everything
  /// under it.
  ///
  /// The children are the ones its `ChildrenComponent` lists whose
  /// `ParentComponent` agrees; destroyed with it, as in most engines. With
  /// [withChildren] false they stay, cut loose: their parent link is
  /// cleared and each becomes a root where it stands.
  ///
  /// Either way the entity leaves its own parent's `ChildrenComponent`, and
  /// every component of every entity destroyed is detached
  /// ([Component.onDetach]).
  ///
  /// A handle that is no longer this world's live entity — destroyed
  /// already, or another world's — is ignored.
  void destroyEntity(Entity entity, {bool withChildren = true}) {
    if (_entityMap[entity.id] != entity) return;

    // Out of its parent's list, so the parent keeps no dead id.
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    if (parentId != null) {
      _entityMap[parentId]?.getComponent<ChildrenComponent>()?.removeChild(
        entity.id,
      );
    }

    if (!entity.hasComponent<ChildrenComponent>()) {
      _destroyOne(entity);
      return;
    }

    if (!withChildren) {
      for (final child in _linkedChildrenOf(entity)) {
        child.getComponent<ParentComponent>()!.parentId = null;
      }
      _destroyOne(entity);
      return;
    }

    // The whole subtree, parents before children; destroyed the other way
    // round, children first.
    final doomed = <Entity>[entity];
    final seen = <Entity>{entity};
    for (var i = 0; i < doomed.length; i++) {
      for (final child in _linkedChildrenOf(doomed[i])) {
        if (seen.add(child)) doomed.add(child);
      }
    }
    for (final e in doomed.reversed) {
      _destroyOne(e);
    }
  }

  /// [parent]'s live children whose link names it back.
  List<Entity> _linkedChildrenOf(Entity parent) {
    final children = parent.getComponent<ChildrenComponent>();
    if (children == null) return const [];
    return [
      for (final id in children.childIds)
        if (_entityMap[id] case final child?)
          if (child.getComponent<ParentComponent>()?.parentId == parent.id)
            child,
    ];
  }

  /// Takes [entity] out of the world and detaches its components.
  void _destroyOne(Entity entity) {
    // Gone already: a component's onDetach may destroy a sibling first.
    if (!identical(entity._world, this)) return;
    final archetype = entity._archetype;
    List<Component>? removed;
    if (archetype != null) {
      final row = entity._archetypeRow;
      removed = [for (final col in archetype._columnList) col[row]];
      archetype._removeRow(row);
      _touch(archetype);
      entity._archetype = null;
      entity._archetypeRow = -1;
    }

    if (!entity._isActive) _inactiveCount--;
    entity._isActive = false;
    entity._world = null;
    _entityMap.remove(entity.id);
    _entities.remove(entity); // O(1) — LinkedHashSet
    final name = entity._name;
    if (name != null) _unindexName(entity, name);
    _entityList = null;
    _structureVersion++;

    if (removed != null) {
      for (final component in removed) {
        _detached(entity, component);
      }
    }
  }

  /// Whether [entity] is this world's live entity for its id.
  ///
  /// False once it has been destroyed. Ids are never reused, so a destroyed
  /// entity's handle never matches a newer one.
  bool isEntityAlive(Entity entity) {
    return _entityMap[entity.id] == entity;
  }

  /// Destroy all entities
  ///
  /// Every component is detached ([Component.onDetach]). Ids keep counting
  /// from where they were: the next entity does not reuse an old one's id.
  void destroyAllEntities() {
    _clearEntities();
  }

  void _clearEntities() {
    final gone = _entities.toList(growable: false);
    final parts = [for (final e in gone) e.components.toList()];

    for (final archetype in _archetypeList) {
      archetype._clearRows();
    }
    for (final entity in gone) {
      entity._world = null;
      entity._archetype = null;
      entity._archetypeRow = -1;
      entity._isActive = false;
    }
    _entities.clear();
    _entityMap.clear();
    _byName.clear();
    _entityList = null;
    _inactiveCount = 0;
    _archetypeList.clear();
    _archetypesByKey.clear();
    _queryCache.clear();
    _queryEntries.clear();
    _tagIndex.clear();
    _structureVersion++;

    for (var i = 0; i < gone.length; i++) {
      for (final component in parts[i]) {
        if (component is TagComponent && identical(component._owner, gone[i])) {
          component._owner = null;
        }
        component.onDetach(gone[i].id);
      }
    }
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

  /// Whether a system of type [T] (or a subtype) is in this world.
  bool hasSystem<T extends System>() => _systems.any((s) => s is T);

  /// Update all active systems
  void update(double deltaTime) {
    _totalStopwatch
      ..reset()
      ..start();
    var flushCount = 0;

    _lastSystemTimesMs.clear();

    var hierarchyDone = !transformHierarchy.enabled;
    for (final system in _systems) {
      if (!hierarchyDone && system.priority < SystemPriorities.hierarchy) {
        _runHierarchy();
        hierarchyDone = true;
      }
      if (system.isActive) {
        _systemStopwatch
          ..reset()
          ..start();
        try {
          system.update(deltaTime);
        } finally {
          _systemStopwatch.stop();
          _lastSystemTimesMs[system._profileName] =
              _systemStopwatch.elapsedMicroseconds / 1000.0;
        }
      }
      // Flush deferred commands between system ticks so later systems
      // see up-to-date entity state.
      if (commands.isNotEmpty) {
        commands.flush();
        flushCount++;
      }
    }

    if (!hierarchyDone) _runHierarchy();

    _totalStopwatch.stop();
    _lastUpdateTimeMs = _totalStopwatch.elapsedMicroseconds / 1000.0;
    _lastCommandFlushCount = flushCount;
  }

  void _runHierarchy() {
    _systemStopwatch
      ..reset()
      ..start();
    transformHierarchy.propagate();
    _systemStopwatch.stop();
    _lastSystemTimesMs['TransformHierarchy'] =
        _systemStopwatch.elapsedMicroseconds / 1000.0;
  }

  /// Render all active systems
  void render(Canvas canvas, Size size) {
    for (final system in _systems) {
      if (system.isActive) {
        system.render(canvas, size);
      }
    }
  }

  /// Find the switched-on entities that have every one of [componentTypes].
  ///
  /// Results are cached per query and refreshed only when an archetype the
  /// query matches changes — an entity added or removed, or switched on or
  /// off — so asking again each frame is a lookup. Uses archetype-based
  /// iteration: only archetypes whose type-set is a superset of
  /// [componentTypes] are scanned, skipping unrelated entities.
  ///
  /// The list is never changed after it is returned; a later change makes
  /// a new one.
  List<Entity> query(List<Type> componentTypes) {
    final entry = _queryEntryFor(componentTypes);
    return entry.entities ??= _collect(entry);
  }

  UnmodifiableListView<Entity> _collect(_QueryCacheEntry entry) {
    final result = <Entity>[];
    for (final archetype in entry.archetypes) {
      for (final entity in archetype._entities) {
        if (entity._isActive) result.add(entity);
      }
    }
    return UnmodifiableListView(result);
  }

  /// Return all [Archetype]s whose component set is a superset of
  /// [componentTypes].
  ///
  /// This allows systems to iterate dense component columns directly for
  /// maximum cache-friendliness instead of going through per-entity
  /// [Entity.getComponent] lookups.
  ///
  /// Unlike [query], this does **not** leave out entities that are switched
  /// off: an archetype holds every entity with its components. A caller
  /// must skip rows whose entity is not [Entity.isActive]
  /// (`archetype.entityAt(row).isActive`).
  Iterable<Archetype> queryArchetypes(List<Type> componentTypes) =>
      _queryEntryFor(componentTypes).archetypes;

  /// The oldest entity named [name], or null.
  ///
  /// Switched-off entities count unless [includeInactive] is false, when
  /// the oldest switched-on one is returned. Backed by an index, so it
  /// costs a map lookup rather than a scan.
  Entity? findEntityByName(String name, {bool includeInactive = true}) {
    final named = _byName[name];
    if (named == null) return null;
    for (final entity in named) {
      if (includeInactive || entity._isActive) return entity;
    }
    return null;
  }

  /// The oldest entity tagged [tag], or null. Entities switched off are
  /// passed over unless [includeInactive].
  ///
  /// Backed by an index, so it costs a map lookup rather than a scan.
  Entity? findTagged(String tag, {bool includeInactive = false}) =>
      _tagIndex.first(tag, includeInactive);

  /// Every entity tagged [tag], oldest first. Entities switched off are
  /// left out unless [includeInactive].
  ///
  /// The list cannot be changed, and is shared: it is reused until a tag
  /// set or an entity's [Entity.isActive] changes, so asking every frame
  /// does not allocate.
  List<Entity> allTagged(String tag, {bool includeInactive = false}) =>
      _tagIndex.all(tag, includeInactive);

  /// Every tag some entity in this world carries.
  Set<String> get tagsInUse => _tagIndex.tagsInUse;

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
  ///
  /// Systems go first, as [clearSystems] removes them: each hears
  /// [System.onRemovedFromWorld] and then [System.dispose], highest
  /// priority first, so a system that put something into a shared service
  /// (a physics joint, a post-process pass) takes it out again. Then every
  /// entity goes, each component detached ([Component.onDetach]).
  ///
  /// A context this world made for itself ([World] with no `context`) is
  /// disposed with it; one it was given belongs to whoever gave it.
  void dispose() {
    clearSystems();
    _clearEntities();
    events.clear();
    _initialized = false;
    if (_ownsContext) context.dispose();
    debugPrint('ECS World disposed');
  }

  /// Get statistics
  Map<String, dynamic> get stats => {
    'totalEntities': _entities.length,
    'activeEntities': _entities.length - _inactiveCount,
    'systems': _systems.length,
    'activeSystems': _systems.where((s) => s.isActive).length,
    'archetypes': _archetypeList.length,
    'lastUpdateMs': _lastUpdateTimeMs,
    'lastCommandFlushes': _lastCommandFlushCount,
    'systemTimesMs': Map<String, double>.unmodifiable(_lastSystemTimesMs),
  };
}

/// One cached query: the archetypes it matches, and its current result.
class _QueryCacheEntry {
  _QueryCacheEntry(this.types);

  /// The component types asked for.
  final Set<Type> types;

  /// Every archetype holding all of [types], oldest first. Replaced, never
  /// changed, when a new one appears.
  UnmodifiableListView<Archetype> archetypes = UnmodifiableListView(const []);

  /// The switched-on entities in [archetypes]; null until asked for again
  /// after a change.
  UnmodifiableListView<Entity>? entities;

  /// Whether [list] asks for exactly [types].
  bool matches(List<Type> list) {
    for (final t in list) {
      if (!types.contains(t)) return false;
    }
    for (final t in types) {
      if (!list.contains(t)) return false;
    }
    return true;
  }
}

/// Puts [entity] into [list], which is kept in id order — creation order,
/// since ids only count up.
void _insertById(List<Entity> list, Entity entity) {
  var lo = 0, hi = list.length;
  // Nearly always the newest: check the end first.
  if (hi == 0 || list[hi - 1].id < entity.id) {
    list.add(entity);
    return;
  }
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].id < entity.id) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo < list.length && identical(list[lo], entity)) return;
  list.insert(lo, entity);
}

/// Takes [entity] out of [list] (in id order); false when it was not there.
bool _removeById(List<Entity> list, Entity entity) {
  var lo = 0, hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].id < entity.id) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo < list.length && identical(list[lo], entity)) {
    list.removeAt(lo);
    return true;
  }
  return false;
}
