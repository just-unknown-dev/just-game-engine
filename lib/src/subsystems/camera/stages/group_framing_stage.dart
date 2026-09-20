library;

import 'dart:math' as math;

import '../../../ecs/components/camera/camera_target_components.dart';
import '../camera_stage.dart';
import '../camera_state.dart';

/// Body, ahead of framing: sets the lens so a followed target group fits.
///
/// It runs first because everything after it — dead zones, the confiner —
/// is measured against the view, and the view is what this changes.
class GroupFramingStage extends CameraStage<CameraGroupFramingComponent> {
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

    final room = 1 + framing.padding;
    final width = group.bounds.width * room;
    final height = group.bounds.height * room;
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
