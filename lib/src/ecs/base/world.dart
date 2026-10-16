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

  /// How many live entities are not active in the hierarchy
  /// ([Entity.isActiveInHierarchy]).
  int _inactiveCount = 0;

  /// All systems in the world, in the order they run: by priority, and in
  /// the order they were added where priorities are equal.
  final List<System> _systems = [];

  /// [_systems] as of its last change — what [update], [frame] and
  /// [render] walk, so a system added or removed while they run changes
  /// [_systems], never the list being walked.
  List<System>? _systemsSnapshot;

  List<System> get _running =>
      _systemsSnapshot ??= List<System>.unmodifiable(_systems);

  /// How many systems have been added, ever: each system's place among
  /// those of the same priority.
  int _systemsAdded = 0;

  /// Entity ID counter. Only ever goes up.
  int _nextEntityId = 0;

  /// Whether the world is initialized
  bool _initialized = false;

  /// Whether [update] times each system and itself for [stats]
  /// (`systemTimesMs`, `lastUpdateMs`).
  ///
  /// On by default in debug and profile builds and off in release, where
  /// reading a stopwatch around every system each step costs time for
  /// numbers nothing reads. Switched off, those stats stay empty and 0.
  bool profiling = !kReleaseMode;

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
  // date as archetypes are made, its result, and its version. Whenever one
  // of those archetypes gains or loses an entity, has a component of one
  // replaced, or one of its entities is switched on or off, the result is
  // dropped and the version moves on. Unrelated queries keep both.

  final Map<int, List<_QueryCacheEntry>> _queryCache = {};
  final List<_QueryCacheEntry> _queryEntries = [];

  /// Where every query's version comes from: one counter for the world, so
  /// no two versions are ever the same.
  int _versionClock = 0;

  int _updateCount = 0;

  /// How many times [update] has run. A renderer drawing between fixed
  /// updates compares it with the value it last saw to know whether one
  /// happened since its last frame.
  int get updateCount => _updateCount;

  /// The cache entry for [componentTypes], made on first use.
  _QueryCacheEntry _queryEntryFor(List<Type> componentTypes) {
    final key = _typeSetKey(componentTypes);
    final bucket = _queryCache[key];
    if (bucket != null) {
      for (final entry in bucket) {
        if (entry.matches(componentTypes)) return entry;
      }
    }
    final entry = _QueryCacheEntry(
      Set<Type>.of(componentTypes),
      ++_versionClock,
    );
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
      entry.version = ++_versionClock;
      archetype._queries.add(entry);
    }
  }

  /// [archetype]'s rows changed: the queries it matches must look again,
  /// and their versions move on.
  void _touch(Archetype archetype) {
    for (final entry in archetype._queries) {
      entry.entities = null;
      entry.version = ++_versionClock;
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
    // Refused before anything changes.
    if (component is ParentComponent) {
      final to = component.parentId;
      if (to != null) _checkLink(entity, to);
    }
    final type = component.componentType;
    final from = entity._archetype;
    final to = _withType(from, type);
    // A component of the same type is replaced — and detached.
    final replaced = identical(to, from)
        ? from!._columns[type]![entity._archetypeRow]
        : null;

    _move(entity, to, type, component);
    // A new type goes after the entity's others; a replaced one keeps its
    // place.
    if (!identical(to, from)) {
      entity._order = List.unmodifiable([...?entity._order, type]);
    }
    entity._components = null;
    if (from != null && !identical(from, to)) _touch(from);
    // A replaced component changes no archetype, but its queries still
    // hear of it: what a system keeps of the old one is out of date.
    _touch(to);

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
    final order = entity._order;
    entity._order = to == null || order == null
        ? null
        : List.unmodifiable([
            for (final t in order)
              if (t != type) t,
          ]);
    entity._components = null;
    _touch(from);
    if (to != null) _touch(to);

    _detached(entity, removed);
  }

  /// [component] is now [entity]'s.
  void _attached(Entity entity, Component component) {
    if (component is TagComponent) _tagIndex.attach(entity, component);
    if (component is ParentComponent) {
      component.bindRelink(
        (from, to) => _relinkChild(entity, from, to),
        check: (to) => _checkLink(entity, to),
      );
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
  /// child itself, is left alone. Under a switched-off parent now, or no
  /// longer, the child's subtree is switched off or on with it
  /// ([Entity.isActiveInHierarchy]).
  void _relinkChild(Entity child, EntityId? from, EntityId? to) {
    if (from == to) return;
    if (from != null) {
      _entityMap[from]?.getComponent<ChildrenComponent>()?.removeChild(
        child.id,
      );
    }
    final parent = to == null ? null : _entityMap[to];
    if (parent != null && !identical(parent, child)) {
      var children = parent.getComponent<ChildrenComponent>();
      if (children == null) {
        children = ChildrenComponent();
        parent.addComponent(children);
      }
      children.addChild(child.id);
    }
    _refreshActive(child);
  }

  /// Throws an [ArgumentError] when hanging [child] under the entity [to]
  /// would make [child] its own ancestor: [to] is [child], or is under it.
  void _checkLink(Entity child, EntityId to) {
    var id = to;
    // Bounded, in case links already loop (they cannot, made through here).
    for (var steps = 0; steps <= _entities.length; steps++) {
      if (id == child.id) {
        throw ArgumentError.value(
          to,
          'parentId',
          '$child cannot be parented under entity $to: that '
              '${to == child.id ? 'is the entity itself' : 'is under it'}',
        );
      }
      final next = _entityMap[id]?.getComponent<ParentComponent>()?.parentId;
      if (next == null) return;
      id = next;
    }
  }

  /// [entity] was switched on or off (called by [Entity.isActive]).
  void _activeChanged(Entity entity) => _refreshActive(entity);

  /// Works out [entity]'s [Entity.isActiveInHierarchy] again — it is
  /// switched on, and so is its parent in the hierarchy, when it has one in
  /// this world — and, when that changed, its subtree's.
  void _refreshActive(Entity entity) {
    if (!identical(entity._world, this)) return;
    final active = entity._isActive && _parentActive(entity);
    if (active == entity._activeInHierarchy) return;
    _setActiveInHierarchy(entity, active);

    final stack = <Entity>[entity];
    while (stack.isNotEmpty) {
      final parent = stack.removeLast();
      final children = parent.getComponent<ChildrenComponent>();
      if (children == null) continue;
      for (final id in children.childIds) {
        final child = _entityMap[id];
        if (child == null || identical(child, parent)) continue;
        // Listed, but linked elsewhere: not this parent's to switch.
        if (child.getComponent<ParentComponent>()?.parentId != parent.id) {
          continue;
        }
        final now = child._isActive && parent._activeInHierarchy;
        if (now == child._activeInHierarchy) continue;
        _setActiveInHierarchy(child, now);
        stack.add(child);
      }
    }
  }

  /// Whether [entity]'s parent is active in the hierarchy — true for an
  /// entity with none in this world.
  bool _parentActive(Entity entity) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    if (parentId == null) return true;
    final parent = _entityMap[parentId];
    if (parent == null || identical(parent, entity)) return true;
    return parent._activeInHierarchy;
  }

  void _setActiveInHierarchy(Entity entity, bool active) {
    entity._activeInHierarchy = active;
    _inactiveCount += active ? -1 : 1;
    final archetype = entity._archetype;
    if (archetype != null) {
      _touch(archetype);
      if (archetype._typeSet.contains(TagComponent)) {
        _tagIndex.activeChanged(entity);
      }
    }
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

  /// Every system, in the order they run. A snapshot: adding or removing
  /// systems while walking it is safe.
  UnmodifiableListView<System> get systems => UnmodifiableListView(_running);

  /// The entities active in the hierarchy ([Entity.isActiveInHierarchy]),
  /// oldest first.
  Iterable<Entity> get activeEntities =>
      _entities.where((e) => e._activeInHierarchy);

  /// Initialize the world
  void initialize() {
    if (_initialized) return;

    for (final system in _running) {
      if (identical(system._addedTo, this)) system.initialize();
    }

    _initialized = true;
    if (kDebugMode) {
      debugPrint('ECS World initialized with ${_systems.length} systems');
    }
  }

  /// Takes a new [entity] in.
  void _adopt(Entity entity) {
    entity._world = this;
    _entities.add(entity);
    _entityMap[entity.id] = entity;
    _indexName(entity);
    _entityList = null;
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
      // In the order given — a scene's as its file lists them — whatever
      // order the shared archetype keeps.
      entity._order = List.unmodifiable(compMap.keys);
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
      entity._order = null;
    }
    entity._components = null;

    if (!entity._activeInHierarchy) _inactiveCount--;
    entity._isActive = false;
    entity._activeInHierarchy = false;
    entity._world = null;
    _entityMap.remove(entity.id);
    _entities.remove(entity); // O(1) — LinkedHashSet
    final name = entity._name;
    if (name != null) _unindexName(entity, name);
    _entityList = null;

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
      entity._order = null;
      entity._components = null;
      entity._isActive = false;
      entity._activeInHierarchy = false;
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

    for (var i = 0; i < gone.length; i++) {
      for (final component in parts[i]) {
        if (component is TagComponent && identical(component._owner, gone[i])) {
          component._owner = null;
        }
        // No longer this world's to keep in step.
        if (component is ParentComponent) component.bindRelink(null);
        component.onDetach(gone[i].id);
      }
    }
  }

  /// Add a system to the world.
  ///
  /// It runs after every system of a higher priority, and after those of
  /// the same priority added before it. Adding one while the systems run —
  /// from a system's update, say — is safe: it runs from the next update
  /// on. Adding a system that is already in this world does nothing.
  void addSystem(System system) {
    if (identical(system._addedTo, this)) return;
    system.world = this;
    system._addedTo = this;
    system._addOrder = _systemsAdded++;
    var at = _systems.length;
    while (at > 0 && _systems[at - 1].priority < system.priority) {
      at--;
    }
    _systems.insert(at, system);
    _systemsSnapshot = null;

    if (_initialized) {
      system.initialize();
    }

    system.onAddedToWorld();
  }

  /// Puts the systems in priority order again — those of the same priority
  /// in the order they were added. They are placed as each is added; a
  /// [System.priority] that changed since — edited code after a hot reload
  /// — takes effect only once this runs. Systems already running this
  /// update keep the order they started in.
  void sortSystems() {
    _systems.sort(_runOrder);
    _systemsSnapshot = null;
  }

  static int _runOrder(System a, System b) {
    final byPriority = b.priority.compareTo(a.priority);
    return byPriority != 0 ? byPriority : a._addOrder.compareTo(b._addOrder);
  }

  /// Runs every active [FrameSystem], in priority order: once per rendered
  /// frame, after its fixed updates (see [FrameSystem.frame]).
  ///
  /// When one ran, the [transformHierarchy] settles again afterwards, so
  /// the children of what a frame system moved follow it in the same frame
  /// rather than at the next fixed update.
  void frame(double deltaTime, double alpha) {
    var ran = false;
    for (final system in _running) {
      if (system is! FrameSystem ||
          !system.isActive ||
          !identical(system._addedTo, this)) {
        continue;
      }
      (system as FrameSystem).frame(deltaTime, alpha);
      ran = true;
      if (commands.isNotEmpty) commands.flush();
    }
    if (ran && transformHierarchy.enabled) transformHierarchy.propagate();
  }

  /// Remove a system from the world: it hears
  /// [System.onRemovedFromWorld], then [System.dispose].
  ///
  /// Safe while the systems run — a system may remove itself, or another,
  /// from its own update; one removed before its turn does not run. A
  /// system that is not in this world is left alone.
  void removeSystem(System system) {
    if (!identical(system._addedTo, this)) return;
    system._addedTo = null;
    system.onRemovedFromWorld();
    _systems.remove(system);
    _systemsSnapshot = null;
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
  ///
  /// Safe while the systems run: the rest of that update skips the systems
  /// removed, and systems added afterwards run from the next update on.
  void clearSystems() {
    final removed = List.of(_systems);
    for (final system in removed) {
      system._addedTo = null;
    }
    for (final system in removed) {
      system.onRemovedFromWorld();
      system.dispose();
    }
    // Only those: one added by a callback above stays.
    final gone = Set<System>.identity()..addAll(removed);
    _systems.removeWhere(gone.contains);
    _systemsSnapshot = null;
  }

  /// Get a system by type
  T? getSystem<T extends System>() {
    return _systems.whereType<T>().firstOrNull;
  }

  /// Whether a system of type [T] (or a subtype) is in this world.
  bool hasSystem<T extends System>() => _systems.any((s) => s is T);

  /// Update all active systems, in order (see [addSystem]).
  ///
  /// Systems may add and remove systems — themselves included — and clear
  /// them all ([clearSystems]) while this runs: a system removed before its
  /// turn does not run, and one added runs from the next update on.
  void update(double deltaTime) {
    _updateCount++;
    final profile = profiling;
    if (profile) {
      _totalStopwatch
        ..reset()
        ..start();
    }
    if (_lastSystemTimesMs.isNotEmpty) _lastSystemTimesMs.clear();
    var flushCount = 0;

    var hierarchyDone = !transformHierarchy.enabled;
    for (final system in _running) {
      if (!hierarchyDone && system.priority < SystemPriorities.hierarchy) {
        _runHierarchy(profile);
        hierarchyDone = true;
      }
      // Removed by a system that ran before it.
      if (!identical(system._addedTo, this)) continue;
      if (system.isActive) {
        if (profile) {
          _systemStopwatch
            ..reset()
            ..start();
          try {
            system.update(deltaTime);
          } finally {
            _systemStopwatch.stop();
            _lastSystemTimesMs[system.profileName] =
                _systemStopwatch.elapsedMicroseconds / 1000.0;
          }
        } else {
          system.update(deltaTime);
        }
      }
      // Flush deferred commands between system ticks so later systems
      // see up-to-date entity state.
      if (commands.isNotEmpty) {
        commands.flush();
        flushCount++;
      }
    }

    if (!hierarchyDone) _runHierarchy(profile);

    if (profile) {
      _totalStopwatch.stop();
      _lastUpdateTimeMs = _totalStopwatch.elapsedMicroseconds / 1000.0;
    } else {
      _lastUpdateTimeMs = 0.0;
    }
    _lastCommandFlushCount = flushCount;
  }

  void _runHierarchy(bool profile) {
    if (!profile) {
      transformHierarchy.propagate();
      return;
    }
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
    for (final system in _running) {
      if (system.isActive && identical(system._addedTo, this)) {
        system.render(canvas, size);
      }
    }
  }

  /// Find the entities active in the hierarchy
  /// ([Entity.isActiveInHierarchy]) that have every one of
  /// [componentTypes]. An entity switched off, or under a parent that is,
  /// is left out.
  ///
  /// Results are cached per query and refreshed only when an archetype the
  /// query matches changes — an entity added or removed, or switched on or
  /// off — so asking again each frame is a lookup. Uses archetype-based
  /// iteration: only archetypes whose type-set is a superset of
  /// [componentTypes] are scanned, skipping unrelated entities.
  ///
  /// The list is never changed after it is returned; a later change makes
  /// a new one (and moves [queryVersion] on).
  List<Entity> query(List<Type> componentTypes) {
    final entry = _queryEntryFor(componentTypes);
    return entry.entities ??= _collect(entry);
  }

  UnmodifiableListView<Entity> _collect(_QueryCacheEntry entry) {
    final result = <Entity>[];
    for (final archetype in entry.archetypes) {
      for (final entity in archetype._entities) {
        if (entity._activeInHierarchy) result.add(entity);
      }
    }
    return UnmodifiableListView(result);
  }

  /// A number that moves on whenever the entities [componentTypes] match
  /// may have changed — for a system that keeps something per matching
  /// entity (a draw list, physics bodies, a cache of components) and
  /// rebuilds it only when its own queries changed.
  ///
  /// It changes when an entity with all of [componentTypes] is created or
  /// destroyed, gains or loses any component (which moves it to another
  /// archetype), has a component replaced (`addComponent` of a type it
  /// already has), or is switched on or off — itself, or with a parent
  /// ([Entity.isActiveInHierarchy]) — and when a new archetype the query
  /// matches appears ([queryArchetypes]). What happens to entities the
  /// query cannot match leaves it alone.
  ///
  /// Versions are unique within the world and only go up, so the largest
  /// of several queries' versions changes whenever any one of them does,
  /// and a query asked for the first time — or again after
  /// [destroyAllEntities] — never has a version seen before.
  int queryVersion(List<Type> componentTypes) =>
      _queryEntryFor(componentTypes).version;

  /// Return all [Archetype]s whose component set is a superset of
  /// [componentTypes].
  ///
  /// This allows systems to iterate dense component columns directly for
  /// maximum cache-friendliness instead of going through per-entity
  /// [Entity.getComponent] lookups.
  ///
  /// Unlike [query], this does **not** leave out entities that are switched
  /// off: an archetype holds every entity with its components. A caller
  /// must skip rows whose entity is not active in the hierarchy
  /// (`archetype.entityAt(row).isActiveInHierarchy`).
  Iterable<Archetype> queryArchetypes(List<Type> componentTypes) =>
      _queryEntryFor(componentTypes).archetypes;

  /// The oldest entity named [name], or null.
  ///
  /// Switched-off entities count unless [includeInactive] is false, when
  /// the oldest one active in the hierarchy
  /// ([Entity.isActiveInHierarchy]) is returned. Backed by an index, so it
  /// costs a map lookup rather than a scan.
  Entity? findEntityByName(String name, {bool includeInactive = true}) {
    final named = _byName[name];
    if (named == null) return null;
    for (final entity in named) {
      if (includeInactive || entity._activeInHierarchy) return entity;
    }
    return null;
  }

  /// The oldest entity tagged [tag], or null. Entities not active in the
  /// hierarchy ([Entity.isActiveInHierarchy]) are passed over unless
  /// [includeInactive].
  ///
  /// Backed by an index, so it costs a map lookup rather than a scan.
  Entity? findTagged(String tag, {bool includeInactive = false}) =>
      _tagIndex.first(tag, includeInactive);

  /// Every entity tagged [tag], oldest first. Entities not active in the
  /// hierarchy ([Entity.isActiveInHierarchy]) are left out unless
  /// [includeInactive].
  ///
  /// The list cannot be changed, and is shared: it is reused until a tag
  /// set or an entity's [Entity.isActiveInHierarchy] changes, so asking
  /// every frame does not allocate.
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
    if (kDebugMode) debugPrint('ECS World disposed');
  }

  /// Statistics, made when read. `activeEntities` counts the entities
  /// active in the hierarchy; `lastUpdateMs` and `systemTimesMs` (each
  /// system's last update, by [System.profileName]) are measured only
  /// while [profiling] is on.
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

/// One cached query: the archetypes it matches, its current result, and
/// its version.
class _QueryCacheEntry {
  _QueryCacheEntry(this.types, this.version);

  /// The component types asked for.
  final Set<Type> types;

  /// See [World.queryVersion].
  int version;

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
