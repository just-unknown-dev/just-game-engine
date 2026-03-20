/// Mutable 2-D vector for performance-critical code paths.
///
/// Unlike Dart's [Offset], which is immutable and creates a new allocation
/// on every operation, [Vector2] is a mutable value holder.  Physics, particles,
/// and collision systems use [Vector2] on the hot path to avoid per-frame GC
/// pressure.
///
/// ```dart
/// final v = Vec2(3, 4);
/// v.addScaled(gravity, dt);   // in-place, zero allocations
/// ```
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A mutable 2-D vector.
class Vector2 {
  /// X component.
  double x;

  /// Y component.
  double y;

  /// Create a vector from components.
  Vector2(this.x, this.y);

  /// The zero vector.
  Vector2.zero() : x = 0.0, y = 0.0;

  /// Copy constructor.
  Vector2.copy(Vector2 other) : x = other.x, y = other.y;

  /// Create from a Dart [Offset].
  Vector2.fromOffset(Offset o) : x = o.dx, y = o.dy;

  // ── Conversion ──────────────────────────────────────────────────────────

  /// Convert to an immutable [Offset] (for Canvas APIs).
  Offset toOffset() => Offset(x, y);

  // ── In-place mutation (the whole point) ─────────────────────────────────

  /// Set to [other].
  void setFrom(Vector2 other) {
    x = other.x;
    y = other.y;
  }

  /// Set to ([nx], [ny]).
  void setValues(double nx, double ny) {
    x = nx;
    y = ny;
  }

  /// Set to zero.
  void setZero() {
    x = 0.0;
    y = 0.0;
  }

  /// Add [other] in-place.
  void add(Vector2 other) {
    x += other.x;
    y += other.y;
  }

  /// Subtract [other] in-place.
  void sub(Vector2 other) {
    x -= other.x;
    y -= other.y;
  }

  /// `this += other * scalar` — the most common physics operation.
  void addScaled(Vector2 other, double scalar) {
    x += other.x * scalar;
    y += other.y * scalar;
  }

  /// `this -= other * scalar`.
  void subScaled(Vector2 other, double scalar) {
    x -= other.x * scalar;
    y -= other.y * scalar;
  }

  /// Multiply both components by [scalar].
  void scale(double scalar) {
    x *= scalar;
    y *= scalar;
  }

  /// Negate both components.
  void negate() {
    x = -x;
    y = -y;
  }

  // ── Non-mutating queries ────────────────────────────────────────────────

  /// Squared length (avoids sqrt).
  double get lengthSquared => x * x + y * y;

  /// Euclidean length.
  double get length => math.sqrt(x * x + y * y);

  /// Dot product.
  double dot(Vector2 other) => x * other.x + y * other.y;

  /// 2-D cross product (returns scalar Z component).
  double cross(Vector2 other) => x * other.y - y * other.x;

  /// Distance squared to [other].
  double distanceToSquared(Vector2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  /// Distance to [other].
  double distanceTo(Vector2 other) => math.sqrt(distanceToSquared(other));

  // ── In-place transforms ─────────────────────────────────────────────────

  /// Normalise in-place. Returns the original length.
  double normalize() {
    final len = length;
    if (len > 1e-9) {
      final inv = 1.0 / len;
      x *= inv;
      y *= inv;
    }
    return len;
  }

  /// Set to the right-perpendicular of the current value: (-y, x).
  void setToPerpendicular() {
    final tmp = x;
    x = -y;
    y = tmp;
  }

  // ── Factory helpers (return new allocation — use sparingly) ─────────────

  /// Return a new perpendicular Vec2 without mutating [this].
  Vector2 perpendicular() => Vector2(-y, x);

  /// Return a normalised copy without mutating [this].
  Vector2 normalized() {
    final len = length;
    if (len > 1e-9) {
      final inv = 1.0 / len;
      return Vector2(x * inv, y * inv);
    }
    return Vector2(1, 0);
  }

  /// Create an operator-based copy.
  Vector2 operator +(Vector2 other) => Vector2(x + other.x, y + other.y);
  Vector2 operator -(Vector2 other) => Vector2(x - other.x, y - other.y);
  Vector2 operator *(double s) => Vector2(x * s, y * s);
  Vector2 operator /(double s) => Vector2(x / s, y / s);
  Vector2 operator -() => Vector2(-x, -y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vector2 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';
}
