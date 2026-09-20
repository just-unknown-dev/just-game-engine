library;

import 'package:flutter/painting.dart' show Offset;

import '../../../ecs/components/camera/camera_framing_component.dart';
import '../camera_stage.dart';
import '../camera_state.dart';

/// Body: keeps the target inside its dead zone, easing when it leaves and
/// never letting it out of the soft zone.
class FramingStage extends CameraStage<CameraFramingComponent> {
  const FramingStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.body;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraFramingComponent framing,
    CameraState state,
    double dt,
  ) {
    final memory = context.memory;
    final targetAt = context.targetPosition;
    if (targetAt == null) {
      // Nothing to frame: hold where the camera last settled, or where its
      // entity sits if it never has.
      if (!memory.initialized) memory.position = state.position;
      return state.copyWith(position: memory.position);
    }

    final snap = context.snap || !memory.initialized;
    final aim = targetAt + _lookahead(context, framing, targetAt, dt, snap);

    // Where the camera would be with the target exactly on its screen spot.
    final view = context.viewAt(state.zoom);
    final ideal =
        aim -
        Offset(framing.screenX * view.width, framing.screenY * view.height);

    var camera = snap ? ideal : memory.position;
    if (!snap) {
      camera = Offset(
        _axis(
          camera.dx,
          ideal.dx,
          dead: framing.deadZoneWidth * view.width / 2,
          soft: framing.softZoneWidth * view.width / 2,
          damping: framing.dampingX,
          dt: dt,
        ),
        _axis(
          camera.dy,
          ideal.dy,
          dead: framing.deadZoneHeight * view.height / 2,
          soft: framing.softZoneHeight * view.height / 2,
          damping: framing.dampingY,
          dt: dt,
        ),
      );
    }
    // An axis that does not follow stays where the camera's entity is.
    camera = Offset(
      framing.followX ? camera.dx : state.position.dx,
      framing.followY ? camera.dy : state.position.dy,
    );
    memory.position = camera;
    return state.copyWith(position: camera);
  }

  /// One axis of the dead zone / soft zone rule.
  double _axis(
    double camera,
    double ideal, {
    required double dead,
    required double soft,
    required double damping,
    required double dt,
  }) {
    final gap = ideal - camera;
    // Inside the dead zone the camera owes the target nothing.
    final owed = gap.abs() <= dead ? 0.0 : gap - gap.sign * dead;
    var next = camera + owed * CameraStage.damp(damping, dt);
    // However lazily it follows, the target never leaves the soft zone.
    final limit = soft < dead ? dead : soft;
    final left = ideal - next;
    if (left.abs() > limit) next = ideal - left.sign * limit;
    return next;
  }

  Offset _lookahead(
    CameraStageContext context,
    CameraFramingComponent framing,
    Offset targetAt,
    double dt,
    bool snap,
  ) {
    final memory = context.memory;
    // A target that does not report a velocity still has one: how far it
    // moved since last frame.
    var velocity = context.targetVelocity;
    final previous = memory.previousTargetPosition;
    if (context.target != null &&
        velocity == Offset.zero &&
        previous != null &&
        dt > 0) {
      velocity = (targetAt - previous) / dt;
    }
    memory.previousTargetPosition = targetAt;
    if (framing.lookaheadTime <= 0) {
      memory.lookaheadVelocity = Offset.zero;
      return Offset.zero;
    }
    memory.lookaheadVelocity = snap
        ? velocity
        : Offset.lerp(
            memory.lookaheadVelocity,
            velocity,
            CameraStage.damp(framing.lookaheadSmoothing, dt),
          )!;
    return memory.lookaheadVelocity * framing.lookaheadTime;
  }
}
