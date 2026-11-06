/// 3-D camera rigs: orbit follow, first person and look at.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;
import 'package:just_dart/just_dart.dart';

import '../camera_rig_3d_components.dart';
import '../camera_stage.dart';
import '../camera_state.dart';

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

/// [value] kept between [a] and [b], whichever is the lower: a lowest
/// pitch typed above the highest must not throw every frame.
double _between(double value, double a, double b) =>
    value.clamp(math.min(a, b), math.max(a, b)).toDouble();

/// Body: circles the target at a distance, turned by the component's yaw
/// and pitch, the pivot easing after the target.
///
/// A camera that follows a target holds its pivot while the target is
/// missing (destroyed, or not spawned yet), and snaps to the target the
/// first time it has one. A camera that follows nothing circles its own
/// spot.
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
    final pivot = memory.extra[this] as Vector3?;
    // Read, never changed: every stage after this one reads it too.
    final anchor = context.targetPosition3;
    final Vector3 at;
    if (anchor == null && context.vcam.hasTarget) {
      // The target is missing this frame: hold the pivot where it was. A
      // camera that has never had one frames from its own spot without
      // remembering it, so the target, once there, is snapped to.
      at =
          pivot ??
          Vector3(
            state.position.dx + orbit.pivot.x,
            state.position.dy + orbit.pivot.y,
            state.z + orbit.pivot.z,
          );
    } else {
      final tx = (anchor?.x ?? state.position.dx) + orbit.pivot.x;
      final ty = (anchor?.y ?? state.position.dy) + orbit.pivot.y;
      final tz = (anchor?.z ?? state.z) + orbit.pivot.z;
      if (pivot == null || context.snap) {
        at = Vector3(tx, ty, tz);
      } else {
        final k = CameraStage.damp(orbit.damping, dt);
        at = pivot
          ..setValues(
            pivot.x + (tx - pivot.x) * k,
            pivot.y + (ty - pivot.y) * k,
            pivot.z + (tz - pivot.z) * k,
          );
      }
      memory.extra[this] = at;
    }
    final pitch = _between(orbit.pitch, orbit.minPitch, orbit.maxPitch);
    final distance = orbit.distance.clamp(
      orbit.minDistance,
      math.max(orbit.minDistance, orbit.maxDistance),
    );
    final forward = cameraForward(pitch, orbit.yaw);
    // Right of the view, level: forward turned a quarter about the up axis.
    final rightX = math.cos(orbit.yaw), rightZ = -math.sin(orbit.yaw);
    final x = at.x - forward.x * distance + rightX * orbit.shoulder;
    final y = at.y - forward.y * distance;
    final z = at.z - forward.z * distance + rightZ * orbit.shoulder;
    return state.copyWith(
      position: Offset(x, y),
      z: z,
      pitch: pitch,
      yaw: orbit.yaw,
    );
  }
}

/// Body: at the target's eyes, looking where the component's yaw and pitch
/// say. While the target is missing the camera stays where its eyes last
/// were; a camera that follows nothing looks from its own spot.
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
    final memory = context.memory;
    final last = memory.extra[this] as Vector3?;
    // Read, never changed: every stage after this one reads it too.
    final anchor = context.targetPosition3;
    final Vector3 at;
    if (anchor == null && context.vcam.hasTarget && last != null) {
      at = last;
    } else {
      final x = (anchor?.x ?? state.position.dx) + eyes.eye.x;
      final y = (anchor?.y ?? state.position.dy) + eyes.eye.y;
      final z = (anchor?.z ?? state.z) + eyes.eye.z;
      at = (last ?? Vector3.zero())..setValues(x, y, z);
      if (anchor != null) memory.extra[this] = at;
    }
    return state.copyWith(
      position: Offset(at.x, at.y),
      z: at.z,
      pitch: _between(eyes.pitch, eyes.minPitch, eyes.maxPitch),
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
    if (last != null &&
        !context.snap &&
        memory.isInitialized &&
        look.damping > 0) {
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
