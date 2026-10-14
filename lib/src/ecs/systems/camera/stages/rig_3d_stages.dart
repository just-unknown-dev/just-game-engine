/// 3-D camera rigs: orbit follow, first person and look at.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;
import 'package:just_dart/just_dart.dart';

import '../../../components/camera/camera_rig_3d_components.dart';
import '../camera_stage.dart';
import '../../../../subsystems/camera/camera_state.dart';

/// The way a camera with [pitch] and [yaw] looks (unit length): +Z when
/// both are zero. A pitch below zero looks down (+Y is down).
Vector3 cameraForward(double pitch, double yaw) => Vector3(
  math.cos(pitch) * math.sin(yaw),
  -math.sin(pitch),
  math.cos(pitch) * math.cos(yaw),
);

/// The pitch and yaw that look along [direction].
(double pitch, double yaw) cameraAnglesOf(Vector3 direction) {
  final flat = math.sqrt(direction.x * direction.x + direction.z * direction.z);
  return (-math.atan2(direction.y, flat), math.atan2(direction.x, direction.z));
}

/// The target's 3-D position, or the camera's own when it has none.
Vector3 _anchor(CameraStageContext context, CameraState state) =>
    context.targetPosition3 ?? Vector3(state.position.dx, state.position.dy, state.z);

/// Body: circles the target at a distance, turned by the component's yaw
/// and pitch, the pivot easing after the target.
class OrbitFollowStage extends CameraStage<OrbitFollowComponent> {
  /// Stateless; the brain registers one for [OrbitFollowComponent].
  const OrbitFollowStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.body;

  @override
  CameraState apply(
    CameraStageContext context,
    OrbitFollowComponent orbit,
    CameraState state,
    double dt,
  ) {
    final memory = context.memory;
    final target = _anchor(context, state)..add(orbit.pivot);
    final pivot = memory.extra[this] as Vector3?;
    final Vector3 at;
    if (pivot == null || context.snap || !memory.initialized) {
      at = Vector3.copy(target);
    } else {
      final k = CameraStage.damp(orbit.damping, dt);
      at = pivot
        ..setValues(
          pivot.x + (target.x - pivot.x) * k,
          pivot.y + (target.y - pivot.y) * k,
          pivot.z + (target.z - pivot.z) * k,
        );
    }
    memory.extra[this] = at;
    final pitch = orbit.pitch.clamp(orbit.minPitch, orbit.maxPitch);
    final distance = orbit.distance.clamp(orbit.minDistance, math.max(orbit.minDistance, orbit.maxDistance));
    final forward = cameraForward(pitch, orbit.yaw);
    // Right of the view, level: forward turned a quarter about the up axis.
    final rightX = math.cos(orbit.yaw), rightZ = -math.sin(orbit.yaw);
    final x = at.x - forward.x * distance + rightX * orbit.shoulder;
    final y = at.y - forward.y * distance;
    final z = at.z - forward.z * distance + rightZ * orbit.shoulder;
    return state.copyWith(position: Offset(x, y), z: z, pitch: pitch, yaw: orbit.yaw);
  }
}

/// Body: at the target's eyes, looking where the component's yaw and pitch
/// say.
class FirstPersonStage extends CameraStage<FirstPersonComponent> {
  /// Stateless; the brain registers one for [FirstPersonComponent].
  const FirstPersonStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.body;

  @override
  CameraState apply(
    CameraStageContext context,
    FirstPersonComponent eyes,
    CameraState state,
    double dt,
  ) {
    final at = _anchor(context, state)..add(eyes.eye);
    return state.copyWith(
      position: Offset(at.x, at.y),
      z: at.z,
      pitch: eyes.pitch.clamp(eyes.minPitch, eyes.maxPitch),
      yaw: eyes.yaw,
    );
  }
}

/// Aim: turns the camera, wherever its body put it, to look at its target.
class LookAtStage extends CameraStage<LookAtComponent> {
  /// Stateless; the brain registers one for [LookAtComponent].
  const LookAtStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.aim;

  @override
  CameraState apply(
    CameraStageContext context,
    LookAtComponent look,
    CameraState state,
    double dt,
  ) {
    final target = context.targetPosition3;
    if (target == null) return state;
    final direction = Vector3(
      target.x + look.offset.x - state.position.dx,
      target.y + look.offset.y - state.position.dy,
      target.z + look.offset.z - state.z,
    );
    if (direction.lengthSquared < 1e-12) return state;
    var (pitch, yaw) = cameraAnglesOf(direction);
    final memory = context.memory;
    final last = memory.extra[this] as (double, double)?;
    if (last != null && !context.snap && memory.initialized && look.damping > 0) {
      final k = CameraStage.damp(look.damping, dt);
      pitch = last.$1 + (pitch - last.$1) * k;
      // The shorter way round.
      var turn = yaw - last.$2;
      turn = (turn + math.pi) % (2 * math.pi) - math.pi;
      yaw = last.$2 + turn * k;
    }
    memory.extra[this] = (pitch, yaw);
    return state.copyWith(pitch: pitch, yaw: yaw);
  }
}
