/// How a camera projects the world onto the screen.
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
/// far behind it.
class CameraLens {
  const CameraLens({
    this.projection = CameraProjection.orthographic,
    this.fieldOfView = _sixtyDegrees,
    this.near = -10000,
    this.far = 10000,
  });

  /// The 2-D default: orthographic, seeing ±10000 units in depth.
  const CameraLens.orthographic({this.near = -10000, this.far = 10000})
    : projection = CameraProjection.orthographic,
      fieldOfView = _sixtyDegrees;

  /// A perspective lens: a 60° vertical field of view, seeing from 1 to
  /// 100000 units ahead unless told otherwise.
  const CameraLens.perspective({
    this.fieldOfView = _sixtyDegrees,
    this.near = 1,
    this.far = 100000,
  }) : projection = CameraProjection.perspective;

  static const double _sixtyDegrees = math.pi / 3;

  final CameraProjection projection;

  /// Vertical field of view in radians — perspective only.
  final double fieldOfView;

  /// The nearest distance drawn.
  final double near;

  /// The furthest distance drawn.
  final double far;

  bool get isOrthographic => projection == CameraProjection.orthographic;

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
