library;

import 'dart:math' as math;

import '../../../components/camera/camera_target_components.dart';
import '../camera_stage.dart';
import '../../../../subsystems/camera/camera_state.dart';

/// Body, ahead of framing: sets the lens so a followed target group fits.
///
/// It runs first because everything after it — dead zones, the confiner —
/// is measured against the view, and the view is what this changes.
class GroupFramingStage extends CameraStage<CameraGroupFramingComponent> {
  /// Stateless; the brain registers one for [CameraGroupFramingComponent].
  const GroupFramingStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.body;

  @override
  int get order => -10;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraGroupFramingComponent framing,
    CameraState state,
    double dt,
  ) {
    final group = context.target?.getComponent<CameraTargetGroupComponent>();
    final viewport = context.viewportSize;
    if (group == null || group.resolved == 0 || viewport.isEmpty) return state;

    // The camera centres on the group's weighted centre, not the middle of
    // its box: the view must reach the box's far side from there, so a
    // heavy member off to one side doesn't push a light one off screen.
    final box = group.bounds;
    final centre = context.targetPosition ?? box.center;
    final room = 1 + framing.padding;
    final width =
        2 * math.max(centre.dx - box.left, box.right - centre.dx).abs() * room;
    final height =
        2 * math.max(centre.dy - box.top, box.bottom - centre.dy).abs() * room;
    // A group with no extent — one member, no radius — fits at any zoom, so
    // it gets the closest the shot allows.
    final fit = math.min(
      width <= 0 ? double.infinity : viewport.width / width,
      height <= 0 ? double.infinity : viewport.height / height,
    );
    final low = math.min(framing.minZoom, framing.maxZoom);
    final high = math.max(framing.minZoom, framing.maxZoom);
    final wanted = fit.clamp(low, high).toDouble();

    final previous = context.memory.extra[this] as double?;
    final zoom = previous == null || context.snap
        ? wanted
        : previous +
              (wanted - previous) * CameraStage.damp(framing.zoomDamping, dt);
    context.memory.extra[this] = zoom;
    return state.copyWith(zoom: zoom);
  }
}
