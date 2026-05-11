library;

import 'dart:math' as math;

import '../../ecs.dart';
import 'package:just_dart/just_dart.dart';

/// Velocity component — linear velocity in 3-D world space.
///
/// For 2-D entities only x and y are used; z defaults to 0.
/// All mutation helpers operate in-place on the mutable [Vector3] to avoid
/// per-frame GC allocations.
class VelocityComponent extends Component {
  /// Velocity vector (units per second).
  Vector3 velocity;

  /// Maximum speed (0 = unlimited).
  double maxSpeed;

  /// Create a velocity component.
  VelocityComponent({Vector3? velocity, this.maxSpeed = 0.0})
    : velocity = velocity ?? Vector3.zero();

  /// Current speed (magnitude of [velocity]).
  double get speed => velocity.length;

  /// Set velocity from a 2-D angle and magnitude.  z is set to 0.
  void setFromAngle(double angle, double magnitude) {
    velocity.x = magnitude * math.cos(angle);
    velocity.y = magnitude * math.sin(angle);
    velocity.z = 0.0;
  }

  /// Clamp velocity to [maxSpeed] in-place (zero allocations).
  void clampToMaxSpeed() {
    if (maxSpeed > 0 && speed > maxSpeed) {
      velocity.scale(maxSpeed / speed);
    }
  }

  /// `velocity += force * dt` in-place.
  void addScaled(Vector3 force, double dt) => velocity.addScaled(force, dt);

  /// `velocity *= factor` in-place.
  void scale(double factor) => velocity.scale(factor);

  /// Set x/y velocity from raw doubles.  2-D fast path; z is unchanged.
  void setVelocityXY(double vx, double vy) {
    velocity.x = vx;
    velocity.y = vy;
  }

  /// Set x/y/z velocity from raw doubles.
  void setVelocityXYZ(double vx, double vy, double vz) =>
      velocity.setValues(vx, vy, vz);

  @override
  String toString() => 'Velocity($velocity)';
}
