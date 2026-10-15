part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Entity
// ════════════════════════════════════════════════════════════════════════════

/// Entity - A lightweight handle for components stored in an [Archetype].
///
/// Entities are just IDs with associated components.
/// All logic is handled by systems.
///
/// A world never reuses an id — not after [World.destroyEntity], not after
/// [World.destroyAllEntities] — so a handle kept past its entity's end can
/// never be mistaken for a newer entity. Use [isAlive] (or
/// [World.isEntityAlive]) to check whether a held reference still points to
/// a live entity.
class Entity {
  /// Unique entity ID
  final EntityId id;

  /// Always 0 for an entity a [World] makes.
  ///
  /// It counted reuses of an id slot, but a world no longer reuses ids.
  @Deprecated(
    'Entity ids are never reused, so there is no generation to compare; '
    'use isAlive or World.isEntityAlive. Will be removed in 3.0.',
  )
  int generation;

  /// Reference to owning world for structural mutations.
  World? _world;

  /// The archetype this entity currently resides in (null if no components).
  Archetype? _archetype;

  /// Row index within [_archetype]'s dense arrays.
  int _archetypeRow = -1;

  /// This entity's component types in its own order: as they were added,
  /// unless [reorderComponents] said otherwise. Its archetype is shared with
  /// every entity of the same types, so it cannot keep one entity's order.
  /// Never changed in place — replaced — so an iteration over [components]
  /// is not disturbed by a change. Null with no components.
  List<Type>? _order;

  /// What [components] returns until this entity's components change.
  List<Component>? _components;

  bool _isActive = true;

  /// [isActiveInHierarchy] as its world keeps it.
  bool _activeInHierarchy = true;

  String? _name;

  /// Create an entity with the given ID.
  Entity(
    this.id, {
    @Deprecated('Entity ids are never reused; there is no generation.')
    this.generation = 0,
    String? name,
  }) : _name = name;

  /// Whether this entity itself is switched on — the scene's saved
  /// "enabled" flag, which an editor shows and saves.
  ///
  /// Switched off, the entity stays in the world but drops out of
  /// [World.query] results, so the systems pass it by — and so does
  /// everything under it in the hierarchy, whose own flags are kept as
  /// they are: see [isActiveInHierarchy], which is what decides. Changing
  /// it tells the entity's world, which refreshes its cached queries and
  /// moves their [World.queryVersion]s on.
  bool get isActive => _isActive;
  set isActive(bool value) {
    if (_isActive == value) return;
    _isActive = value;
    _world?._activeChanged(this);
  }

  /// Whether this entity takes part in the game: it is switched on
  /// ([isActive]), and so is every parent above it in the hierarchy (its
  /// `ParentComponent`'s, and theirs) — Unity's `activeInHierarchy`.
  ///
  /// This is what [World.query], [World.findTagged] and the engine's
  /// systems go by: an entity under a switched-off parent is not queried,
  /// drawn or simulated, whatever its own [isActive]. Kept up to date by
  /// the world as entities are switched on and off, re-parented, made and
  /// destroyed, so reading it costs nothing. False once destroyed.
  bool get isActiveInHierarchy => _isActive && _activeInHierarchy;

  /// Optional entity name, for finding it ([World.findEntityByName]) and for
  /// debugging. Renaming updates the world's name index.
  String? get name => _name;
  set name(String? value) {
    if (_name == value) return;
    final old = _name;
    _name = value;
    _world?._renamed(this, old);
  }

  /// Whether this entity is still owned by a world (not destroyed).
  bool get isAlive => _world != null;

  /// The world this entity lives in — null once it has been destroyed.
  World? get world => _world;

  /// Add a component to this entity
  void addComponent(Component component) {
    _world?._addComponentToEntity(this, component);
  }

  /// Remove a component from this entity
  void removeComponent<T extends Component>() {
    _world?._removeComponentFromEntity(this, T);
  }

  /// Remove a component by runtime [type].
  void removeComponentByType(Type type) {
    _world?._removeComponentFromEntity(this, type);
  }

  /// Get a component of the specified type
  T? getComponent<T extends Component>() {
    return _archetype?.getComponent<T>(_archetypeRow);
  }

  /// The component filed under the runtime [type] (its
  /// `Component.componentType`), or null.
  Component? getComponentByType(Type type) {
    return _archetype?.getComponentByType(type, _archetypeRow);
  }

  /// Check if entity has a component of the specified type
  bool hasComponent<T extends Component>() {
    return _archetype?._typeSet.contains(T) ?? false;
  }

  /// Check if entity has a component by runtime [type].
  bool hasComponentByType(Type type) {
    return _archetype?._typeSet.contains(type) ?? false;
  }

  /// Every component, in this entity's order: as they were added — a scene's
  /// as its file lists them — unless [reorderComponents] put them otherwise.
  /// A scene saves them in this order. Systems find components by type, so
  /// the order changes nothing in how the game runs.
  ///
  /// The list cannot be changed, and is made once and kept until this
  /// entity's components change, so asking every frame costs nothing. A
  /// change makes a new one: walking this one while the entity gains or
  /// loses components is safe, and lists what it had when asked.
  List<Component> get components {
    final known = _components;
    if (known != null) return known;
    final archetype = _archetype;
    final row = _archetypeRow;
    if (archetype == null || row < 0) return const [];
    final order = _order;
    final types = order != null && order.length == archetype._typeSet.length
        ? order
        : archetype._typeList;
    return _components = List<Component>.unmodifiable([
      for (final type in types) archetype._columns[type]![row],
    ]);
  }

  /// The types [components] are filed under (`Component.componentType`), in
  /// the same order.
  List<Type> get componentTypes {
    final order = _order;
    if (order != null) return order;
    return List.unmodifiable(_archetype?._typeList ?? const <Type>[]);
  }

  /// Puts this entity's components in the order of [types] — each a
  /// `Component.componentType` — those listed first, as listed, then the
  /// rest as they were. Types it has no component of are passed over.
  ///
  /// For an editor that lets components be rearranged: what [components]
  /// lists, and so what a scene file saves. Nothing else changes — not the
  /// components, not which systems see the entity.
  void reorderComponents(Iterable<Type> types) {
    final current = _order;
    if (current == null) return;
    final placed = <Type>{};
    final next = <Type>[
      for (final type in types)
        if (current.contains(type) && placed.add(type)) type,
      for (final type in current)
        if (!placed.contains(type)) type,
    ];
    _order = List.unmodifiable(next);
    _components = null;
  }

  /// Check if entity has all specified component types
  bool hasComponents(List<Type> types) {
    final archetype = _archetype;
    if (archetype == null) return types.isEmpty;
    return types.every(archetype._typeSet.contains);
  }

  @override
  String toString() => 'Entity($id${name != null ? ', $name' : ''})';
}
