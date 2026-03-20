library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../rendering/impl/sprite.dart';
import '../rendering/impl/renderable.dart';
import '../../memory/object_pool.dart';

part 'base/animation_base.dart';
part 'impl/sprite_animation.dart';
part 'impl/tween_animation.dart';
part 'impl/animation_sequence.dart';
part 'impl/animation_group.dart';
part 'impl/easings.dart';

/// Main animation system class
class AnimationSystem {
  /// List of all active animations
  final List<Animation> _animations = [];

  /// Whether the animation system is initialized
  bool _initialized = false;

  /// Optional callback invoked for each completed (non-looping) animation.
  ///
  /// Use this to release finished tweens back to an [ObjectPool] for reuse,
  /// avoiding GC pressure in high-churn tween scenarios.
  ///
  /// ```dart
  /// final pool = ObjectPool<TweenAnimation<double>>(() => TweenAnimation(...));
  /// animSystem.onAnimationCompleted = (anim) {
  ///   if (anim is TweenAnimation<double>) pool.release(anim);
  /// };
  /// ```
  void Function(Animation completed)? onAnimationCompleted;

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

    // Update all animations, then compact completed ones in-place
    // (avoids the per-frame allocation that removeWhere can cause).
    int writeIndex = 0;
    for (int i = 0; i < _animations.length; i++) {
      final anim = _animations[i];
      anim.update(deltaTime);
      if (!anim.isComplete || anim.loop) {
        _animations[writeIndex++] = anim;
      } else {
        // Notify listener so completed tweens can be recycled via ObjectPool.
        onAnimationCompleted?.call(anim);
      }
    }
    _animations.length = writeIndex;
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
