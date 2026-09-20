library;

import 'package:flutter/painting.dart' show Offset, Rect;

import '../../../ecs/components/camera/camera_confiner_components.dart';
import '../../../ecs/components/camera/camera_noise_components.dart';
import '../camera_stage.dart';
import '../camera_state.dart';
import '../camera_targets.dart';

/// Noise: continuous handheld motion over the settled shot.
class NoiseStage extends CameraStage<CameraNoiseComponent> {
  const NoiseStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.noise;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraNoiseComponent noise,
    CameraState state,
    double dt,
  ) {
    // A frozen game has a still camera: nothing to author against if the
    // frame you are composing keeps moving.
    if (dt <= 0 || context.snap || noise.amplitudeGain == 0) return state;
    final memory = context.memory;
    memory.noiseTime += dt * noise.frequencyGain;
    final profile = noise.preset.profile;
    final zoom = state.zoom <= 0 ? 1.0 : state.zoom;
    return state.copyWith(
      position:
          state.position +
          profile.positionAt(memory.noiseTime) * (noise.amplitudeGain / zoom),
      rotation:
          state.rotation +
          profile.rotationAt(memory.noiseTime) * noise.amplitudeGain,
    );
  }
}

/// Noise: what the impulses in the air do to this shot.
class ImpulseListenerStage extends CameraStage<CameraImpulseListenerComponent> {
  const ImpulseListenerStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.noise;

  @override
  int get order => 10;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraImpulseListenerComponent listener,
    CameraState state,
    double dt,
  ) {
    if (context.snap || listener.gain == 0) return state;
    final felt = context.brain.impulses.feltAt(
      state.position,
      channels: listener.channels,
    );
    return felt == Offset.zero
        ? state
        : state.copyWith(position: state.position + felt * listener.gain);
  }
}

/// Finalize: keeps the whole view inside the named bounds.
class ConfinerStage extends CameraStage<CameraConfinerComponent> {
  const ConfinerStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.finalize;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraConfinerComponent confiner,
    CameraState state,
    double dt,
  ) {
    final bounds = boundsFor(context, confiner);
    if (bounds == null) return state;
    final view = context.viewAt(state.zoom);
    final wanted = Offset(
      _confine(state.position.dx, bounds.left, bounds.right, view.width / 2),
      _confine(state.position.dy, bounds.top, bounds.bottom, view.height / 2),
    );
    var push = wanted - state.position;

    // A damped confiner eases *into* the wall and lets go at once: easing
    // out would hold the camera against an edge it has already left.
    final previous = context.memory.extra[this] as Offset? ?? Offset.zero;
    if (!context.snap &&
        confiner.damping > 0 &&
        push.distance > previous.distance) {
      push = Offset.lerp(
        previous,
        push,
        CameraStage.damp(confiner.damping, dt),
      )!;
    }
    context.memory.extra[this] = push;
    return push == Offset.zero
        ? state
        : state.copyWith(position: state.position + push);
  }

  /// The rectangle [confiner] names, or null when it names nothing usable.
  static Rect? boundsFor(
    CameraStageContext context,
    CameraConfinerComponent confiner,
  ) {
    if (confiner.boundsName.isEmpty) return null;
    final entity = context.brain.targets.resolve(name: confiner.boundsName);
    if (entity == null) return null;
    final at = CameraTargetResolver.positionOf(entity);
    if (at == null) return null;
    for (final component in entity.components) {
      if (component is CameraBoundsSource) {
        return (component as CameraBoundsSource).cameraBoundsAt(at);
      }
    }
    return null;
  }

  static double _confine(double at, double low, double high, double halfView) {
    // Nowhere legal to be: centre, rather than flip between two wrong edges.
    if (high - low <= halfView * 2) return (low + high) / 2;
    return at.clamp(low + halfView, high - halfView);
  }
}
