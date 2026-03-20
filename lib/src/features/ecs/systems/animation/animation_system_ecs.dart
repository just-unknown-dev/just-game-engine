library;

import '../../ecs.dart';
import '../../components/components.dart';

/// Animation system - Updates animation state
class AnimationSystemECS extends System {
  @override
  List<Type> get requiredComponents => [AnimationStateComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final anim = entity.getComponent<AnimationStateComponent>()!;

      if (anim.isPlaying) {
        anim.time += deltaTime;
        // Loop logic would go here based on animation data
      }
    });
  }
}
