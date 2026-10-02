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
  /// Signals over the given entity, labelled [debugLabel] (by default
  /// `EntitySignal(<id>)`). Component signals are made as they are asked
  /// for.
  EntitySignal(this._entity, {String? debugLabel})
    : _debugLabel = debugLabel ?? 'EntitySignal(${_entity.id})';

  final Entity _entity;
  final String _debugLabel;

  // Stores Signal<T?> for each component type T, keyed by Type.
  // Declared as Map<Type, dynamic> so that Signal<T?> values (which are
  // invariant in T) can coexist in the same map without invalid variance casts.
  final Map<Type, dynamic> _componentSignals = {};
  late final Signal<bool> _activeSignal = Signal(
    _entity.isActive,
    debugLabel: 'Entity.isActive',
  );

  /// The underlying entity.
  Entity get entity => _entity;

  /// The entity ID.
  EntityId get id => _entity.id;

  /// Signal for the entity's active state: the entity's `isActive` when
  /// first read, then as of the last [sync].
  Signal<bool> get isActive => _activeSignal;

  /// Returns the signal for a component [type] if it already exists, or null.
  ///
  /// Unlike [component], this does **not** create the signal lazily.
  /// Exposes the raw signal as [Signal<Component?>] for callers that only
  /// need change notification (e.g. [ReactiveSystem] watch hooks).
  Signal<Component?>? componentSignalByType(Type type) {
    final s = _componentSignals[type];
    if (s == null) return null;
    return s as Signal<Component?>;
  }

  /// Gets or creates a [Signal<T?>] for the given component type.
  ///
  /// The signal holds `null` when the component is not present on the entity.
  Signal<T?> component<T extends Component>() {
    if (_componentSignals.containsKey(T)) {
      return _componentSignals[T] as Signal<T?>;
    }
    final signal = Signal<T?>(
      _entity.getComponent<T>(),
      debugLabel: '$_debugLabel.$T',
    );
    _componentSignals[T] = signal;
    return signal;
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
      // entry.value is Signal<T?> stored via dynamic — use dynamic dispatch
      // so the assignment is checked against the actual (correct) runtime type.
      final dynamic signal = entry.value;

      // Matched by componentType — the type the world files a component
      // under, and so the one component<T>() finds it by.
      Component? current;
      for (final comp in _entity.components) {
        if (comp.componentType == type) {
          current = comp;
          break;
        }
      }
      signal.value = current;
    }
  }

  /// Notifies that a component was added.
  void notifyComponentAdded<T extends Component>(T component) {
    final dynamic signal = _componentSignals[T];
    if (signal != null) {
      signal.value = component;
    }
  }

  /// Notifies that a component was removed.
  void notifyComponentRemoved<T extends Component>() {
    final dynamic signal = _componentSignals[T];
    if (signal != null) {
      signal.value = null;
    }
  }

  /// Disposes every signal made here, [isActive] included. The entity is
  /// left as it is.
  void dispose() {
    for (final dynamic signal in _componentSignals.values) {
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
