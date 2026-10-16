library;

import 'package:flutter/painting.dart' show Offset, Size;

import '../../../components/camera/camera_framing_component.dart';
import '../camera_stage.dart';
import '../../../../subsystems/camera/camera_state.dart';

/// Body: keeps the target inside its dead zone, easing when it leaves and
/// never letting it out of the soft zone.
class FramingStage extends CameraStage<CameraFramingComponent> {
  /// Stateless; the brain registers one for [CameraFramingComponent].
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
      // Whatever comes back is measured afresh, not from where it vanished.
      memory.previousTargetPosition = null;
      memory.extra.remove(_targetKey);
      return state.copyWith(position: memory.position);
    }

    final snap = context.snap || !memory.initialized;
    final view = context.viewAt(state.zoom);
    final aim =
        targetAt + _lookahead(context, framing, targetAt, view, dt, snap);

    // Where the camera would be with the target exactly on its screen spot.
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
    Size view,
    double dt,
    bool snap,
  ) {
    final memory = context.memory;
    // Which entity "last frame" was measured on: a new target's distance
    // from the old one is not a speed.
    final sameTarget = identical(memory.extra[_targetKey], context.target);
    memory.extra[_targetKey] = context.target;

    // A target that does not report a velocity still has one: how far it
    // moved since last frame. Not on a snap — a teleport or a respawn is
    // not movement — and not for a jump longer than the view, which only a
    // teleport the game forgot to snap for makes.
    var velocity = context.targetVelocity;
    final previous = memory.previousTargetPosition;
    if (context.target != null &&
        velocity == Offset.zero &&
        previous != null &&
        !snap &&
        sameTarget &&
        dt > 0) {
      final moved = targetAt - previous;
      if (!_isTeleport(moved, view)) velocity = moved / dt;
    }
    memory.previousTargetPosition = targetAt;
    if (framing.lookaheadTime <= 0) {
      memory.lookaheadVelocity = Offset.zero;
      return Offset.zero;
    }
    final smoothed = snap
        ? velocity
        : Offset.lerp(
            memory.lookaheadVelocity,
            velocity,
            CameraStage.damp(framing.lookaheadSmoothing, dt),
          )!;
    // However fast the target goes, looking ahead never puts it off
    // screen: the lead is at most half the view on each axis.
    memory.lookaheadVelocity = _capped(smoothed, view, framing.lookaheadTime);
    return memory.lookaheadVelocity * framing.lookaheadTime;
  }

  static const Object _targetKey = #framingTarget;

  static bool _isTeleport(Offset moved, Size view) =>
      !view.isEmpty &&
      (moved.dx.abs() > view.width || moved.dy.abs() > view.height);

  static Offset _capped(Offset velocity, Size view, double lookaheadTime) {
    if (view.isEmpty || lookaheadTime <= 0) return velocity;
    final maxX = view.width / 2 / lookaheadTime;
    final maxY = view.height / 2 / lookaheadTime;
    return Offset(
      velocity.dx.clamp(-maxX, maxX),
      velocity.dy.clamp(-maxY, maxY),
    );
  }
}
