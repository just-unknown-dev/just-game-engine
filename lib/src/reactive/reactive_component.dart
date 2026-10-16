library;

import 'dart:ui' show VoidCallback;

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';

/// A mixin for components that want built-in change notification.
///
/// ReactiveComponent provides automatic signal creation for component
/// properties, making them reactive without manual signal setup.
///
/// ```dart
/// class PlayerComponent extends Component with ReactiveComponent {
///   double _health = 100;
///
///   double get health => _health;
///   set health(double value) {
///     if (_health != value) {
///       _health = value;
///       notifyChange('health');
///     }
///   }
/// }
/// ```
mixin ReactiveComponent on Component {
  final Map<String, Signal<dynamic>> _propertySignals = {};
  final Set<VoidCallback> _changeListeners = {};
  bool _isBatching = false;
  final Set<String> _pendingChanges = {};

  /// Gets or creates a signal for a named property.
  Signal<T> propertySignal<T>(String name, T initialValue) {
    return _propertySignals.putIfAbsent(
          name,
          () => Signal<T>(initialValue, debugLabel: '$runtimeType.$name'),
        )
        as Signal<T>;
  }

  /// Notifies that a property has changed.
  void notifyChange(String propertyName) {
    if (_isBatching) {
      _pendingChanges.add(propertyName);
      return;
    }

    _dispatchChange(propertyName);
  }

  void _dispatchChange(String propertyName) {
    // Notify property-specific signal
    final signal = _propertySignals[propertyName];
    if (signal != null) {
      signal.forceSet(signal.value);
    }

    // Notify general listeners
    for (final listener in List.from(_changeListeners)) {
      if (_changeListeners.contains(listener)) {
        listener();
      }
    }
  }

  /// Batches multiple property changes into a single notification.
  void batchChanges(void Function() changes) {
    _isBatching = true;
    try {
      changes();
    } finally {
      _isBatching = false;
      // Dispatch all pending changes
      for (final name in _pendingChanges) {
        _dispatchChange(name);
      }
      _pendingChanges.clear();
    }
  }

  /// Adds a listener for any property change.
  void addChangeListener(VoidCallback listener) {
    _changeListeners.add(listener);
  }

  /// Removes a change listener.
  void removeChangeListener(VoidCallback listener) {
    _changeListeners.remove(listener);
  }

  /// Disposes all signals and listeners.
  void disposeReactive() {
    for (final signal in _propertySignals.values) {
      signal.dispose();
    }
    _propertySignals.clear();
    _changeListeners.clear();
  }
}
