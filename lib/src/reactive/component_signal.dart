library;

import 'package:just_signals/just_signals.dart';

import '../ecs/ecs.dart';
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
