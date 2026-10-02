library;

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';
import '../ecs/components/components.dart';
import 'package:just_dart/just_dart.dart';

/// A signal that wraps a component's property for reactive updates.
///
/// ComponentSignal provides change detection for ECS components,
/// enabling surgical UI updates when component data changes.
///
/// ```dart
/// final transform = entity.getComponent<TransformComponent>()!;
/// final positionX = ComponentSignal<TransformComponent, double>(
///   transform,
///   getter: (c) => c.position.x,
///   setter: (c, v) => c.position.x = v,
/// );
///
/// positionX.value = 100; // Updates component and notifies listeners
/// ```
class ComponentSignal<C extends Component, T> extends Signal<T> {
  /// A signal over one property of the given component: [getter] reads it
  /// (and gives the starting value), [setter] writes it when [value] is
  /// set to something different.
  ComponentSignal(
    this._component, {
    required T Function(C component) getter,
    required void Function(C component, T value) setter,
    super.debugLabel,
  }) : _getter = getter,
       _setter = setter,
       super(getter(_component));

  final C _component;
  final T Function(C component) _getter;
  final void Function(C component, T value) _setter;

  /// The component this signal wraps.
  C get component => _component;

  @override
  T get value {
    // Always read from component to stay in sync
    final currentValue = _getter(_component);
    super.setSilent(currentValue);
    return super.value;
  }

  @override
  set value(T newValue) {
    final oldValue = _getter(_component);
    if (oldValue != newValue) {
      _setter(_component, newValue);
      super.forceSet(newValue);
    }
  }

  /// Syncs the signal with the component's current value.
  ///
  /// Call this if the component was modified externally.
  void sync() {
    final currentValue = _getter(_component);
    if (super.value != currentValue) {
      super.forceSet(currentValue);
    }
  }
}

/// A collection of signals for all properties of a transform component.
///
/// Provides convenient reactive access to position, angle (the 2-D rotation), and scale.
class TransformSignals {
  /// Signals over [component]'s position x and y, angle and scale.
  TransformSignals(TransformComponent component)
    : x = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.position.x,
        setter: (c, v) => c.position.x = v,
        debugLabel: 'TransformSignals.x',
      ),
      y = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.position.y,
        setter: (c, v) => c.position.y = v,
        debugLabel: 'TransformSignals.y',
      ),
      angle = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.angle,
        setter: (c, v) => c.angle = v,
        debugLabel: 'TransformSignals.angle',
      ),
      scale = ComponentSignal<TransformComponent, Vector3>(
        component,
        getter: (c) => c.scale,
        setter: (c, v) => c.scale = v,
        debugLabel: 'TransformSignals.scale',
      );

  /// The position's x, in world units.
  final ComponentSignal<TransformComponent, double> x;

  /// The position's y, in world units.
  final ComponentSignal<TransformComponent, double> y;

  /// The rotation about Z, in radians.
  final ComponentSignal<TransformComponent, double> angle;

  /// The scale vector itself, not a copy: changing its parts in place
  /// notifies nobody; set a different vector to notify.
  final ComponentSignal<TransformComponent, Vector3> scale;

  /// Sets position in a batch (single notification).
  void setPosition(double x, double y) {
    batch(() {
      this.x.value = x;
      this.y.value = y;
    });
  }

  /// Translates position in a batch.
  void translate(double dx, double dy) {
    batch(() {
      x.value += dx;
      y.value += dy;
    });
  }

  /// Syncs all signals with component values.
  void syncAll() {
    x.sync();
    y.sync();
    angle.sync();
    scale.sync();
  }

  /// Disposes all four signals; the component is left as it is.
  void dispose() {
    x.dispose();
    y.dispose();
    angle.dispose();
    scale.dispose();
  }
}

/// A collection of signals for velocity component.
class VelocitySignals {
  /// Signals over [component]'s velocity x and y and its max speed.
  VelocitySignals(VelocityComponent component)
    : vx = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.velocity.x,
        setter: (c, v) => c.velocity.x = v,
        debugLabel: 'VelocitySignals.vx',
      ),
      vy = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.velocity.y,
        setter: (c, v) => c.velocity.y = v,
        debugLabel: 'VelocitySignals.vy',
      ),
      maxSpeed = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.maxSpeed,
        setter: (c, v) => c.maxSpeed = v,
        debugLabel: 'VelocitySignals.maxSpeed',
      );

  /// The velocity's x.
  final ComponentSignal<VelocityComponent, double> vx;

  /// The velocity's y.
  final ComponentSignal<VelocityComponent, double> vy;

  /// The component's `maxSpeed`.
  final ComponentSignal<VelocityComponent, double> maxSpeed;

  /// Sets both parts of the velocity in a batch (single notification).
  void setVelocity(double vx, double vy) {
    batch(() {
      this.vx.value = vx;
      this.vy.value = vy;
    });
  }

  /// Syncs all signals with component values.
  void syncAll() {
    vx.sync();
    vy.sync();
    maxSpeed.sync();
  }

  /// Disposes all three signals; the component is left as it is.
  void dispose() {
    vx.dispose();
    vy.dispose();
    maxSpeed.dispose();
  }
}

/// A collection of signals for health component.
class HealthSignals {
  /// Signals over [component]'s health and max health.
  HealthSignals(HealthComponent component)
    : health = ComponentSignal<HealthComponent, double>(
        component,
        getter: (c) => c.health,
        setter: (c, v) => c.health = v,
        debugLabel: 'HealthSignals.health',
      ),
      maxHealth = ComponentSignal<HealthComponent, double>(
        component,
        getter: (c) => c.maxHealth,
        setter: (c, v) => c.maxHealth = v,
        debugLabel: 'HealthSignals.maxHealth',
      );

  /// The current health.
  final ComponentSignal<HealthComponent, double> health;

  /// The maximum health.
  final ComponentSignal<HealthComponent, double> maxHealth;

  /// The health as a percentage (0.0 - 1.0).
  double get healthPercent {
    final max = maxHealth.value;
    return max > 0 ? health.value / max : 0;
  }

  /// Syncs both signals with component values.
  void syncAll() {
    health.sync();
    maxHealth.sync();
  }

  /// Disposes both signals; the component is left as it is.
  void dispose() {
    health.dispose();
    maxHealth.dispose();
  }
}
