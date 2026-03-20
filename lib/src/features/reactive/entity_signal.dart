library;

import 'package:flutter/foundation.dart';

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';

/// A signal that tracks entity-level events like component changes.
///
/// EntitySignal provides reactive access to an entity's components
/// and notifies when components are added or removed.
///
/// ```dart
/// final entitySignal = EntitySignal(entity);
///
/// // Watch for specific component
/// entitySignal.watch<HealthComponent>((health) {
///   print('Health changed: ${health?.health}');
/// });
///
/// // React to component additions/removals
/// Effect(() {
///   final hasHealth = entitySignal.has<HealthComponent>();
///   print('Entity has health: $hasHealth');
///   return null;
/// });
/// ```
class EntitySignal {
  EntitySignal(this._entity, {String? debugLabel})
    : _debugLabel = debugLabel ?? 'EntitySignal(${_entity.id})';

  final Entity _entity;
  final String _debugLabel;

  final Map<Type, Signal<Component?>> _componentSignals = {};
  final Signal<bool> _activeSignal = Signal(
    true,
    debugLabel: 'Entity.isActive',
  );

  /// The underlying entity.
  Entity get entity => _entity;

  /// The entity ID.
  EntityId get id => _entity.id;

  /// Signal for the entity's active state.
  Signal<bool> get isActive => _activeSignal;

  /// Gets or creates a signal for a specific component type.
  ///
  /// The signal's value will be null if the component doesn't exist.
  Signal<T?> component<T extends Component>() {
    return _componentSignals.putIfAbsent(
          T,
          () => Signal<Component?>(
            _entity.getComponent<T>(),
            debugLabel: '$_debugLabel.$T',
          ),
        )
        as Signal<T?>;
  }

  /// Checks if the entity has a component (reactive).
  bool has<T extends Component>() {
    return component<T>().value != null;
  }

  /// Gets a component value directly (reactive read).
  T? get<T extends Component>() {
    return component<T>().value;
  }

  /// Watches a component and calls the callback when it changes.
  ///
  /// Returns a dispose function to stop watching.
  VoidCallback watch<T extends Component>(
    void Function(T? component) callback,
  ) {
    final signal = component<T>();
    void listener() => callback(signal.value);
    signal.addListener(listener);
    // Call immediately with current value
    callback(signal.value);
    return () => signal.removeListener(listener);
  }

  /// Syncs all component signals with the entity's current state.
  ///
  /// Call this after the entity is modified externally.
  void sync() {
    _activeSignal.value = _entity.isActive;

    for (final entry in _componentSignals.entries) {
      final type = entry.key;
      final signal = entry.value;

      // Use reflection-free approach - check if component exists
      Component? current;
      for (final comp in _entity.components) {
        if (comp.runtimeType == type) {
          current = comp;
          break;
        }
      }
      signal.value = current;
    }
  }

  /// Notifies that a component was added.
  void notifyComponentAdded<T extends Component>(T component) {
    final signal = _componentSignals[T];
    if (signal != null) {
      signal.value = component;
    }
  }

  /// Notifies that a component was removed.
  void notifyComponentRemoved<T extends Component>() {
    final signal = _componentSignals[T];
    if (signal != null) {
      signal.value = null;
    }
  }

  void dispose() {
    for (final signal in _componentSignals.values) {
      signal.dispose();
    }
    _componentSignals.clear();
    _activeSignal.dispose();
  }

  @override
  String toString() => _debugLabel;
}

/// Extension on Entity to create reactive wrappers.
extension ReactiveEntityExtension on Entity {
  /// Creates a reactive signal wrapper for this entity.
  EntitySignal toSignal({String? debugLabel}) {
    return EntitySignal(this, debugLabel: debugLabel);
  }
}
