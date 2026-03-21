part of '../animation_system.dart';

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
