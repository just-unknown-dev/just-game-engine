/// Entity-Component System (ECS)
///
/// A flexible architecture for organizing game logic where:
/// - Entities are containers for components (just an ID)
/// - Components are pure data (no logic)
/// - Systems process entities with specific components
library;

import 'dart:collection';
import 'package:flutter/material.dart';

/// Unique identifier for an entity
typedef EntityId = int;

/// Base class for all components
///
/// Components are pure data containers with no logic.
/// Override to create custom component types.
abstract class Component {
  /// Type identifier for this component
  Type get componentType => runtimeType;
}

/// Entity - A container for components
///
/// Entities are just IDs with associated components.
/// All logic is handled by systems.
class Entity {
  /// Unique entity ID
  final EntityId id;

  /// Map of component types to component instances
  final Map<Type, Component> _components = {};

  /// Whether this entity is active
  bool isActive = true;

  /// Optional entity name for debugging
  String? name;

  /// Create an entity with the given ID
  Entity(this.id, {this.name});

  /// Add a component to this entity
  void addComponent(Component component) {
    _components[component.componentType] = component;
  }

  /// Remove a component from this entity
  void removeComponent<T extends Component>() {
    _components.remove(T);
  }

  /// Get a component of the specified type
  T? getComponent<T extends Component>() {
    return _components[T] as T?;
  }

  /// Check if entity has a component of the specified type
  bool hasComponent<T extends Component>() {
    return _components.containsKey(T);
  }

  /// Get all components
  Iterable<Component> get components => _components.values;

  /// Check if entity has all specified component types
  bool hasComponents(List<Type> types) {
    return types.every((type) => _components.containsKey(type));
  }

  @override
  String toString() => 'Entity($id${name != null ? ', $name' : ''})';
}

/// Base class for all systems
///
/// Systems contain logic and operate on entities with specific components.
/// Override update() to implement system logic.
abstract class System {
  /// World this system belongs to
  late World world;

  /// Required component types for this system
  List<Type> get requiredComponents;

  /// Whether this system is active
  bool isActive = true;

  /// Priority for system execution order (higher = earlier)
  int priority = 0;

  /// Initialize the system
  void initialize() {}

  /// Update the system
  void update(double deltaTime) {}

  /// Render the system (optional)
  void render(Canvas canvas, Size size) {}

  /// Called when system is added to world
  void onAddedToWorld() {}

  /// Called when system is removed from world
  void onRemovedFromWorld() {}

  /// Dispose system resources
  void dispose() {}

  /// Get all entities that match this system's requirements
  Iterable<Entity> get entities {
    return world.entities.where(
      (entity) => entity.isActive && entity.hasComponents(requiredComponents),
    );
  }

  /// Execute a function for each matching entity
  void forEach(void Function(Entity entity) action) {
    for (final entity in entities) {
      action(entity);
    }
  }
}

/// ECS World - Manages all entities and systems
///
/// The central manager for the Entity-Component System.
/// Creates entities, manages systems, and coordinates updates.
class World {
  /// All entities in the world
  final List<Entity> _entities = [];

  /// All systems in the world
  final List<System> _systems = [];

  /// Entity ID counter
  int _nextEntityId = 0;

  /// Whether the world is initialized
  bool _initialized = false;

  /// Get all entities
  UnmodifiableListView<Entity> get entities => UnmodifiableListView(_entities);

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
    final entity = Entity(_nextEntityId++, name: name);
    _entities.add(entity);
    return entity;
  }

  /// Create an entity with components
  Entity createEntityWithComponents(
    List<Component> components, {
    String? name,
  }) {
    final entity = createEntity(name: name);
    for (final component in components) {
      entity.addComponent(component);
    }
    return entity;
  }

  /// Destroy an entity
  void destroyEntity(Entity entity) {
    entity.isActive = false;
    _entities.remove(entity);
  }

  /// Destroy all entities
  void destroyAllEntities() {
    _entities.clear();
    _nextEntityId = 0;
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

  /// Get a system by type
  T? getSystem<T extends System>() {
    return _systems.whereType<T>().firstOrNull;
  }

  /// Update all active systems
  void update(double deltaTime) {
    for (final system in _systems) {
      if (system.isActive) {
        system.update(deltaTime);
      }
    }
  }

  /// Render all active systems
  void render(Canvas canvas, Size size) {
    for (final system in _systems) {
      if (system.isActive) {
        system.render(canvas, size);
      }
    }
  }

  /// Find entities with specific components
  Iterable<Entity> query(List<Type> componentTypes) {
    return activeEntities.where(
      (entity) => entity.hasComponents(componentTypes),
    );
  }

  /// Find entity by name
  Entity? findEntityByName(String name) {
    return _entities.where((e) => e.name == name).firstOrNull;
  }

  /// Get entity by ID
  Entity? getEntity(EntityId id) {
    return _entities.where((e) => e.id == id).firstOrNull;
  }

  /// Dispose the world and all systems
  void dispose() {
    for (final system in _systems) {
      system.dispose();
    }
    _systems.clear();
    _entities.clear();
    _initialized = false;
    debugPrint('ECS World disposed');
  }

  /// Get statistics
  Map<String, dynamic> get stats => {
    'totalEntities': _entities.length,
    'activeEntities': activeEntities.length,
    'systems': _systems.length,
    'activeSystems': _systems.where((s) => s.isActive).length,
  };
}
