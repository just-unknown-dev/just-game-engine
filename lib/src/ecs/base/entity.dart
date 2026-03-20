part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Entity
// ════════════════════════════════════════════════════════════════════════════

/// Entity - A lightweight handle for components stored in an [Archetype].
///
/// Entities are just IDs with associated components.
/// All logic is handled by systems.
///
/// Each entity carries a [generation] counter that is incremented every time
/// the slot is recycled. Use [isAlive] to check whether a held reference
/// still points to a live entity (guards against use-after-destroy).
class Entity {
  /// Unique entity ID
  final EntityId id;

  /// Generation counter — incremented when the id slot is recycled.
  int generation;

  /// Reference to owning world for structural mutations.
  World? _world;

  /// The archetype this entity currently resides in (null if no components).
  Archetype? _archetype;

  /// Row index within [_archetype]'s dense arrays.
  int _archetypeRow = -1;

  /// Whether this entity is active
  bool isActive = true;

  /// Optional entity name for debugging
  String? name;

  /// Create an entity with the given ID and [generation].
  Entity(this.id, {this.generation = 0, this.name});

  /// Whether this entity is still owned by a world (not destroyed).
  bool get isAlive => _world != null;

  /// Add a component to this entity
  void addComponent(Component component) {
    _world?._addComponentToEntity(this, component);
  }

  /// Remove a component from this entity
  void removeComponent<T extends Component>() {
    _world?._removeComponentFromEntity<T>(this);
  }

  /// Get a component of the specified type
  T? getComponent<T extends Component>() {
    return _archetype?.getComponent<T>(_archetypeRow);
  }

  /// Check if entity has a component of the specified type
  bool hasComponent<T extends Component>() {
    return _archetype?.types.contains(T) ?? false;
  }

  /// Get all components
  Iterable<Component> get components {
    if (_archetype == null || _archetypeRow < 0) return const [];
    return _archetype!.getComponents(_archetypeRow);
  }

  /// Check if entity has all specified component types
  bool hasComponents(List<Type> types) {
    if (_archetype == null) return types.isEmpty;
    return types.every((type) => _archetype!.types.contains(type));
  }

  @override
  String toString() => 'Entity($id${name != null ? ', $name' : ''})';
}
