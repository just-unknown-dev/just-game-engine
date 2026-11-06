/// What animators keep per engine: what their parameters can be bound to,
/// what they play on, and where their graphs come from.
library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show AnimatorGraph;

import '../ecs/engine_context.dart';
import 'animation_targets.dart';
import 'animator_bindings.dart';

/// Loads an animator graph by path.
typedef AnimatorGraphLoader = Future<AnimatorGraph> Function(String path);

/// The animation state of one [EngineContext]; read it through
/// [ContextAnimation].
final class AnimationContextState {
  AnimationContextState._(this._context)
    : bindings = AnimatorBindings(withBuiltIns: _context.withBuiltIns) {
    graphs = bundleLoader;
  }

  /// [context]'s state, made the first time it is asked for.
  static AnimationContextState of(EngineContext context) =>
      context.slot(_key, () => AnimationContextState._(context));

  static final Object _key = Object();

  final EngineContext _context;

  /// See [ContextAnimation.animatorBindings].
  final AnimatorBindings bindings;

  /// See [ContextAnimation.animationTargets].
  final AnimationTargets targets = AnimationTargets();

  /// See [ContextAnimation.animatorGraphs].
  late AnimatorGraphLoader graphs;

  /// Reads an animator graph from the context's bundle: the default
  /// [graphs].
  Future<AnimatorGraph> bundleLoader(String path) async =>
      AnimatorGraph.parse(await _context.bundle.loadString(path));
}

/// An engine's animation state, on its [EngineContext].
extension ContextAnimation on EngineContext {
  /// What an animator graph's parameters can be bound to.
  AnimatorBindings get animatorBindings =>
      AnimationContextState.of(this).bindings;

  /// What animator graphs play on besides sprites: a package registers its
  /// own (a 3-D model's skeleton) from its extension.
  AnimationTargets get animationTargets =>
      AnimationContextState.of(this).targets;

  /// Loads animator graphs for the `AnimatorSystem`. The bundle by default;
  /// an authoring tool points it at the project's files (`overrideLoaders`).
  AnimatorGraphLoader get animatorGraphs =>
      AnimationContextState.of(this).graphs;
  set animatorGraphs(AnimatorGraphLoader value) =>
      AnimationContextState.of(this).graphs = value;
}
