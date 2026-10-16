library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;

import '../../../components/camera/camera_manager_components.dart';
import '../camera_manager.dart';
import '../../../../subsystems/camera/camera_state.dart';

/// Shows the child mapped to another entity's `CameraStateComponent.state`.
class StateDrivenManager extends CameraManager<CameraStateDrivenComponent> {
  /// Stateless; the brain registers one for [CameraStateDrivenComponent].
  const StateDrivenManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraStateDrivenComponent driven,
  ) {
    final source = context.brain.targets.resolveTarget(
      driven.source,
      owner: context.entity,
    );
    final state = source?.getComponent<CameraStateComponent>()?.state;
    final child =
        context.childNamed(driven.states[state] ?? '') ??
        context.childNamed(driven.defaultChild) ??
        context.children.firstOrNull;
    if (child == null) return null;
    final shot = context.stateOf(child);
    if (shot == null) return null;
    final blender =
        context.memory.extra[this] as CameraChildBlender? ??
        (context.memory.extra[this] = CameraChildBlender());
    return blender.show(
      child.id,
      shot,
      blend: driven.blend,
      dt: context.dt,
      snap: context.snap,
    );
  }
}

/// Plays its children as a sequence of held shots.
class BlendListManager extends CameraManager<CameraBlendListComponent> {
  /// Stateless; the brain registers one for [CameraBlendListComponent].
  /// Where each list is up to lives in its camera's memory.
  const BlendListManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraBlendListComponent list,
  ) {
    if (list.steps.isEmpty) return null;
    var run =
        context.memory.extra[this] as _BlendListRun? ??
        (context.memory.extra[this] = _BlendListRun());

    // The list starts over each time its camera goes live — also for a
    // camera that kept running on standby (`CameraStandbyUpdate.always`),
    // whose memory the brain does not reset.
    final live = context.brain.liveCamera?.id == context.entity.id;
    if (live && !run.wasLive) {
      run = _BlendListRun();
      context.memory.extra[this] = run;
    }
    run.wasLive = live;

    // The list may have lost steps since last frame.
    if (run.index >= list.steps.length) run.index = list.steps.length - 1;

    // Time only runs while the game does: a frozen editor holds the shot.
    if (!context.snap) run.elapsed += context.dt;
    var step = list.steps[run.index];
    // A step lasts its blend-in plus its hold; the first has nothing to
    // blend from.
    while (run.elapsed >= _lengthOf(step, first: run.isFirst)) {
      final last = run.index == list.steps.length - 1;
      if (last && !list.loop) break;
      run
        ..elapsed -= _lengthOf(step, first: run.isFirst)
        ..index = last ? 0 : run.index + 1
        ..isFirst = false;
      step = list.steps[run.index];
      if (last) {
        // Back at the start of a loop: skip whole cycles at once. A cycle
        // of no length at all has nothing to hold — stay on the first step.
        final cycle = _cycleOf(list.steps);
        if (cycle <= 0) {
          run.elapsed = 0;
          break;
        }
        run.elapsed %= cycle;
      }
    }

    final child = context.childNamed(step.child);
    if (child == null) return null;
    final shot = context.stateOf(child);
    if (shot == null) return null;
    return run.blender.show(
      child.id,
      shot,
      blend: step.blend,
      dt: context.dt,
      snap: context.snap,
    );
  }

  static double _lengthOf(CameraBlendStep step, {required bool first}) =>
      math.max(0.0, step.hold) + (first ? 0.0 : math.max(0.0, step.blend));

  /// One pass through every step, blends included.
  static double _cycleOf(List<CameraBlendStep> steps) {
    var total = 0.0;
    for (final step in steps) {
      total += _lengthOf(step, first: false);
    }
    return total;
  }
}

class _BlendListRun {
  int index = 0;
  double elapsed = 0;
  bool isFirst = true;

  /// Whether the list's camera was live when last evaluated.
  bool wasLive = false;
  final CameraChildBlender blender = CameraChildBlender();
}

/// Shows every weighted child at once.
class MixerManager extends CameraManager<CameraMixerComponent> {
  /// Stateless; the brain registers one for [CameraMixerComponent].
  const MixerManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraMixerComponent mix,
  ) {
    var total = 0.0;
    var position = Offset.zero;
    var logZoom = 0.0;
    var z = 0.0;
    // The lens is the heaviest child's: projections do not average.
    CameraState? heaviest;
    var heaviestWeight = 0.0;
    final shots = <(CameraState, double)>[];
    for (final child in context.children) {
      final weight = mix.weights[child.name] ?? 0;
      if (weight <= 0) continue;
      final shot = context.stateOf(child);
      if (shot == null) continue;
      shots.add((shot, weight));
      total += weight;
      position += shot.position * weight;
      // Lenses mix geometrically, like they blend.
      logZoom += math.log(shot.zoom <= 0 ? 0.0001 : shot.zoom) * weight;
      z += shot.z * weight;
      if (weight > heaviestWeight) {
        heaviest = shot;
        heaviestWeight = weight;
      }
    }
    if (total <= 0 || heaviest == null) return null;
    return CameraState(
      position: position / total,
      zoom: math.exp(logZoom / total),
      rotation: _meanAngle(shots, heaviest.rotation, (s) => s.rotation),
      z: z / total,
      pitch: _meanAngle(shots, heaviest.pitch, (s) => s.pitch),
      yaw: _meanAngle(shots, heaviest.yaw, (s) => s.yaw),
      lens: heaviest.lens,
    );
  }

  /// The weighted mean of an angle, around the circle: +170° and −170°
  /// average to 180°, not 0°. Measured from [reference] — the heaviest
  /// shot's — so shots that agree give back exactly their own angle, and
  /// shots that cancel out leave it there.
  static double _meanAngle(
    List<(CameraState, double)> shots,
    double reference,
    double Function(CameraState) angleOf,
  ) {
    var sin = 0.0, cos = 0.0;
    for (final (shot, weight) in shots) {
      final turn = angleOf(shot) - reference;
      sin += math.sin(turn) * weight;
      cos += math.cos(turn) * weight;
    }
    if (sin.abs() < 1e-12 && cos.abs() < 1e-12) return reference;
    return reference + math.atan2(sin, cos);
  }
}
