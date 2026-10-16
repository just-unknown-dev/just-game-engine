library;

import 'package:flutter/painting.dart' show Offset;

import '../../../components/camera/camera_manager_components.dart';
import '../camera_stage.dart';
import '../../../../subsystems/camera/camera_state.dart';

/// Body: puts the camera on its track — at the point nearest the target, or
/// wherever `pathPosition` says.
///
/// Runs after framing, so on a camera that carries both, the track has the
/// last word on position.
class DollyStage extends CameraStage<CameraDollyComponent> {
  /// Stateless; the brain registers one for [CameraDollyComponent].
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
    // On a loop, 0 and 1 are the same point: the way from 0.95 to 0.05 is
    // forward across the seam, not back round the whole track.
    final loop = path.closed;
    var gap = previous == null ? 0.0 : wanted - previous;
    if (loop) gap -= gap.roundToDouble();
    var at = previous == null || context.snap
        ? wanted
        : previous + gap * CameraStage.damp(dolly.damping, dt);
    if (loop) at -= at.floorToDouble();
    context.memory.extra[this] = at;
    return state.copyWith(position: path.pointAt(at));
  }
}

/// A polyline measured by length, so `0.5` is halfway along it however its
/// points are spaced. Shared with the editor, which draws the same track.
class DollyPath {
  /// The track through [waypoints], in world space. [closed] adds a last
  /// segment back to the first point, but only with three or more points.
  /// Measures every segment once, up front.
  DollyPath(List<Offset> waypoints, {bool closed = false})
    : closed = closed && waypoints.length > 2,
      points = [
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

  /// Whether the track is closed: a closed track was asked for and there
  /// are three or more waypoints. With fewer, the track stays open, and
  /// this is false.
  final bool closed;

  /// The track's points in order, with the first repeated at the end when
  /// the track is actually closed.
  final List<Offset> points;
  final List<double> _lengthTo = [0];

  /// Total length of the track, in world units.
  late final double length;

  /// Whether there is a track to ride: two or more points and a length
  /// above zero.
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
