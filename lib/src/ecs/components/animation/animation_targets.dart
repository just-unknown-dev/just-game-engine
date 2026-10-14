/// What an animator graph plays its states on, beyond sprites.
library;

import '../../../subsystems/animation/animator/animator_graph.dart';
import '../../ecs.dart';
import 'animator_component.dart';

/// Something an `AnimatorSystem` plays a graph's states on: a 3-D model's
/// skeleton, or a kit's own kind of animation.
///
/// An entity with a `SpriteAnimationComponent` plays on its sprite, as it
/// always has. Any other entity with an [AnimatorComponent] plays on the
/// first registered target that [drives] it (`context.animationTargets`);
/// with none, its animator does nothing.
abstract class AnimationTarget {
  /// Const constructor so subclasses can be const.
  const AnimationTarget();

  /// Whether this target plays on [entity].
  bool drives(Entity entity);

  /// [entity] enters [state], blending from what it played over [fade]
  /// seconds where it can.
  void enter(Entity entity, AnimatorState state, {double fade = 0});

  /// Once per update while in [state], after the animator's parameters are
  /// filled: what a blend tree needs to weigh its motions.
  void update(
    Entity entity,
    AnimatorComponent animator,
    AnimatorState state,
    double deltaTime,
  ) {}

  /// How far through [state]'s clip [entity] is, 0–1; a looping clip
  /// counts on past 1, so an exit time is reached once and stays reached.
  double progress(Entity entity, AnimatorComponent animator, AnimatorState state);

  /// Whether [state]'s clip has played to its end and stopped.
  bool isComplete(Entity entity, AnimatorState state);
}

/// The [AnimationTarget]s of one engine context, tried in the order they
/// were registered. Register a package's own from its `ContextExtension`.
final class AnimationTargets {
  final List<AnimationTarget> _targets = [];

  /// Every target, in the order tried.
  List<AnimationTarget> get all => List.unmodifiable(_targets);

  /// Adds [target]; one of the same runtime type is replaced in place (so
  /// a hot reload's re-registration doesn't add a second).
  void register(AnimationTarget target) {
    final at = _targets.indexWhere((t) => t.runtimeType == target.runtimeType);
    if (at >= 0) {
      _targets[at] = target;
    } else {
      _targets.add(target);
    }
  }

  /// The first target that drives [entity], or null.
  AnimationTarget? targetFor(Entity entity) {
    for (final target in _targets) {
      if (target.drives(entity)) return target;
    }
    return null;
  }
}
