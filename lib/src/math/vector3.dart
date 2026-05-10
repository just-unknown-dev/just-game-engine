/// Mutable 3-D vector for performance-critical code paths.
///
/// Unlike Dart's [Offset], which is immutable and creates a new allocation
/// on every operation, [Vector3] is a mutable value holder.  Physics, particles,
/// and collision systems use [Vector3] on the hot path to avoid per-frame GC
/// pressure.
///
/// The z-axis is ignored by the 2-D Canvas renderer (use [toOffset] to project
/// to XY).  It carries depth/world-Z for future 3-D rendering.
///
/// ```dart
/// final v = Vector3(3, 4, 0);
/// v.addScaled(gravity, dt);   // in-place, zero allocations
/// ```
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A mutable 3-D vector.
class Vector3 {
  /// X component.
  double x;

  /// Y component.
  double y;

  /// Z component.
  double z;

  /// Create a vector from components.
  Vector3(this.x, this.y, this.z);

  /// The zero vector.
  Vector3.zero() : x = 0.0, y = 0.0, z = 0.0;

  /// Copy constructor.
  Vector3.copy(Vector3 other) : x = other.x, y = other.y, z = other.z;

  /// Create from 2-D components with z = 0 (convenience for 2-D migration).
  Vector3.fromXY(this.x, this.y) : z = 0.0;

  /// Create from a Dart [Offset] with z = 0.
  Vector3.fromOffset(Offset o) : x = o.dx, y = o.dy, z = 0.0;

  // ── Conversion ──────────────────────────────────────────────────────────

  /// Project to an immutable [Offset] by discarding z (for Canvas APIs).
  Offset toOffset() => Offset(x, y);

  // ── In-place mutation (the whole point) ─────────────────────────────────

  /// Set to [other].
  void setFrom(Vector3 other) {
    x = other.x;
    y = other.y;
    z = other.z;
  }

  /// Set to ([nx], [ny], [nz]).
  void setValues(double nx, double ny, double nz) {
    x = nx;
    y = ny;
    z = nz;
  }

  /// Set to zero.
  void setZero() {
    x = 0.0;
    y = 0.0;
    z = 0.0;
  }

  /// Add [other] in-place.
  void add(Vector3 other) {
    x += other.x;
    y += other.y;
    z += other.z;
  }

  /// Subtract [other] in-place.
  void sub(Vector3 other) {
    x -= other.x;
    y -= other.y;
    z -= other.z;
  }

  /// `this += other * scalar` — the most common physics operation.
  void addScaled(Vector3 other, double scalar) {
    x += other.x * scalar;
    y += other.y * scalar;
    z += other.z * scalar;
  }

  /// `this -= other * scalar`.
  void subScaled(Vector3 other, double scalar) {
    x -= other.x * scalar;
    y -= other.y * scalar;
    z -= other.z * scalar;
  }

  /// Multiply all components by [scalar].
  void scale(double scalar) {
    x *= scalar;
    y *= scalar;
    z *= scalar;
  }

  /// Negate all components.
  void negate() {
    x = -x;
    y = -y;
    z = -z;
  }

  // ── Non-mutating queries ────────────────────────────────────────────────

  /// Squared length (avoids sqrt).
  double get lengthSquared => x * x + y * y + z * z;

  /// Euclidean length.
  double get length => math.sqrt(x * x + y * y + z * z);

  /// Dot product.
  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;

  /// Cross product (returns a new vector).
  Vector3 cross(Vector3 other) => Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// Distance squared to [other].
  double distanceToSquared(Vector3 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return dx * dx + dy * dy + dz * dz;
  }

  /// Distance to [other].
  double distanceTo(Vector3 other) => math.sqrt(distanceToSquared(other));

  // ── In-place transforms ─────────────────────────────────────────────────

  /// Normalise in-place. Returns the original length.
  double normalize() {
    final len = length;
    if (len > 1e-9) {
      final inv = 1.0 / len;
      x *= inv;
      y *= inv;
      z *= inv;
    }
    return len;
  }

  /// Return a normalised copy without mutating [this].
  Vector3 normalized() {
    final len = length;
    if (len > 1e-9) {
      final inv = 1.0 / len;
      return Vector3(x * inv, y * inv, z * inv);
    }
    return Vector3(1, 0, 0);
  }

  // ── Factory helpers (return new allocation — use sparingly) ─────────────

  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) => Vector3(x - other.x, y - other.y, z - other.z);
  Vector3 operator *(double s) => Vector3(x * s, y * s, z * s);
  Vector3 operator /(double s) => Vector3(x / s, y / s, z / s);
  Vector3 operator -() => Vector3(-x, -y, -z);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vector3 && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}
