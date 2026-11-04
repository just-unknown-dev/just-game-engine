import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_dart/just_dart.dart' show Matrix4, Quaternion;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../../ecs/ecs.dart';
import 'model_components.dart';
import 'graphics_models.dart';

/// Poses to blend through while sampling a player: one set per model. It
/// also remembers what was last sampled, so a pose that would come out the
/// same is not worked out again ([samplePlayer]'s `skipUnchanged`).
final class PlayerScratch {
  /// Scratch for a model of [nodeCount] nodes.
  PlayerScratch(int nodeCount) : a = Pose(nodeCount), b = Pose(nodeCount);

  /// Each clip of a blend is sampled into this.
  final Pose a;

  /// What fades out is built here.
  final Pose b;

  // What was last sampled, and into which pose.
  Pose? _pose;
  bool _blending = false;
  String _clip = '';
  double _at = double.nan;
  final List<String> _clips = [];
  final List<double> _weights = [];
  final List<double> _speeds = [];
  bool _fading = false;
  double _fade = double.nan;
  String _from = '';
  double _fromAt = double.nan;
  final List<String> _fromClips = [];
  final List<double> _fromWeights = [];
  final List<double> _fromSpeeds = [];

  /// Remembers that [pose] shows [p] at [at] (its clip's time, or its
  /// blend's phase); whether that differs from what it last remembered.
  bool _remember(AnimationPlayerComponent p, Pose pose, double at) {
    var changed = false;
    if (!identical(pose, _pose)) {
      _pose = pose;
      changed = true;
    }
    final blending = p.isBlending;
    if (blending != _blending || at != _at) {
      _blending = blending;
      _at = at;
      changed = true;
    }
    if (blending) {
      changed = _copy(p.blendClips, _clips) | changed;
      changed = _copy(p.blendWeights, _weights) | changed;
      changed = _copy(p.blendSpeeds, _speeds) | changed;
    } else if (p.playingClip != _clip) {
      _clip = p.playingClip;
      changed = true;
    }
    final fading = p.isFading;
    if (fading != _fading) {
      _fading = fading;
      changed = true;
    }
    if (!fading) return changed;
    final fromBlend = p.fadingFromBlend.isNotEmpty;
    final fromAt = fromBlend ? p.fadingFromPhase : p.fadingFromTime;
    if (p.fade != _fade || p.fadingFrom != _from || fromAt != _fromAt) {
      _fade = p.fade;
      _from = p.fadingFrom;
      _fromAt = fromAt;
      changed = true;
    }
    changed = _copy(p.fadingFromBlend, _fromClips) | changed;
    changed = _copy(p.fadingFromWeights, _fromWeights) | changed;
    return _copy(p.fadingFromSpeeds, _fromSpeeds) | changed;
  }

  /// Makes [kept] hold what [now] holds; whether it differed.
  static bool _copy<T>(List<T> now, List<T> kept) {
    var same = now.length == kept.length;
    for (var i = 0; same && i < now.length; i++) {
      same = now[i] == kept[i];
    }
    if (same) return false;
    kept
      ..clear()
      ..addAll(now);
    return true;
  }
}

/// Writes into [pose] what [player] shows, [alpha] of the way from its
/// previous update to its latest: its clip or blend, blended with what is
/// fading out. Nodes no clip moves keep [model]'s rest pose. A time past a
/// clip's ends is wrapped into it when it loops, else held at the end.
///
/// With [skipUnchanged] it writes nothing, and returns false, when [pose]
/// already holds this — the same clips at the same times, as [scratch]
/// remembers them from its last call; otherwise it returns true.
bool samplePlayer(
  AnimationPlayerComponent player,
  GpuModel model,
  Pose pose,
  PlayerScratch scratch, {
  double alpha = 1,
  bool skipUnchanged = false,
}) {
  final blending = player.isBlending;
  final clip = blending ? null : model.clips[player.playingClip];
  final at = blending
      ? _inCycle(_blendPhaseAt(player, alpha), 1, player.playingLoop)
      : clip == null
      ? 0.0
      : _inCycle(
          _timeAt(player, clip.duration, alpha),
          clip.duration,
          player.playingLoop,
        );
  final changed = scratch._remember(player, pose, at);
  if (skipUnchanged && !changed) return false;
  if (blending) {
    _sampleMix(
      model,
      player.blendClips,
      player.blendWeights,
      player.blendSpeeds,
      at,
      pose,
      scratch.a,
    );
  } else {
    pose.setRest(model.data);
    clip?.sample(at, pose);
  }
  if (!player.isFading) return true;
  final from = scratch.b;
  if (player.fadingFromBlend.isNotEmpty) {
    _sampleMix(
      model,
      player.fadingFromBlend,
      player.fadingFromWeights,
      player.fadingFromSpeeds,
      player.fadingFromPhase,
      from,
      scratch.a,
    );
  } else {
    from.setRest(model.data);
    final clip = model.clips[player.fadingFrom];
    if (clip == null) return true;
    clip.sample(player.fadingFromTime, from);
  }
  pose.blend(from, pose, player.fade);
  return true;
}

/// [clips] weighted by [weights], each at [phase] of its own length — from
/// its end, for a motion whose speed in [speeds] is negative — into [out];
/// [temp] holds each clip while it is folded in.
void _sampleMix(
  GpuModel model,
  List<String> clips,
  List<double> weights,
  List<double> speeds,
  double phase,
  Pose out,
  Pose temp,
) {
  var total = 0.0;
  for (var i = 0; i < clips.length; i++) {
    final w = i < weights.length ? weights[i] : 0.0;
    final clip = model.clips[clips[i]];
    if (w <= 1e-4 || clip == null) continue;
    final backwards = i < speeds.length && speeds[i] < 0;
    final at = (backwards ? 1 - phase : phase) * clip.duration;
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
  if (p.playingLoop && duration > 0) {
    if (p.playingSpeed > 0 && current < p.previousTime) current += duration;
    if (p.playingSpeed < 0 && current > p.previousTime) current -= duration;
  }
  final t = p.previousTime + (current - p.previousTime) * alpha;
  return p.playingLoop && duration > 0 ? _wrap(t, duration) : t;
}

/// The blend's phase between the player's last two updates.
double _blendPhaseAt(AnimationPlayerComponent p, double alpha) {
  if (alpha >= 1 || p.previousPhase == p.phase) return p.phase;
  var current = p.phase;
  if (p.playingLoop) {
    if (p.playingSpeed > 0 && current < p.previousPhase) current += 1;
    if (p.playingSpeed < 0 && current > p.previousPhase) current -= 1;
  }
  final t = p.previousPhase + (current - p.previousPhase) * alpha;
  return p.playingLoop ? _wrap(t, 1) : t;
}

double _wrap(double t, double duration) {
  final r = t % duration;
  return r < 0 ? r + duration : r;
}

/// [t] within a cycle [length] long: wrapped into it when it [loop]s,
/// else held at its ends.
double _inCycle(double t, double length, bool loop) {
  if (length <= 0) return 0;
  return loop ? _wrap(t, length) : t.clamp(0.0, length);
}

/// Seconds one cycle of a blend lasts: its clips' lengths over their
/// speeds, weighted.
///
/// Motions of one clip count as that clip at their speeds' weighted mean.
/// Its stride is the same at any speed, so between two of them its feet
/// keep to the ground, as they do at each; weighting their lengths instead
/// would play it too slowly. Different clips' lengths are weighted, so a
/// long idle keeps near its own pace as a walk comes in.
double _cycleOf(
  GpuModel? model,
  List<String> clips,
  List<double> weights,
  List<double> speeds,
) {
  var cycle = 0.0, total = 0.0;
  for (var i = 0; i < clips.length; i++) {
    // Each clip once, with every motion that plays it.
    if (clips.indexOf(clips[i]) < i) continue;
    final duration = model?.clips[clips[i]]?.duration ?? 0;
    if (duration <= 0) continue;
    var w = 0.0, rate = 0.0;
    for (var j = i; j < clips.length; j++) {
      final wj = j < weights.length ? weights[j] : 0.0;
      if (clips[j] != clips[i] || wj <= 0) continue;
      w += wj;
      // A motion played backwards goes as fast as one played forwards.
      final speed = j < speeds.length ? speeds[j].abs() : 1.0;
      rate += wj * (speed > 0 ? speed : 1.0);
    }
    if (w <= 0) continue;
    // Its weight times its length over its mean speed, rate / w.
    cycle += w * w * duration / rate;
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
/// smooth at any frame rate. A socket's entity gets a previous pose too —
/// its node where the update began, on its parent as the renderer draws it
/// there — so it is drawn between the two, in the hand, not ahead of it.
/// Each parent is posed once an update, however many sockets it carries.
/// Added to the world by `Graphics3D`.
final class Animation3DSystem extends System {
  /// A system reading clip lengths and skeletons from [models].
  Animation3DSystem(this.models) {
    priority = SystemPriorities.animation;
  }

  /// Where models are loaded.
  final GraphicsModels models;

  @override
  List<Type> get requiredComponents => const [AnimationPlayerComponent];

  // One posed copy per socket parent, kept while the parent lives.
  final Map<Entity, _SocketParent> _parents = {};
  final Matrix4 _socketWorld = Matrix4.identity();
  final Matrix4 _node = Matrix4.identity();
  final Quaternion _rotation = Quaternion.identity();
  int _structure = -1;
  int _updates = 0;

  /// How many socket parents are posed for their sockets, for tests.
  @visibleForTesting
  int get debugSocketParents => _parents.length;

  /// How many times a socket parent has been posed, for tests.
  @visibleForTesting
  int debugPoses = 0;

  @override
  void update(double deltaTime) {
    for (final archetype in world.queryArchetypes(const [
      AnimationPlayerComponent,
      ModelComponent,
    ])) {
      final players = archetype.getColumn(AnimationPlayerComponent)!;
      final modelColumn = archetype.getColumn(ModelComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
        final path = (modelColumn[row] as ModelComponent).model;
        final model = path.isEmpty ? null : models.get(path);
        _advance(players[row] as AnimationPlayerComponent, model, deltaTime);
      }
    }
    _placeSockets();
  }

  void _advance(AnimationPlayerComponent p, GpuModel? model, double dt) {
    final blending = p.isBlending;
    final length = blending
        ? _cycleOf(model, p.blendClips, p.blendWeights, p.blendSpeeds)
        : model?.clips[p.playingClip]?.duration ?? 0;
    p
      ..duration = length
      // Just started: backwards from its end.
      ..placeStart(length)
      ..previousTime = p.time
      ..previousPhase = p.phase;
    if (p.isPlaying && length > 0) _move(p, length, dt);
    _advanceFade(p, model, dt);
  }

  /// Moves [p]'s time on by [dt] at its speed: a loop wraps, counting the
  /// laps; anything else stops at its end — its start, played backwards.
  static void _move(AnimationPlayerComponent p, double length, double dt) {
    final backwards = p.playingSpeed < 0;
    if (p.isBlending) {
      final next = p.phase + dt * p.playingSpeed / length;
      if (p.playingLoop) {
        p
          ..cycles += _laps(p.phase, next, 1, backwards: backwards)
          ..phase = _wrapFor(next, 1, backwards: backwards);
      } else {
        p.phase = next.clamp(0.0, 1.0);
      }
      p.time = p.phase * length;
      return;
    }
    final t = p.time + dt * p.playingSpeed;
    if (p.playingLoop) {
      p
        ..cycles += _laps(p.time, t, length, backwards: backwards)
        ..time = _wrapFor(t, length, backwards: backwards);
    } else {
      p.time = t.clamp(0.0, length);
    }
  }

  /// How many times time going from [from] to [to] passed a loop's end,
  /// [length] long, the way it plays.
  static int _laps(
    double from,
    double to,
    double length, {
    required bool backwards,
  }) => backwards
      ? (from / length).ceil() - (to / length).ceil()
      : (to / length).floor() - (from / length).floor();

  /// [t] within a loop [length] long: 0 up to (not including) [length]
  /// forwards; above 0 up to [length] backwards, so a backwards loop that
  /// lands on its start counts the lap and goes on from its end.
  static double _wrapFor(double t, double length, {required bool backwards}) {
    final r = _wrap(t, length);
    return backwards && r == 0 ? length : r;
  }

  /// Moves what fades out on by [dt], and the fade.
  void _advanceFade(AnimationPlayerComponent p, GpuModel? model, double dt) {
    if (p.fade < 1) {
      final seconds = p.fadeSeconds;
      p.fade = seconds <= 0 ? 1 : math.min(1, p.fade + dt / seconds);
      // What fades out goes on as it played: at its own speed, looping or
      // holding at its end.
      final step = dt * p.fadingFromSpeed;
      if (p.fadingFromBlend.isNotEmpty) {
        final cycle = _cycleOf(
          model,
          p.fadingFromBlend,
          p.fadingFromWeights,
          p.fadingFromSpeeds,
        );
        if (cycle > 0) {
          final next = p.fadingFromPhase + step / cycle;
          p.fadingFromPhase = p.fadingFromLoop
              ? _wrap(next, 1)
              : next.clamp(0.0, 1.0);
        }
      } else {
        final fromDuration = model?.clips[p.fadingFrom]?.duration ?? 0;
        if (fromDuration > 0) {
          final next = p.fadingFromTime + step;
          p.fadingFromTime = p.fadingFromLoop
              ? _wrap(next, fromDuration)
              : next.clamp(0.0, fromDuration);
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
    final version = world.queryVersion(const [
      TransformComponent,
      ModelComponent,
    ]);
    if (version != _structure) {
      _structure = version;
      _parents.removeWhere((entity, _) => !entity.isAlive);
    }
    _updates++;
    for (final archetype in world.queryArchetypes(const [
      SocketComponent,
      ParentComponent,
      TransformComponent,
    ])) {
      final sockets = archetype.getColumn(SocketComponent)!;
      final links = archetype.getColumn(ParentComponent)!;
      final transforms = archetype.getColumn(TransformComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
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
        var posed = _parents[parent];
        if (posed == null || !identical(posed.posed.model, model)) {
          posed = _parents[parent] = _SocketParent(model, parentTransform);
        }
        final node = posed.nodeNamed((sockets[row] as SocketComponent).node);
        if (node < 0) continue;
        if (posed.posedAt != _updates) {
          _pose(posed, parent, parentTransform);
          posed.posedAt = _updates;
        }
        final t = transforms[row] as TransformComponent;
        // Where the update began, kept as its previous pose; then where it
        // is now.
        _socketInto(posed.previousWorld, posed.previousNodes, node);
        _place(t, _socketWorld);
        t.capturePrevious();
        _socketInto(posed.world, posed.posed.nodeMatrices, node);
        _place(t, _socketWorld);
      }
    }
  }

  /// Poses [p]'s model as [parent] shows it at the update's start and now,
  /// and where [transform] puts it then and now — the start from its
  /// previous pose when something captured one in the update (as the
  /// renderer draws it), else from where it is.
  void _pose(_SocketParent p, Entity parent, TransformComponent transform) {
    debugPoses++;
    final count = transform.captureCount;
    final fresh = count != p.captures && p.posedAt == _updates - 1;
    p.captures = count;
    transform.localToWorldInto(p.world);
    if (fresh) {
      transform.interpolatedToWorldInto(p.previousWorld, 0);
    } else {
      p.previousWorld.setFrom(p.world);
    }
    final posed = p.posed;
    final model = posed.model;
    final player = parent.getComponent<AnimationPlayerComponent>();
    final moving =
        player != null &&
        (player.previousTime != player.time ||
            player.previousPhase != player.phase);
    if (moving) {
      samplePlayer(player, model, posed.pose, p.scratch, alpha: 0);
      model.skeleton.evaluate(posed.pose, p.previousNodes);
    }
    if (player != null) {
      samplePlayer(player, model, posed.pose, p.scratch);
    } else {
      posed.pose.setRest(model.data);
    }
    model.skeleton.evaluate(posed.pose, posed.nodeMatrices);
    if (!moving) p.previousNodes.setAll(0, posed.nodeMatrices);
  }

  /// Into [_socketWorld]: the frame of [node] — its matrix in [nodes] — on
  /// a model placed at [parentWorld], in engine axes.
  void _socketInto(Matrix4 parentWorld, Float32List nodes, int node) {
    final m = _node.storage;
    for (var i = 0; i < 16; i++) {
      m[i] = nodes[node * 16 + i];
    }
    // The joint's frame in engine axes: a model hung on the socket gets its
    // own axis turn when drawn, so the joint's is undone after.
    _socketWorld
      ..setFrom(parentWorld)
      ..multiply(gltfToEngine)
      ..multiply(_node)
      ..multiply(gltfToEngine);
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

/// A socket parent's model, posed for its sockets once an update.
final class _SocketParent {
  _SocketParent(GpuModel model, TransformComponent transform)
    : posed = PosedModel(model),
      scratch = PlayerScratch(model.data.nodes.length),
      previousNodes = Float32List(model.data.nodes.length * 16),
      captures = transform.captureCount;

  /// The model in its pose now.
  final PosedModel posed;

  /// Where a blend is put together.
  final PlayerScratch scratch;

  /// Every node's model-space matrix at the update's start, 16 floats each.
  final Float32List previousNodes;

  /// Where the parent is now, and where it was drawn from at the update's
  /// start.
  final Matrix4 world = Matrix4.identity();
  final Matrix4 previousWorld = Matrix4.identity();

  /// The parent transform's capture count when last posed.
  int captures;

  /// The update it was last posed in.
  int posedAt = -1;

  final Map<String, int> _nodes = {};

  /// The index of the node called [name], or -1.
  int nodeNamed(String name) => _nodes[name] ??= posed.nodeNamed(name);
}
