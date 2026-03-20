/// Animation System
///
/// Manages character and object animations including sprite animations and tweening.
/// This module provides animation playback and blending capabilities.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../rendering/sprite.dart';
import '../rendering/renderable.dart';

/// Main animation system class
class AnimationSystem {
  /// List of all active animations
  final List<Animation> _animations = [];

  /// Whether the animation system is initialized
  bool _initialized = false;

  /// Get all animations
  List<Animation> get animations => List.unmodifiable(_animations);

  /// Initialize the animation system
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    debugPrint('Animation System initialized');
  }

  /// Update all animations
  void update(double deltaTime) {
    if (!_initialized) return;

    // Update and remove completed animations
    _animations.removeWhere((anim) {
      anim.update(deltaTime);
      return anim.isComplete && !anim.loop;
    });
  }

  /// Register an animation
  void addAnimation(Animation animation) {
    if (!_animations.contains(animation)) {
      _animations.add(animation);
    }
  }

  /// Remove an animation
  void removeAnimation(Animation animation) {
    _animations.remove(animation);
  }

  /// Clear all animations
  void clear() {
    _animations.clear();
  }

  /// Clean up animation resources
  void dispose() {
    clear();
    _initialized = false;
    debugPrint('Animation System disposed');
  }

  /// Get the number of active animations
  int get animationCount => _animations.length;
}

/// Base class for all animations
abstract class Animation {
  /// Current time in the animation
  double currentTime = 0.0;

  /// Animation duration
  final double duration;

  /// Whether animation loops
  final bool loop;

  /// Animation speed multiplier
  double speed = 1.0;

  /// Whether animation is paused
  bool isPaused = false;

  /// Callback when animation completes
  VoidCallback? onComplete;

  /// Create an animation
  Animation({required this.duration, this.loop = false, this.onComplete});

  /// Update the animation
  void update(double deltaTime) {
    if (isPaused || isComplete) return;

    currentTime += deltaTime * speed;

    if (currentTime >= duration) {
      if (loop) {
        currentTime = currentTime % duration;
      } else {
        currentTime = duration;
        onComplete?.call();
      }
    }

    updateAnimation(deltaTime);
  }

  /// Override this to implement animation logic
  void updateAnimation(double deltaTime);

  /// Get normalized time (0.0 to 1.0)
  double get normalizedTime => (currentTime / duration).clamp(0.0, 1.0);

  /// Check if animation is complete
  bool get isComplete => currentTime >= duration && !loop;

  /// Reset the animation
  void reset() {
    currentTime = 0.0;
  }

  /// Play the animation
  void play() {
    isPaused = false;
  }

  /// Pause the animation
  void pause() {
    isPaused = true;
  }

  /// Stop and reset
  void stop() {
    isPaused = true;
    reset();
  }
}

/// Sprite animation for frame-based animations
class SpriteAnimation extends Animation {
  /// The sprite to animate
  final Sprite sprite;

  /// List of frame rectangles from sprite sheet
  final List<Rect> frames;

  /// Current frame index
  int currentFrame = 0;

  /// Create a sprite animation
  SpriteAnimation({
    required this.sprite,
    required this.frames,
    required super.duration,
    super.loop = true,
    super.onComplete,
  });

  @override
  void updateAnimation(double deltaTime) {
    // Calculate current frame
    final frameIndex = (normalizedTime * frames.length).floor();
    currentFrame = frameIndex.clamp(0, frames.length - 1);

    // Update sprite source rect
    sprite.sourceRect = frames[currentFrame];
  }

  /// Create from sprite sheet
  static SpriteAnimation fromSpriteSheet({
    required Sprite sprite,
    required int frameCount,
    required int frameWidth,
    required int frameHeight,
    required double duration,
    int startFrame = 0,
    bool loop = true,
  }) {
    final frames = <Rect>[];
    for (int i = 0; i < frameCount; i++) {
      final x = ((startFrame + i) * frameWidth) % sprite.image!.width;
      final y =
          ((startFrame + i) * frameWidth ~/ sprite.image!.width) * frameHeight;
      frames.add(
        Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          frameWidth.toDouble(),
          frameHeight.toDouble(),
        ),
      );
    }

    return SpriteAnimation(
      sprite: sprite,
      frames: frames,
      duration: duration,
      loop: loop,
    );
  }
}

/// Tween animation for interpolating values
class TweenAnimation<T> extends Animation {
  /// Start value
  final T start;

  /// End value
  final T end;

  /// Easing function
  final Easing easing;

  /// Callback with current value
  final void Function(T value) onUpdate;

  /// Interpolation function
  final T Function(T start, T end, double t) lerp;

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

/// Sequence of animations
class AnimationSequence extends Animation {
  /// List of animations in sequence
  final List<Animation> animations;

  /// Current animation index
  int currentIndex = 0;

  /// Create an animation sequence
  AnimationSequence({required this.animations, super.loop, super.onComplete})
    : super(duration: animations.fold(0.0, (sum, anim) => sum + anim.duration));

  @override
  void updateAnimation(double deltaTime) {
    if (currentIndex >= animations.length) return;

    final currentAnim = animations[currentIndex];
    currentAnim.update(deltaTime);

    if (currentAnim.isComplete) {
      currentIndex++;
      if (currentIndex >= animations.length && loop) {
        reset();
      }
    }
  }

  @override
  void reset() {
    super.reset();
    currentIndex = 0;
    for (final anim in animations) {
      anim.reset();
    }
  }
}

/// Parallel animations
class AnimationGroup extends Animation {
  /// List of animations to run in parallel
  final List<Animation> animations;

  /// Create an animation group
  AnimationGroup({required this.animations, super.loop, super.onComplete})
    : super(
        duration: animations.fold(
          0.0,
          (max, anim) => math.max(max, anim.duration),
        ),
      );

  @override
  void updateAnimation(double deltaTime) {
    for (final anim in animations) {
      if (!anim.isComplete) {
        anim.update(deltaTime);
      }
    }
  }

  @override
  void reset() {
    super.reset();
    for (final anim in animations) {
      anim.reset();
    }
  }
}

/// Easing functions for smooth animations
typedef Easing = double Function(double t);

/// Common easing functions
class Easings {
  // Linear
  static double linear(double t) => t;

  // Quadratic
  static double easeInQuad(double t) => t * t;
  static double easeOutQuad(double t) => t * (2 - t);
  static double easeInOutQuad(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  // Cubic
  static double easeInCubic(double t) => t * t * t;
  static double easeOutCubic(double t) => (--t) * t * t + 1;
  static double easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
  }

  // Quartic
  static double easeInQuart(double t) => t * t * t * t;
  static double easeOutQuart(double t) => 1 - (--t) * t * t * t;
  static double easeInOutQuart(double t) {
    return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
  }

  // Sine
  static double easeInSine(double t) => 1 - math.cos(t * math.pi / 2);
  static double easeOutSine(double t) => math.sin(t * math.pi / 2);
  static double easeInOutSine(double t) => -(math.cos(math.pi * t) - 1) / 2;

  // Exponential
  static double easeInExpo(double t) {
    return t == 0 ? 0 : math.pow(2, 10 * t - 10).toDouble();
  }

  static double easeOutExpo(double t) {
    return t == 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble();
  }

  static double easeInOutExpo(double t) {
    if (t == 0 || t == 1) return t;
    return t < 0.5
        ? math.pow(2, 20 * t - 10).toDouble() / 2
        : (2 - math.pow(2, -20 * t + 10).toDouble()) / 2;
  }

  // Elastic
  static double easeInElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    return t == 0
        ? 0
        : t == 1
        ? 1
        : -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4);
  }

  static double easeOutElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    return t == 0
        ? 0
        : t == 1
        ? 1
        : math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
  }

  // Bounce
  static double easeOutBounce(double t) {
    const n1 = 7.5625;
    const d1 = 2.75;

    if (t < 1 / d1) {
      return n1 * t * t;
    } else if (t < 2 / d1) {
      return n1 * (t -= 1.5 / d1) * t + 0.75;
    } else if (t < 2.5 / d1) {
      return n1 * (t -= 2.25 / d1) * t + 0.9375;
    } else {
      return n1 * (t -= 2.625 / d1) * t + 0.984375;
    }
  }

  static double easeInBounce(double t) {
    return 1 - easeOutBounce(1 - t);
  }
}

// Export common easings
final Easing linear = Easings.linear;
final Easing easeInQuad = Easings.easeInQuad;
final Easing easeOutQuad = Easings.easeOutQuad;
final Easing easeInOutQuad = Easings.easeInOutQuad;
final Easing easeInCubic = Easings.easeInCubic;
final Easing easeOutCubic = Easings.easeOutCubic;
final Easing easeInOutCubic = Easings.easeInOutCubic;
