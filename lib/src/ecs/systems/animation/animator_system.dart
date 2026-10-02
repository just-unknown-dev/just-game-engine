library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../subsystems/animation/animator/animator_graph.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../rendering/sprite_systems.dart';
import '../../base/system_priorities.dart';

/// A state change, for whoever wants to react: sound, particles, a debugger.
class AnimatorStateChange {
  /// [entity]'s animator leaving the state [from] for [to].
  const AnimatorStateChange(this.entity, this.from, this.to);

  /// The entity whose animator changed state.
  final Entity entity;

  /// The state left; empty when the animator has just started and is
  /// entering its graph's entry state.
  final String from;

  /// The state entered. May equal [from]: a transition back into the same
  /// state restarts it.
  final String to;
}

class _Running {
  _Running(this.path);

  final String path;
  AnimatorGraph? graph;

  /// The frame this animator last ran in.
  int seenAt = 0;
}

/// Runs every [AnimatorComponent]: fills its bound parameters, takes the
/// transition that should fire, and tells the entity's
/// [SpriteAnimationComponent] which clip to play.
class AnimatorSystem extends System {
  /// A system that reads each graph with [loader] — the world context's
  /// `animatorGraphs` when null — once per path, shared by every animator
  /// that names it.
  AnimatorSystem({Future<AnimatorGraph> Function(String path)? loader})
    : _loader = loader;

  final Future<AnimatorGraph> Function(String path)? _loader;
  final Map<String, Future<AnimatorGraph>> _graphs = {};
  final Map<Entity, _Running> _running = {};

  // Paths whose failure to load has been said.
  final Set<String> _reported = {};

  int _frame = 0;

  // Found once a frame, the first time an exit time needs it.
  SpriteAnimationSystem? _sprites;
  bool _spritesLooked = false;
  final StreamController<AnimatorStateChange> _changes =
      StreamController<AnimatorStateChange>.broadcast(sync: true);

  /// Below this horizontal speed the sprite keeps facing the way it was.
  static const double facingDeadZone = 1.0;

  /// Every state an animator enters, its first included. Broadcast and
  /// synchronous: a listener runs inside [update], as the state changes.
  Stream<AnimatorStateChange> get stateChanges => _changes.stream;

  // Before SpriteAnimationSystem, so a clip chosen this frame plays this
  // frame.
  @override
  int get priority => SystemPriorities.animation;

  @override
  List<Type> get requiredComponents => [
    AnimatorComponent,
    SpriteAnimationComponent,
  ];

  /// The graph [entity] is running, once loaded.
  AnimatorGraph? graphOf(Entity entity) => _running[entity]?.graph;

  /// Reads [graphPath] again — it changed on disk. Animators running it
  /// start over from its entry. Without a path, every graph.
  void reload([String? graphPath]) {
    if (graphPath == null) {
      _graphs.clear();
    } else {
      _graphs.remove(graphPath);
    }
    _running.removeWhere((entity, r) {
      if (graphPath != null && r.path != graphPath) return false;
      entity.getComponent<AnimatorComponent>()?.restart();
      return true;
    });
  }

  @override
  void update(double deltaTime) {
    final frame = ++_frame;
    _spritesLooked = false;
    var seen = 0;

    forEach((entity) {
      final animator = entity.getComponent<AnimatorComponent>()!;
      final path = animator.graphPath.trim();
      var running = _running[entity];
      if (running == null || running.path != path) {
        running = _running[entity] = _Running(path);
        animator.restart();
        if (path.isNotEmpty) _load(entity, running);
      }
      running.seenAt = frame;
      seen++;
      final graph = running.graph;
      if (graph == null || !animator.enabled) return;
      final sprite = entity.getComponent<SpriteAnimationComponent>()!;

      if (animator.faceVelocity) {
        final vx = entity.getComponent<VelocityComponent>()?.velocity.x ?? 0;
        if (vx.abs() > facingDeadZone) sprite.flipX = vx < 0;
      }

      for (final p in graph.parameters) {
        animator.parameters.putIfAbsent(p.name, () => p.initialValue);
        final read = p.binding == null
            ? null
            : world.context.animatorBindings.of(p.binding!);
        final value = read?.call(entity);
        if (value != null) animator.parameters[p.name] = value;
      }

      if (graph.stateNamed(animator.currentState) == null) {
        final entry = graph.entryState;
        if (entry == null) return;
        _enter(entity, animator, sprite, entry);
        return;
      }
      animator.stateTime += deltaTime;

      final next = _transitionToTake(entity, graph, animator, sprite);
      if (next == null) return;
      for (final c in next.conditions) {
        if (graph.parameterNamed(c.parameter)?.type ==
            AnimatorParameterType.trigger) {
          animator.parameters[c.parameter] = false;
        }
      }
      _enter(entity, animator, sprite, graph.stateNamed(next.to)!);
    });

    // An animator not run this frame — its entity destroyed, switched off
    // or without the components — is forgotten, and starts again from its
    // entry when it next runs.
    if (_running.length > seen) {
      _running.removeWhere((_, running) => running.seenAt != frame);
    }
  }

  Future<void> _load(Entity entity, _Running running) async {
    try {
      final graph = await (_graphs[running.path] ??=
          (_loader ?? world.context.animatorGraphs)(running.path));
      if (_running[entity] == running) running.graph = graph;
    } catch (error) {
      // Not tried again for this animator; said once per file.
      _graphs.remove(running.path);
      if (_reported.add(running.path)) {
        debugPrint(
          'AnimatorSystem: "${running.path}" could not be loaded; animators '
          'using it stay still. $error',
        );
      }
    }
  }

  /// The first transition that may fire: those from Any State, then those
  /// from the current state, each group by priority.
  AnimatorTransition? _transitionToTake(
    Entity entity,
    AnimatorGraph graph,
    AnimatorComponent animator,
    SpriteAnimationComponent sprite,
  ) {
    // Any State first, then this state's own; within each, the highest
    // priority, and the one listed first among equals.
    final candidates = graph.transitionsFrom(animator.currentState);

    double? progress;
    for (final t in candidates) {
      if (t.hasExitTime) {
        // A state that plays a timeline is done when the timeline is.
        final player =
            (graph.stateNamed(animator.currentState)?.timeline ?? '').isEmpty
            ? null
            : entity.getComponent<TimelinePlayerComponent>();
        progress ??= player?.progress ?? _progress(entity, sprite);
        final done = player?.isFinished ?? sprite.isComplete;
        if (progress < t.exitTime && !done) continue;
      }
      var holds = true;
      for (final c in t.conditions) {
        final type = graph.parameterNamed(c.parameter)?.type;
        if (type == null || !c.holds(animator.parameters[c.parameter], type)) {
          holds = false;
          break;
        }
      }
      if (holds) return t;
    }
    return null;
  }

  /// How far through its clip [sprite] is, 0–1. A looping clip counts up
  /// past its first pass, so an exit time is reached once and stays reached.
  double _progress(Entity entity, SpriteAnimationComponent sprite) {
    if (sprite.isComplete) return 1.0;
    if (!_spritesLooked) {
      _spritesLooked = true;
      _sprites = world.getSystem<SpriteAnimationSystem>();
    }
    final system = _sprites;
    if (system == null) return 0.0;
    final atlas = system.atlasOf(entity);
    if (atlas == null) return 0.0;
    final total = system.clipOf(atlas, sprite).totalDuration;
    if (total <= 0) return 1.0;
    final animator = entity.getComponent<AnimatorComponent>()!;
    final played = animator.stateTime * sprite.speed;
    return played / total;
  }

  void _enter(
    Entity entity,
    AnimatorComponent animator,
    SpriteAnimationComponent sprite,
    AnimatorState state,
  ) {
    final from = animator.currentState;
    animator
      ..previousState = from
      ..currentState = state.name
      ..stateTime = 0.0;
    sprite
      ..speed = state.speed
      ..switchClip(state.clipName, restartIfSame: true, loop: state.loop);
    if (state.timeline.isNotEmpty) {
      entity.getComponent<TimelinePlayerComponent>()?.playTimeline(
        state.timeline,
      );
    }
    _changes.add(AnimatorStateChange(entity, from, state.name));
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}
