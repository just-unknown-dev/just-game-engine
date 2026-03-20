part of '../animation_system.dart';

/// Tween animation for interpolating values.
///
/// Fields are non-final so instances can be reconfigured after being
/// acquired from an [ObjectPool], avoiding per-tween allocation overhead.
class TweenAnimation<T> extends Animation {
  /// Start value
  T start;

  /// End value
  T end;

  /// Easing function
  Easing easing;

  /// Callback with current value
  void Function(T value) onUpdate;

  /// Interpolation function
  T Function(T start, T end, double t) lerp;

  /// Create a tween animation
  TweenAnimation({
    required this.start,
    required this.end,
    required this.lerp,
    required this.onUpdate,
    required super.duration,
    this.easing = Easings.linear,
    super.loop,
    super.onComplete,
  });

  @override
  void updateAnimation(double deltaTime) {
    final t = easing(normalizedTime);
    final value = lerp(start, end, t);
    onUpdate(value);
  }
}

/// Position tween for moving objects
class PositionTween extends TweenAnimation<Offset> {
  PositionTween({
    required super.start,
    required super.end,
    required Renderable target,
    required super.duration,
    super.easing = Easings.linear,
    super.loop = false,
    super.onComplete,
  }) : super(
         lerp: (a, b, t) => Offset.lerp(a, b, t)!,
         onUpdate: (value) => target.position = value,
       );
}

/// Rotation tween for rotating objects
class RotationTween extends TweenAnimation<double> {
  RotationTween({
    required super.start,
    required super.end,
    required Renderable target,
    required super.duration,
    super.easing = Easings.linear,
    super.loop = false,
    super.onComplete,
  }) : super(
         lerp: (a, b, t) => a + (b - a) * t,
         onUpdate: (value) => target.rotation = value,
       );
}

/// Scale tween for scaling objects
class ScaleTween extends TweenAnimation<double> {
  ScaleTween({
    required super.start,
    required super.end,
    required Renderable target,
    required super.duration,
    super.easing,
    super.loop,
    super.onComplete,
  }) : super(
         lerp: (a, b, t) => a + (b - a) * t,
         onUpdate: (value) => target.scale = value,
       );
}

/// Opacity tween for fading objects
class OpacityTween extends TweenAnimation<double> {
  OpacityTween({
    required super.start,
    required super.end,
    required Renderable target,
    required super.duration,
    super.easing,
    super.loop,
    super.onComplete,
  }) : super(
         lerp: (a, b, t) => a + (b - a) * t,
         onUpdate: (value) => target.opacity = value,
       );
}

/// Color tween for color transitions
class ColorTween extends TweenAnimation<Color> {
  ColorTween({
    required super.start,
    required super.end,
    required super.onUpdate,
    required super.duration,
    super.easing,
    super.loop,
    super.onComplete,
  }) : super(lerp: (a, b, t) => Color.lerp(a, b, t)!);
}
