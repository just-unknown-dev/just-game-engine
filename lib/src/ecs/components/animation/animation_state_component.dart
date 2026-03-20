library;

import '../../ecs.dart';

/// Animation state component - Tracks current animation
class AnimationStateComponent extends Component {
  /// Current animation name
  String currentAnimation;

  /// Animation time
  double time = 0.0;

  /// Is animation playing
  bool isPlaying = true;

  /// Should loop
  bool loop;

  /// Total frames in this animation.
  int frameCount;

  /// Duration of each frame in seconds.
  double frameDuration;

  /// Create animation state component
  AnimationStateComponent({
    required this.currentAnimation,
    this.loop = true,
    this.frameCount = 1,
    this.frameDuration = 0.1,
  });

  /// The computed current frame index (0-based).
  int get currentFrame {
    if (frameCount <= 1) return 0;
    final totalDuration = frameCount * frameDuration;
    if (totalDuration <= 0) return 0;
    final t = loop ? time % totalDuration : time.clamp(0.0, totalDuration);
    return (t / frameDuration).floor().clamp(0, frameCount - 1);
  }

  /// Whether the animation has finished (only meaningful when [loop] is false).
  bool get isComplete => !loop && time >= frameCount * frameDuration;

  /// Play animation
  void play(
    String animation, {
    bool restart = false,
    int? frameCount,
    double? frameDuration,
  }) {
    if (currentAnimation != animation || restart) {
      currentAnimation = animation;
      time = 0.0;
      isPlaying = true;
      if (frameCount != null) this.frameCount = frameCount;
      if (frameDuration != null) this.frameDuration = frameDuration;
    }
  }

  /// Stop animation
  void stop() {
    isPlaying = false;
  }

  @override
  String toString() => 'AnimationState($currentAnimation, t: $time)';
}
