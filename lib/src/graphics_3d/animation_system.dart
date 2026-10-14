import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/renderer.dart';

import 'graphics_components.dart';
import 'graphics_models.dart';

/// Poses to blend through while sampling a player: one set per model.
final class PlayerScratch {
  /// Scratch for a model of [nodeCount] nodes.
  PlayerScratch(int nodeCount) : a = Pose(nodeCount), b = Pose(nodeCount);

  /// Each clip of a blend is sampled into this.
  final Pose a;

  /// What fades out is built here.
  final Pose b;
}

/// Writes into [pose] what [player] shows, [alpha] of the way from its
/// previous update to its latest: its clip or blend, blended with what is
/// fading out. Nodes no clip moves keep [model]'s rest pose.
void samplePlayer(
  AnimationPlayerComponent player,
  GpuModel model,
  Pose pose,
  PlayerScratch scratch, {
  double alpha = 1,
}) {
  if (player.isBlending) {
    final phase = _blendPhaseAt(player, alpha);
    _sampleMix(
      model,
      player.blendClips,
      player.blendWeights,
      phase,
      pose,
      scratch.a,
    );
  } else {
    pose.setRest(model.data);
    final clip = model.clips[player.clip];
    if (clip != null) clip.sample(_timeAt(player, clip.duration, alpha), pose);
  }
  if (!player.isFading) return;
  final from = scratch.b;
  if (player.fadingFromBlend.isNotEmpty) {
    _sampleMix(
      model,
      player.fadingFromBlend,
      player.fadingFromWeights,
      player.fadingFromPhase,
      from,
      scratch.a,
    );
  } else {
    from.setRest(model.data);
    final clip = model.clips[player.fadingFrom];
    if (clip == null) return;
    clip.sample(player.fadingFromTime, from);
  }
  pose.blend(from, pose, player.fade);
}

/// [clips] weighted by [weights], each at [phase] of its own length, into
/// [out]; [temp] holds each clip while it is folded in.
void _sampleMix(
  GpuModel model,
  List<String> clips,
  List<double> weights,
  double phase,
  Pose out,
  Pose temp,
) {
  var total = 0.0;
  for (var i = 0; i < clips.length; i++) {
    final w = i < weights.length ? weights[i] : 0.0;
    final clip = model.clips[clips[i]];
    if (w <= 1e-4 || clip == null) continue;
    final at = phase * clip.duration;
    if (total == 0) {
      out.setRest(model.data);
      clip.sample(at, out);
      total = w;
      continue;
    }
    temp.setRest(model.data);
    clip.sample(at, temp);
    total += w;
    out.blend(out, temp, w / total);
  }
  if (total == 0) out.setRest(model.data);
}

/// The clip time between the player's last two updates.
double _timeAt(AnimationPlayerComponent p, double duration, double alpha) {
  if (alpha >= 1 || p.previousTime == p.time) return p.time;
  var current = p.time;
  // A loop that wrapped since the last update: unwrap to blend across.
  if (p.loop && duration > 0) {
    if (p.speed > 0 && current < p.previousTime) current += duration;
    if (p.speed < 0 && current > p.previousTime) current -= duration;
  }
  final t = p.previousTime + (current - p.previousTime) * alpha;
  return p.loop && duration > 0 ? _wrap(t, duration) : t;
}

/// The blend's phase between the player's last two updates.
double _blendPhaseAt(AnimationPlayerComponent p, double alpha) {
  if (alpha >= 1 || p.previousPhase == p.phase) return p.phase;
  var current = p.phase;
  if (p.loop) {
    if (p.speed > 0 && current < p.previousPhase) current += 1;
    if (p.speed < 0 && current > p.previousPhase) current -= 1;
  }
  final t = p.previousPhase + (current - p.previousPhase) * alpha;
  return p.loop ? _wrap(t, 1) : t;
}

double _wrap(double t, double duration) {
  final r = t % duration;
  return r < 0 ? r + duration : r;
}

/// Seconds one cycle of a blend lasts: its clips' lengths over their
/// speeds, weighted.
double _cycleOf(
  GpuModel? model,
  List<String> clips,
  List<double> weights,
  List<double> speeds,
) {
  var cycle = 0.0, total = 0.0;
  for (var i = 0; i < clips.length; i++) {
    final duration = model?.clips[clips[i]]?.duration ?? 0;
    final w = i < weights.length ? weights[i] : 0.0;
    final speed = i < speeds.length && speeds[i] > 0 ? speeds[i] : 1.0;
    if (duration <= 0 || w <= 0) continue;
    cycle += w * duration / speed;
    total += w;
  }
  return total > 0 ? cycle / total : 0;
}

/// Moves animation time on and places sockets: for every entity with an
/// [AnimationPlayerComponent] and a [ModelComponent], advances its clip
/// (looping or holding at the end) and its crossfade; then moves each
/// [SocketComponent] entity to its node in its parent's posed model.
///
/// The renderer draws the pose between the last two updates, so motion is
/// smooth at any frame rate. Added to the world by `Graphics3D`.
final class AnimationSystem3D extends System {
  /// A system reading clip lengths and skeletons from [models].
  AnimationSystem3D(this.models) {
    priority = SystemPriorities.animation;
  }

  /// Where models are loaded.
  final GraphicsModels models;

  @override
  List<Type> get requiredComponents => const [AnimationPlayerComponent];

  // One posed copy per socket parent, kept while the parent lives.
  final Map<Entity, (PosedModel, PlayerScratch)> _parents = {};
  final Map<(PosedModel, String), int> _nodes = {};
  final Matrix4 _parentWorld = Matrix4.identity();
  final Matrix4 _node = Matrix4.identity();
  final Quaternion _rotation = Quaternion.identity();
  int _structure = -1;

  @override
  void update(double deltaTime) {
    for (final archetype in world.queryArchetypes(const [
      AnimationPlayerComponent,
      ModelComponent,
    ])) {
      final players = archetype.getColumn(AnimationPlayerComponent)!;
      final modelColumn = archetype.getColumn(ModelComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActive) continue;
        final path = (modelColumn[row] as ModelComponent).model;
        final model = path.isEmpty ? null : models.get(path);
        _advance(players[row] as AnimationPlayerComponent, model, deltaTime);
      }
    }
    _placeSockets();
  }

  void _advance(AnimationPlayerComponent p, GpuModel? model, double dt) {
    p
      ..previousTime = p.time
      ..previousPhase = p.phase;
    if (p.isBlending) {
      final cycle = _cycleOf(
        model,
        p.blendClips,
        p.blendWeights,
        p.blendSpeeds,
      );
      p.duration = cycle;
      if (p.playing && cycle > 0) {
        final next = p.phase + dt * p.speed / cycle;
        if (p.loop) {
          p.cycles += next.floor() - p.phase.floor();
          p.phase = _wrap(next, 1);
        } else {
          p.phase = next.clamp(0.0, 1.0);
        }
        p.time = p.phase * cycle;
      }
    } else {
      final duration = model?.clips[p.clip]?.duration ?? 0;
      p.duration = duration;
      if (p.playing && duration > 0) {
        final t = p.time + dt * p.speed;
        if (p.loop) {
          p.cycles += (t / duration).floor() - (p.time / duration).floor();
          p.time = _wrap(t, duration);
        } else {
          p.time = t.clamp(0.0, duration);
        }
      }
    }
    if (p.fade < 1) {
      final seconds = p.fadeSeconds;
      p.fade = seconds <= 0 ? 1 : math.min(1, p.fade + dt / seconds);
      if (p.fadingFromBlend.isNotEmpty) {
        final cycle = _cycleOf(
          model,
          p.fadingFromBlend,
          p.fadingFromWeights,
          const [],
        );
        if (cycle > 0) {
          p.fadingFromPhase = _wrap(
            p.fadingFromPhase + dt * p.speed / cycle,
            1,
          );
        }
      } else {
        final fromDuration = model?.clips[p.fadingFrom]?.duration ?? 0;
        if (fromDuration > 0) {
          p.fadingFromTime = _wrap(
            p.fadingFromTime + dt * p.speed,
            fromDuration,
          );
        }
      }
      if (p.fade >= 1) {
        p
          ..fadingFrom = ''
          ..fadingFromBlend = const [];
      }
    }
  }

  void _placeSockets() {
    if (world.structureVersion != _structure) {
      _structure = world.structureVersion;
      _parents.removeWhere((entity, _) => !entity.isAlive);
    }
    for (final archetype in world.queryArchetypes(const [
      SocketComponent,
      ParentComponent,
      TransformComponent,
    ])) {
      final sockets = archetype.getColumn(SocketComponent)!;
      final links = archetype.getColumn(ParentComponent)!;
      final transforms = archetype.getColumn(TransformComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActive) continue;
        final parentId = (links[row] as ParentComponent).parentId;
        final parent = parentId == null ? null : world.getEntity(parentId);
        final parentTransform = parent?.getComponent<TransformComponent>();
        final modelComponent = parent?.getComponent<ModelComponent>();
        if (parent == null ||
            parentTransform == null ||
            modelComponent == null) {
          continue;
        }
        final model = modelComponent.model.isEmpty
            ? null
            : models.get(modelComponent.model);
        if (model == null) continue;
        final (posed, scratch) = _parents.putIfAbsent(parent, () {
          final posed = PosedModel(model);
          return (posed, PlayerScratch(model.data.nodes.length));
        });
        if (!identical(posed.model, model)) {
          _parents.remove(parent);
          continue;
        }
        final socket = sockets[row] as SocketComponent;
        final node = _nodes.putIfAbsent((
          posed,
          socket.node,
        ), () => posed.nodeNamed(socket.node));
        if (node < 0) continue;
        final player = parent.getComponent<AnimationPlayerComponent>();
        if (player != null) {
          samplePlayer(player, model, posed.pose, scratch);
        } else {
          posed.pose.setRest(model.data);
        }
        model.skeleton.evaluate(posed.pose, posed.nodeMatrices);
        parentTransform.localToWorldInto(_parentWorld);
        posed.nodeMatrixInto(node, _node);
        // The joint's frame in engine axes: a model hung on the socket gets
        // its own axis turn when drawn, so the joint's is undone after.
        _parentWorld
          ..multiply(gltfToEngine)
          ..multiply(_node)
          ..multiply(gltfToEngine);
        _place(transforms[row] as TransformComponent, _parentWorld);
      }
    }
  }

  /// Moves [t] to [m]'s position and rotation, keeping [t]'s scale.
  void _place(TransformComponent t, Matrix4 m) {
    final s = m.storage;
    t.position.setValues(s[12], s[13], s[14]);
    double length(int o) =>
        math.sqrt(s[o] * s[o] + s[o + 1] * s[o + 1] + s[o + 2] * s[o + 2]);
    final sx = length(0), sy = length(4), sz = length(8);
    if (sx < 1e-12 || sy < 1e-12 || sz < 1e-12) return;
    _rotation.setFromRotationElements(
      s[0] / sx,
      s[4] / sy,
      s[8] / sz, //
      s[1] / sx,
      s[5] / sy,
      s[9] / sz,
      s[2] / sx,
      s[6] / sy,
      s[10] / sz,
    );
    t.setRotation(_rotation);
  }
}
