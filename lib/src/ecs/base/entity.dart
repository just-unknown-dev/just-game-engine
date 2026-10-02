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

  bool _isActive = true;

  String? _name;

  /// Create an entity with the given ID.
  Entity(
    this.id, {
    @Deprecated('Entity ids are never reused; there is no generation.')
    this.generation = 0,
    String? name,
  }) : _name = name;

  /// Whether this entity is switched on — the scene's "enabled" flag.
  ///
  /// An inactive entity stays in the world but drops out of
  /// [World.query] results, so the systems pass it by. Changing it tells the
  /// entity's world, which refreshes its cached queries and moves
  /// [World.structureVersion] on.
  bool get isActive => _isActive;
  set isActive(bool value) {
    if (_isActive == value) return;
    _isActive = value;
    _world?._activeChanged(this);
  }

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

  /// Check if entity has a component of the specified type
  bool hasComponent<T extends Component>() {
    return _archetype?._typeSet.contains(T) ?? false;
  }

  /// Check if entity has a component by runtime [type].
  bool hasComponentByType(Type type) {
    return _archetype?._typeSet.contains(type) ?? false;
  }

  /// Get all components
  Iterable<Component> get components {
    if (_archetype == null || _archetypeRow < 0) return const [];
    return _archetype!.getComponents(_archetypeRow);
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
