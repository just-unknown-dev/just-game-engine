library;

import 'dart:ui';

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';
import '../ecs/components.dart';

/// A signal that wraps a component's property for reactive updates.
///
/// ComponentSignal provides change detection for ECS components,
/// enabling surgical UI updates when component data changes.
///
/// ```dart
/// final transform = entity.getComponent<TransformComponent>()!;
/// final positionX = ComponentSignal<TransformComponent, double>(
///   transform,
///   getter: (c) => c.position.dx,
///   setter: (c, v) => c.position = Offset(v, c.position.dy),
/// );
///
/// positionX.value = 100; // Updates component and notifies listeners
/// ```
class ComponentSignal<C extends Component, T> extends Signal<T> {
  ComponentSignal(
    this._component, {
    required T Function(C component) getter,
    required void Function(C component, T value) setter,
    String? debugLabel,
  }) : _getter = getter,
       _setter = setter,
       super(getter(_component), debugLabel: debugLabel);

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
/// Provides convenient reactive access to position, rotation, and scale.
class TransformSignals {
  TransformSignals(TransformComponent component)
    : x = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
        debugLabel: 'TransformSignals.x',
      ),
      y = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.position.dy,
        setter: (c, v) => c.position = Offset(c.position.dx, v),
        debugLabel: 'TransformSignals.y',
      ),
      rotation = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.rotation,
        setter: (c, v) => c.rotation = v,
        debugLabel: 'TransformSignals.rotation',
      ),
      scale = ComponentSignal<TransformComponent, double>(
        component,
        getter: (c) => c.scale,
        setter: (c, v) => c.scale = v,
        debugLabel: 'TransformSignals.scale',
      );

  final ComponentSignal<TransformComponent, double> x;
  final ComponentSignal<TransformComponent, double> y;
  final ComponentSignal<TransformComponent, double> rotation;
  final ComponentSignal<TransformComponent, double> scale;

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
    rotation.sync();
    scale.sync();
  }

  void dispose() {
    x.dispose();
    y.dispose();
    rotation.dispose();
    scale.dispose();
  }
}

/// A collection of signals for velocity component.
class VelocitySignals {
  VelocitySignals(VelocityComponent component)
    : vx = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.velocity.dx,
        setter: (c, v) => c.velocity = Offset(v, c.velocity.dy),
        debugLabel: 'VelocitySignals.vx',
      ),
      vy = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.velocity.dy,
        setter: (c, v) => c.velocity = Offset(c.velocity.dx, v),
        debugLabel: 'VelocitySignals.vy',
      ),
      maxSpeed = ComponentSignal<VelocityComponent, double>(
        component,
        getter: (c) => c.maxSpeed,
        setter: (c, v) => c.maxSpeed = v,
        debugLabel: 'VelocitySignals.maxSpeed',
      );

  final ComponentSignal<VelocityComponent, double> vx;
  final ComponentSignal<VelocityComponent, double> vy;
  final ComponentSignal<VelocityComponent, double> maxSpeed;

  void setVelocity(double vx, double vy) {
    batch(() {
      this.vx.value = vx;
      this.vy.value = vy;
    });
  }

  void syncAll() {
    vx.sync();
    vy.sync();
    maxSpeed.sync();
  }

  void dispose() {
    vx.dispose();
    vy.dispose();
    maxSpeed.dispose();
  }
}

/// A collection of signals for health component.
class HealthSignals {
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

  final ComponentSignal<HealthComponent, double> health;
  final ComponentSignal<HealthComponent, double> maxHealth;

  /// The health as a percentage (0.0 - 1.0).
  double get healthPercent {
    final max = maxHealth.value;
    return max > 0 ? health.value / max : 0;
  }

  void syncAll() {
    health.sync();
    maxHealth.sync();
  }

  void dispose() {
    health.dispose();
    maxHealth.dispose();
  }
}
