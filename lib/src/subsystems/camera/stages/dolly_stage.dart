library;

import 'package:flutter/painting.dart' show Offset;

import '../../../ecs/components/camera/camera_manager_components.dart';
import '../camera_stage.dart';
import '../camera_state.dart';

/// Body: puts the camera on its track — at the point nearest the target, or
/// wherever `pathPosition` says.
///
/// Runs after framing, so on a camera that carries both, the track has the
/// last word on position.
class DollyStage extends CameraStage<CameraDollyComponent> {
  const DollyStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.body;

  @override
  int get order => 10;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraDollyComponent dolly,
    CameraState state,
    double dt,
  ) {
    final path = DollyPath(dolly.waypoints, closed: dolly.closed);
    if (!path.isUsable) return state;

    final target = context.targetPosition;
    final wanted = dolly.autoDolly && target != null
        ? path.nearestTo(target)
        : dolly.pathPosition.clamp(0.0, 1.0).toDouble();

    final previous = context.memory.extra[this] as double?;
    final at = previous == null || context.snap
        ? wanted
        : previous + (wanted - previous) * CameraStage.damp(dolly.damping, dt);
    context.memory.extra[this] = at;
    return state.copyWith(position: path.pointAt(at));
  }
}

/// A polyline measured by length, so `0.5` is halfway along it however its
/// points are spaced. Shared with the editor, which draws the same track.
class DollyPath {
  DollyPath(List<Offset> waypoints, {this.closed = false})
    : points = [
        ...waypoints,
        if (closed && waypoints.length > 2) waypoints.first,
      ] {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
      _lengthTo.add(total);
    }
    length = total;
  }

  final bool closed;
  final List<Offset> points;
  final List<double> _lengthTo = [0];
  late final double length;

  bool get isUsable => points.length >= 2 && length > 0;

  /// The point [t] of the way along, `0`–`1` by length.
  Offset pointAt(double t) {
    if (!isUsable) return points.isEmpty ? Offset.zero : points.first;
    final want = t.clamp(0.0, 1.0) * length;
    for (var i = 1; i < points.length; i++) {
      if (want <= _lengthTo[i]) {
        final span = _lengthTo[i] - _lengthTo[i - 1];
        final f = span <= 0 ? 0.0 : (want - _lengthTo[i - 1]) / span;
        return Offset.lerp(points[i - 1], points[i], f)!;
      }
    }
    return points.last;
  }

  /// How far along, `0`–`1`, the point of the track nearest [target] is.
  double nearestTo(Offset target) {
    if (!isUsable) return 0;
    var best = 0.0;
    var bestDistance = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final ab = points[i] - a;
      final span = ab.distanceSquared;
      final f = span <= 0
          ? 0.0
          : (((target - a).dx * ab.dx + (target - a).dy * ab.dy) / span).clamp(
              0.0,
              1.0,
            );
      final distance = (a + ab * f - target).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = _lengthTo[i - 1] + (_lengthTo[i] - _lengthTo[i - 1]) * f;
      }
    }
    return best / length;
  }
}
