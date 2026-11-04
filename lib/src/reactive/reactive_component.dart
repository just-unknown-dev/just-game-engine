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
///
///   late final healthSignal = propertySignal('health', () => health);
/// }
/// ```
mixin ReactiveComponent on Component {
  final Map<String, Signal<dynamic>> _propertySignals = {};
  final Map<String, Object? Function()> _propertyReaders = {};
  final Set<VoidCallback> _changeListeners = {};
  bool _isBatching = false;
  final Set<String> _pendingChanges = {};

  /// Gets or creates a signal for a named property, holding what [read]
  /// gives: read now, and again each time [notifyChange] names [name], so
  /// the signal always carries the property's new value. Asked again for
  /// the same [name], it returns the signal made the first time.
  Signal<T> propertySignal<T>(String name, T Function() read) {
    return _propertySignals.putIfAbsent(name, () {
          _propertyReaders[name] = read;
          return Signal<T>(read(), debugLabel: '$runtimeType.$name');
        })
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
    // The property's signal takes its new value, and its listeners hear
    // of the change even when the value compares equal.
    final signal = _propertySignals[propertyName];
    if (signal != null) {
      signal.forceSet(_propertyReaders[propertyName]!());
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
    _propertyReaders.clear();
    _changeListeners.clear();
  }
}
