/// How a camera projects the world onto the screen.
///
/// Lives with the interfaces because `GameCamera` names it: the ECS layer
/// reads a camera's lens without depending on the camera subsystem.
library;

import 'dart:math' as math;

/// Straight on, or with perspective.
enum CameraProjection {
  /// Parallel lines stay parallel; size does not change with distance. How
  /// every 2-D game is drawn — the camera's zoom sets how much it sees.
  orthographic,

  /// Things further away look smaller; the field of view sets how much it
  /// sees.
  perspective,
}

/// A camera's lens: its projection and what it can see.
///
/// Distances are along the camera's forward axis (+Z in its own space; see
/// `WorldAxes`). An orthographic lens sees behind the camera too — a 2-D
/// camera sits in the plane of what it draws — so its near plane defaults
/// far behind it. A perspective lens cannot: its near plane defaults to 1.
///
/// The numbers are kept as given. What a projection is built from is
/// [safeNear], [safeFar] and [safeFieldOfView], which turn a lens that
/// cannot project — near and far equal, a perspective near at or behind the
/// camera, a field of view of 0 or π — into the nearest one that can.
class CameraLens {
  /// A lens of [projection]. [near] and [far] default to that projection's
  /// own: ±10000 for an orthographic lens, 1 to 100000 for a perspective one.
  const CameraLens({
    this.projection = CameraProjection.orthographic,
    this.fieldOfView = _sixtyDegrees,
    double? near,
    double? far,
  }) : near =
           near ??
           (projection == CameraProjection.perspective
               ? _perspectiveNear
               : -_orthographicDepth),
       far =
           far ??
           (projection == CameraProjection.perspective
               ? _perspectiveFar
               : _orthographicDepth);

  /// The 2-D default: orthographic, seeing ±10000 units in depth.
  const CameraLens.orthographic({
    this.near = -_orthographicDepth,
    this.far = _orthographicDepth,
  }) : projection = CameraProjection.orthographic,
       fieldOfView = _sixtyDegrees;

  /// A perspective lens: a 60° vertical field of view, seeing from 1 to
  /// 100000 units ahead unless told otherwise.
  const CameraLens.perspective({
    this.fieldOfView = _sixtyDegrees,
    this.near = _perspectiveNear,
    this.far = _perspectiveFar,
  }) : projection = CameraProjection.perspective;

  static const double _sixtyDegrees = math.pi / 3;
  static const double _orthographicDepth = 10000;
  static const double _perspectiveNear = 1;
  static const double _perspectiveFar = 100000;

  /// The closest a perspective near plane may be to the camera.
  static const double minPerspectiveNear = 0.01;

  /// The narrowest field of view a projection is built with, in radians
  /// (0.1°); the widest is π less this.
  static const double minFieldOfView = math.pi / 1800;

  /// Orthographic or perspective: which of [near], [far] and
  /// [fieldOfView] shape the view.
  final CameraProjection projection;

  /// Vertical field of view in radians — perspective only.
  final double fieldOfView;

  /// The nearest distance drawn.
  final double near;

  /// The furthest distance drawn.
  final double far;

  /// Whether [projection] is [CameraProjection.orthographic].
  bool get isOrthographic => projection == CameraProjection.orthographic;

  /// [near] as a projection can use it: at least [minPerspectiveNear] in
  /// front of a perspective camera, and finite.
  double get safeNear {
    if (isOrthographic) return near.isFinite ? near : -_orthographicDepth;
    return near.isFinite && near >= minPerspectiveNear
        ? near
        : (near.isFinite ? minPerspectiveNear : _perspectiveNear);
  }

  /// [far] as a projection can use it: finite and past [safeNear], since a
  /// projection whose planes meet divides by zero.
  double get safeFar {
    final n = safeNear;
    final f = far.isFinite
        ? far
        : (isOrthographic ? _orthographicDepth : _perspectiveFar);
    if (isOrthographic) return (f - n).abs() < 1e-6 ? n + 1 : f;
    return f > n ? f : math.max(n * 1000, n + 1);
  }

  /// [fieldOfView] kept strictly between 0 and π, where a perspective
  /// projection exists.
  double get safeFieldOfView {
    if (fieldOfView.isNaN) return _sixtyDegrees;
    return fieldOfView.clamp(minFieldOfView, math.pi - minFieldOfView);
  }

  /// The lens [t] of the way from [a] to [b]. Between two lenses of one
  /// projection the numbers blend; between an orthographic and a
  /// perspective lens it switches halfway.
  static CameraLens lerp(CameraLens a, CameraLens b, double t) {
    if (t <= 0 || identical(a, b)) return a;
    if (t >= 1) return b;
    if (a.projection != b.projection) return t < 0.5 ? a : b;
    if (a == b) return a;
    double mix(double x, double y) => x + (y - x) * t;
    return CameraLens(
      projection: a.projection,
      fieldOfView: mix(a.fieldOfView, b.fieldOfView),
      near: mix(a.near, b.near),
      far: mix(a.far, b.far),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CameraLens &&
      other.projection == projection &&
      other.fieldOfView == fieldOfView &&
      other.near == near &&
      other.far == far;

  @override
  int get hashCode => Object.hash(projection, fieldOfView, near, far);

  @override
  String toString() => isOrthographic
      ? 'CameraLens.orthographic($near..$far)'
      : 'CameraLens.perspective(${fieldOfView.toStringAsFixed(3)} rad, '
            '$near..$far)';
}
