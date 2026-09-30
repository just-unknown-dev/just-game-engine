library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;

import '../../../ecs/components/camera/camera_manager_components.dart';
import '../camera_manager.dart';
import '../camera_state.dart';

/// Shows the child mapped to another entity's `CameraStateComponent.state`.
class StateDrivenManager extends CameraManager<CameraStateDrivenComponent> {
  const StateDrivenManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraStateDrivenComponent driven,
  ) {
    final source = context.brain.targets.resolve(
      name: driven.sourceName,
      tag: driven.sourceTag,
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
  const BlendListManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraBlendListComponent list,
  ) {
    if (list.steps.isEmpty) return null;
    final run =
        context.memory.extra[this] as _BlendListRun? ??
        (context.memory.extra[this] = _BlendListRun());

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
}

class _BlendListRun {
  int index = 0;
  double elapsed = 0;
  bool isFirst = true;
  final CameraChildBlender blender = CameraChildBlender();
}

/// Shows every weighted child at once.
class MixerManager extends CameraManager<CameraMixerComponent> {
  const MixerManager();

  @override
  CameraState? evaluate(
    CameraManagerContext context,
    CameraMixerComponent mix,
  ) {
    var total = 0.0;
    var position = Offset.zero;
    var logZoom = 0.0;
    var rotation = 0.0;
    var z = 0.0, pitch = 0.0, yaw = 0.0;
    // The lens is the heaviest child's: projections do not average.
    CameraState? heaviest;
    var heaviestWeight = 0.0;
    for (final child in context.children) {
      final weight = mix.weights[child.name] ?? 0;
      if (weight <= 0) continue;
      final shot = context.stateOf(child);
      if (shot == null) continue;
      total += weight;
      position += shot.position * weight;
      // Lenses mix geometrically, like they blend.
      logZoom += math.log(shot.zoom <= 0 ? 0.0001 : shot.zoom) * weight;
      rotation += shot.rotation * weight;
      z += shot.z * weight;
      pitch += shot.pitch * weight;
      yaw += shot.yaw * weight;
      if (weight > heaviestWeight) {
        heaviest = shot;
        heaviestWeight = weight;
      }
    }
    if (total <= 0 || heaviest == null) return null;
    return CameraState(
      position: position / total,
      zoom: math.exp(logZoom / total),
      rotation: rotation / total,
      z: z / total,
      pitch: pitch / total,
      yaw: yaw / total,
      lens: heaviest.lens,
    );
  }
}
