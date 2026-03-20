part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Command Buffer — deferred entity/component mutations
// ════════════════════════════════════════════════════════════════════════════

/// A buffer that collects structural mutations (create, destroy, add/remove
/// component) during system updates and applies them in a batch after
/// iteration is complete.
///
/// This prevents concurrent modification when systems destroy or create
/// entities while iterating query results.
///
/// Usage:
/// ```dart
/// // Inside a System.update():
/// world.commands.destroy(entity);      // deferred
/// world.commands.create([Health(100)]); // deferred
///
/// // World.update() flushes automatically between system ticks.
/// ```
class CommandBuffer {
  final World _world;

  final List<_DeferredCreate> _creates = [];
  final List<Entity> _destroys = [];
  final List<_DeferredAddComponent> _adds = [];
  final List<_DeferredRemoveComponent> _removes = [];

  CommandBuffer(this._world);

  /// Schedule entity creation with the given components.
  /// Returns nothing — use [flush] results or query after flush.
  void create(List<Component> components, {String? name}) {
    _creates.add(_DeferredCreate(components, name));
  }

  /// Schedule entity destruction.
  void destroy(Entity entity) {
    _destroys.add(entity);
  }

  /// Schedule adding a component to an existing entity.
  void addComponent(Entity entity, Component component) {
    _adds.add(_DeferredAddComponent(entity, component));
  }

  /// Schedule removing a component type from an entity.
  void removeComponent<T extends Component>(Entity entity) {
    _removes.add(_DeferredRemoveComponent(entity, T));
  }

  /// Whether any commands are pending.
  bool get isNotEmpty =>
      _creates.isNotEmpty ||
      _destroys.isNotEmpty ||
      _adds.isNotEmpty ||
      _removes.isNotEmpty;

  /// Apply all buffered commands to the world and clear the buffer.
  void flush() {
    // Process destroys first (avoids adding components to doomed entities).
    for (final entity in _destroys) {
      if (entity._world != null) {
        _world.destroyEntity(entity);
      }
    }
    _destroys.clear();

    // Process creates.
    for (final cmd in _creates) {
      _world.createEntityWithComponents(cmd.components, name: cmd.name);
    }
    _creates.clear();

    // Process component additions.
    for (final cmd in _adds) {
      if (cmd.entity._world != null) {
        cmd.entity.addComponent(cmd.component);
      }
    }
    _adds.clear();

    // Process component removals.
    for (final cmd in _removes) {
      if (cmd.entity._world != null) {
        _world._removeComponentFromEntity2(cmd.entity, cmd.type);
      }
    }
    _removes.clear();
  }
}

class _DeferredCreate {
  final List<Component> components;
  final String? name;
  _DeferredCreate(this.components, this.name);
}

class _DeferredAddComponent {
  final Entity entity;
  final Component component;
  _DeferredAddComponent(this.entity, this.component);
}

class _DeferredRemoveComponent {
  final Entity entity;
  final Type type;
  _DeferredRemoveComponent(this.entity, this.type);
}
