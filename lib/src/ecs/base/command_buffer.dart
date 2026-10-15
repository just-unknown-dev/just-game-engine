part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Command Buffer — deferred entity/component mutations
// ════════════════════════════════════════════════════════════════════════════

/// A buffer that collects structural mutations (create, destroy, add/remove
/// component) during system updates and applies them in a batch after
/// iteration is complete — in the order they were queued, so
/// `removeComponent<Sprite>(e)` then `addComponent(e, newSprite)` ends with
/// the new sprite.
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

  List<_Command> _commands = [];

  /// An empty buffer that applies its commands to the given world.
  CommandBuffer(this._world);

  /// Schedule entity creation with the given components.
  /// Returns nothing — use [flush] results or query after flush.
  void create(List<Component> components, {String? name}) {
    _commands.add(_DeferredCreate(components, name));
  }

  /// Schedule entity destruction; see [World.destroyEntity] for
  /// [withChildren].
  void destroy(Entity entity, {bool withChildren = true}) {
    _commands.add(_DeferredDestroy(entity, withChildren));
  }

  /// Schedule adding a component to an existing entity.
  void addComponent(Entity entity, Component component) {
    _commands.add(_DeferredAddComponent(entity, component));
  }

  /// Schedule removing a component type from an entity.
  void removeComponent<T extends Component>(Entity entity) {
    _commands.add(_DeferredRemoveComponent(entity, T));
  }

  /// Whether any commands are pending.
  bool get isNotEmpty => _commands.isNotEmpty;

  /// Apply all buffered commands to the world, in the order they were
  /// queued, and clear the buffer.
  ///
  /// A command on an entity that is gone by then is skipped. Commands queued
  /// while flushing (by a component's `onAttach`, say) run in this flush,
  /// after the ones already queued.
  ///
  /// A command that throws does not stop the rest: every command is run,
  /// and then the first error is rethrown, with its stack trace.
  void flush() {
    Object? firstError;
    StackTrace? firstStack;
    while (_commands.isNotEmpty) {
      final batch = _commands;
      _commands = [];
      for (final command in batch) {
        try {
          command.apply(_world);
        } catch (error, stack) {
          if (firstError == null) {
            firstError = error;
            firstStack = stack;
          }
        }
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

sealed class _Command {
  void apply(World world);
}

class _DeferredCreate extends _Command {
  final List<Component> components;
  final String? name;
  _DeferredCreate(this.components, this.name);

  @override
  void apply(World world) =>
      world.createEntityWithComponents(components, name: name);
}

class _DeferredDestroy extends _Command {
  final Entity entity;
  final bool withChildren;
  _DeferredDestroy(this.entity, this.withChildren);

  @override
  void apply(World world) {
    if (identical(entity._world, world)) {
      world.destroyEntity(entity, withChildren: withChildren);
    }
  }
}

class _DeferredAddComponent extends _Command {
  final Entity entity;
  final Component component;
  _DeferredAddComponent(this.entity, this.component);

  @override
  void apply(World world) {
    if (entity._world != null) entity.addComponent(component);
  }
}

class _DeferredRemoveComponent extends _Command {
  final Entity entity;
  final Type type;
  _DeferredRemoveComponent(this.entity, this.type);

  @override
  void apply(World world) {
    if (entity._world != null) entity.removeComponentByType(type);
  }
}
