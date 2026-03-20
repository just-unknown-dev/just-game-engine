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

  /// Create animation state component
  AnimationStateComponent({required this.currentAnimation, this.loop = true});

  /// Play animation
  void play(String animation, {bool restart = false}) {
    if (currentAnimation != animation || restart) {
      currentAnimation = animation;
      time = 0.0;
      isPlaying = true;
    }
  }

  /// Stop animation
  void stop() {
    isPlaying = false;
  }

  @override
  String toString() => 'AnimationState($currentAnimation, t: $time)';
}
