part of '../animation_system.dart';

/// Base class for all animations.
///
/// Implements [Recyclable] so completed animations can be returned to an
/// [ObjectPool] and reused without GC pressure.
abstract class Animation with Recyclable {
  /// Current time in the animation
  double currentTime = 0.0;

  /// Animation duration (non-final to allow pool reconfiguration).
  double duration;

  /// Whether animation loops (non-final to allow pool reconfiguration).
  bool loop;

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

  /// Reset all mutable state so the animation can be replayed or reused
  /// from an [ObjectPool].
  @override
  void reset() {
    currentTime = 0.0;
    speed = 1.0;
    isPaused = false;
    onComplete = null;
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
