library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Animation system — advances animation time and updates sprite frames.
///
/// Entities with [AnimationStateComponent] have their `time` advanced each
/// tick.  If the entity also carries a [SpriteComponent], the system writes
/// the computed `currentFrame` into `SpriteComponent.frame` so the renderer
/// picks up the correct sprite-sheet cell.
class AnimationSystemECS extends System {
  @override
  int get priority => SystemPriorities.animation;
  @override
  List<Type> get requiredComponents => [AnimationStateComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final anim = entity.getComponent<AnimationStateComponent>()!;
      if (!anim.isPlaying) return;

      anim.time += deltaTime;

      // Stop non-looping animations that have finished.
      if (anim.isComplete) {
        anim.isPlaying = false;
        return;
      }

      // Drive SpriteComponent frame when present.
      final sprite = entity.getComponent<SpriteComponent>();
      if (sprite != null) {
        sprite.frame = anim.currentFrame;
      }
    });
  }
}
