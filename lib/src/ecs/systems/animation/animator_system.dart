library;

import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../../../subsystems/animation/animator/animator_graph.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../rendering/sprite_systems.dart';
import '../system_priorities.dart';

/// Reads an entity's own state into an animator parameter, every frame.
/// Returns a `num` or a `bool`, or null to leave the parameter alone.
typedef AnimatorBinding = Object? Function(Entity entity);

/// The sources a graph's parameter can be bound to, by id.
///
/// The engine registers the ones below; a kit adds its own — a platformer's
/// `grounded` — so a graph can use them without the game writing glue.
abstract final class AnimatorBindings {
  static final Map<String, AnimatorBinding> _sources = {
    'velocityX': (e) => e.getComponent<VelocityComponent>()?.velocity.x,
    'velocityY': (e) => e.getComponent<VelocityComponent>()?.velocity.y,
    'speed': (e) => e.getComponent<VelocityComponent>()?.speed,
    'speedX': (e) => e.getComponent<VelocityComponent>()?.velocity.x.abs(),
    'speedY': (e) => e.getComponent<VelocityComponent>()?.velocity.y.abs(),
    'health': (e) => e.getComponent<HealthComponent>()?.health,
    'healthFraction': (e) {
      final h = e.getComponent<HealthComponent>();
      if (h == null) return null;
      return h.maxHealth <= 0 ? 0.0 : h.health / h.maxHealth;
    },
    'alive': (e) {
      final h = e.getComponent<HealthComponent>();
      return h == null ? null : h.health > 0;
    },
  };

  /// Adds (or replaces) the source called [id].
  static void register(String id, AnimatorBinding read) => _sources[id] = read;

  static void unregister(String id) => _sources.remove(id);

  static AnimatorBinding? of(String id) => _sources[id];

  /// Every id, for an editor's dropdown.
  static List<String> get ids => _sources.keys.toList()..sort();
}

/// Where animator graphs come from; a tool replaces [loader] to read the
/// project's files instead of the asset bundle.
abstract final class AnimatorAssets {
  static Future<AnimatorGraph> Function(String path) loader = _fromBundle;

  static Future<AnimatorGraph> _fromBundle(String path) async =>
      AnimatorGraph.parse(await rootBundle.loadString(path));

  /// Restores the bundle loader.
  static void useBundle() => loader = _fromBundle;
}

/// A state change, for whoever wants to react: sound, particles, a debugger.
class AnimatorStateChange {
  const AnimatorStateChange(this.entity, this.from, this.to);

  final Entity entity;
  final String from;
  final String to;
}

class _Running {
  _Running(this.path);

  final String path;
  AnimatorGraph? graph;
}

/// Runs every [AnimatorComponent]: fills its bound parameters, takes the
/// transition that should fire, and tells the entity's
/// [SpriteAnimationComponent] which clip to play.
class AnimatorSystem extends System {
  AnimatorSystem({Future<AnimatorGraph> Function(String path)? loader})
    : _loader = loader;

  final Future<AnimatorGraph> Function(String path)? _loader;
  final Map<String, Future<AnimatorGraph>> _graphs = {};
  final Map<Entity, _Running> _running = {};
  final StreamController<AnimatorStateChange> _changes =
      StreamController<AnimatorStateChange>.broadcast(sync: true);

  /// Below this horizontal speed the sprite keeps facing the way it was.
  static const double facingDeadZone = 1.0;

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
    final live = entities.toSet();
    _running.removeWhere((e, _) => !live.contains(e));

    forEach((entity) {
      final animator = entity.getComponent<AnimatorComponent>()!;
      final path = animator.graphPath.trim();
      var running = _running[entity];
      if (running == null || running.path != path) {
        running = _running[entity] = _Running(path);
        animator.restart();
        if (path.isNotEmpty) _load(entity, running);
      }
      final graph = running.graph;
      if (graph == null || !animator.enabled) return;
      final sprite = entity.getComponent<SpriteAnimationComponent>()!;

      if (animator.faceVelocity) {
        final vx = entity.getComponent<VelocityComponent>()?.velocity.x ?? 0;
        if (vx.abs() > facingDeadZone) sprite.flipX = vx < 0;
      }

      for (final p in graph.parameters) {
        animator.parameters.putIfAbsent(p.name, () => p.initialValue);
        final read = p.binding == null ? null : AnimatorBindings.of(p.binding!);
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
  }

  Future<void> _load(Entity entity, _Running running) async {
    try {
      final graph = await (_graphs[running.path] ??=
          (_loader ?? AnimatorAssets.loader)(running.path));
      if (_running[entity] == running) running.graph = graph;
    } catch (_) {
      _graphs.remove(running.path);
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
    final current = animator.currentState;
    // Any State first, then this state's own; within each, the highest
    // priority, and the one listed first among equals.
    final all = graph.transitions;
    int rank(int i) => all[i].isFromAny ? 0 : 1;
    final order =
        [
          for (var i = 0; i < all.length; i++)
            if (graph.stateNamed(all[i].to) != null &&
                (all[i].isFromAny
                    ? all[i].to != current
                    : all[i].from == current))
              i,
        ]..sort((a, b) {
          if (rank(a) != rank(b)) return rank(a) - rank(b);
          final byPriority = all[b].priority.compareTo(all[a].priority);
          return byPriority != 0 ? byPriority : a - b;
        });
    final candidates = [for (final i in order) all[i]];

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
    for (final system in world.systems) {
      if (system is! SpriteAnimationSystem) continue;
      final atlas = system.atlasOf(entity);
      if (atlas == null) return 0.0;
      final total = system.clipOf(atlas, sprite).totalDuration;
      if (total <= 0) return 1.0;
      final animator = entity.getComponent<AnimatorComponent>()!;
      final played = animator.stateTime * sprite.speed;
      return played / total;
    }
    return 0.0;
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
