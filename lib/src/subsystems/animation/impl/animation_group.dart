part of '../animation_system.dart';

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
