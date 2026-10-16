library;

import 'package:just_dart/just_dart.dart';

/// A rotation held as Euler angles in radians — the engine's one convention,
/// `q = qY(y) · qX(x) · qZ(z)` (see [Quaternion]).
///
/// Holding angles rather than a quaternion keeps them editable and
/// continuous (a turn past 180° keeps counting); [setFromQuaternion] picks
/// the equivalent triple nearest the current one.
class EulerRotation {
  /// Rotation about X.
  double x;

  /// Rotation about Y.
  double y;

  /// Rotation about Z — the 2-D angle.
  double z;

  /// Create from angles in radians.
  EulerRotation([this.x = 0.0, this.y = 0.0, this.z = 0.0]);

  /// Whether this only turns about Z.
  bool get isPlanar => x == 0.0 && y == 0.0;

  /// Set all three angles.
  void setValues(double nx, double ny, double nz) {
    x = nx;
    y = ny;
    z = nz;
  }

  /// Set to [other].
  void setFrom(EulerRotation other) => setValues(other.x, other.y, other.z);

  /// Write this rotation as a quaternion into [out].
  void quaternionInto(Quaternion out) {
    if (isPlanar) {
      out.setRotationZ(z);
    } else {
      out.setEuler(x, y, z);
    }
  }

  /// Set from a quaternion, nearest the current angles. A rotation that is
  /// 2-D up to rounding stays exactly 2-D.
  void setFromQuaternion(Quaternion q) {
    _scratch.setValues(x, y, z);
    q.eulerInto(_scratch, hint: _scratch);
    x = _scratch.x.abs() < 1e-12 ? 0.0 : _scratch.x;
    y = _scratch.y.abs() < 1e-12 ? 0.0 : _scratch.y;
    z = _scratch.z;
  }

  static final Vector3 _scratch = Vector3.zero();

  @override
  String toString() => 'Euler($x, $y, $z)';
}
