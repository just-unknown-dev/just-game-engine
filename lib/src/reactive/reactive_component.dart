library;

import 'dart:ui';

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';
import '../ecs/components/components.dart';

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

/// A reactive transform component with built-in signals.
class ReactiveTransformComponent extends TransformComponent
    with ReactiveComponent {
  ReactiveTransformComponent({super.position, super.rotation, super.scale});

  @override
  set position(Offset value) {
    if (super.position != value) {
      super.position = value;
      notifyChange('position');
    }
  }

  @override
  set rotation(double value) {
    if (super.rotation != value) {
      super.rotation = value;
      notifyChange('rotation');
    }
  }

  @override
  set scale(double value) {
    if (super.scale != value) {
      super.scale = value;
      notifyChange('scale');
    }
  }

  @override
  void translate(Offset offset) {
    super.translate(offset);
    notifyChange('position');
  }

  @override
  void rotate(double angle) {
    super.rotate(angle);
    notifyChange('rotation');
  }
}

/// A reactive velocity component with built-in signals.
class ReactiveVelocityComponent extends VelocityComponent
    with ReactiveComponent {
  ReactiveVelocityComponent({super.velocity, super.maxSpeed});

  @override
  set velocity(Offset value) {
    if (super.velocity != value) {
      super.velocity = value;
      notifyChange('velocity');
    }
  }

  @override
  set maxSpeed(double value) {
    if (super.maxSpeed != value) {
      super.maxSpeed = value;
      notifyChange('maxSpeed');
    }
  }
}

/// A reactive health component with built-in signals.
class ReactiveHealthComponent extends HealthComponent with ReactiveComponent {
  ReactiveHealthComponent({
    super.health,
    required super.maxHealth,
    super.isInvulnerable,
  });

  @override
  set health(double value) {
    if (super.health != value) {
      super.health = value;
      notifyChange('health');
    }
  }

  @override
  set maxHealth(double value) {
    if (super.maxHealth != value) {
      super.maxHealth = value;
      notifyChange('maxHealth');
    }
  }

  @override
  set isInvulnerable(bool value) {
    if (super.isInvulnerable != value) {
      super.isInvulnerable = value;
      notifyChange('isInvulnerable');
    }
  }

  @override
  void damage(double amount) {
    super.damage(amount);
    notifyChange('health');
  }

  @override
  void heal(double amount) {
    super.heal(amount);
    notifyChange('health');
  }
}
