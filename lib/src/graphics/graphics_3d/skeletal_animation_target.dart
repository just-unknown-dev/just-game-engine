import '../../ecs/ecs.dart';
import '../../animation/animation.dart';
import 'model_components.dart';

/// Plays an animator graph's states on a 3-D model's skeleton: an entity
/// with an [AnimatorComponent], a [ModelComponent] and an
/// [AnimationPlayerComponent] (which it drives). A transition's duration
/// crossfades; a blend tree blends its motions, weighted by the graph's
/// parameters every update. It sets what the player plays at run time
/// (`playingClip`, `playingSpeed`, `playingLoop`), never what it saves.
///
/// `Graphics3D` registers it (`context.animationTargets`).
final class SkeletalAnimationTarget extends AnimationTarget {
  /// The one target; it keeps no state.
  const SkeletalAnimationTarget();

  @override
  bool drives(Entity entity) =>
      entity.hasComponent<AnimationPlayerComponent>() &&
      entity.hasComponent<ModelComponent>();

  @override
  void enter(Entity entity, AnimatorState state, {double fade = 0}) {
    final player = entity.getComponent<AnimationPlayerComponent>()!;
    final tree = state.blend;
    if (tree == null || tree.motions.isEmpty) {
      player.play(state.clipName, fade: fade, restart: true);
    } else {
      // Weights come with the first update; until then the first motion.
      player.playBlend(
        [for (final m in tree.motions) m.clip],
        [for (var i = 0; i < tree.motions.length; i++) i == 0 ? 1.0 : 0.0],
        speeds: [for (final m in tree.motions) m.speed],
        fade: fade,
      );
    }
    // Set after playing, so what fades out keeps its own speed and looping.
    player
      ..playingSpeed = state.speed
      ..playingLoop = state.loop ?? true;
  }

  @override
  void release(Entity entity) =>
      entity.getComponent<AnimationPlayerComponent>()?.release(fade: 0);

  @override
  void update(
    Entity entity,
    AnimatorComponent animator,
    AnimatorState state,
    double deltaTime,
  ) {
    final tree = state.blend;
    if (tree == null) return;
    final x = AnimatorParameter.asNumber(animator.parameters[tree.parameter]);
    final y = AnimatorParameter.asNumber(animator.parameters[tree.parameterY]);
    entity.getComponent<AnimationPlayerComponent>()!.setBlendWeights(
      tree.weights(x, y),
    );
  }

  /// Cycles played, the way it plays: a clip played backwards goes from 0
  /// at its end to 1 at its start.
  @override
  double progress(
    Entity entity,
    AnimatorComponent animator,
    AnimatorState state,
  ) {
    final p = entity.getComponent<AnimationPlayerComponent>()!;
    if (p.startPending) return 0;
    final backwards = p.playingSpeed < 0;
    if (p.isBlending) return p.cycles + (backwards ? 1 - p.phase : p.phase);
    if (p.duration <= 0) return 0;
    final done = backwards ? p.duration - p.time : p.time;
    return p.cycles + done / p.duration;
  }

  /// Whether a clip that does not loop has reached its end — its start,
  /// played backwards.
  @override
  bool isComplete(Entity entity, AnimatorState state) {
    final p = entity.getComponent<AnimationPlayerComponent>()!;
    if (p.playingLoop || p.duration <= 0 || p.startPending) return false;
    if (p.playingSpeed < 0) return p.isBlending ? p.phase <= 0 : p.time <= 0;
    return p.isBlending ? p.phase >= 1 : p.time >= p.duration;
  }
}
