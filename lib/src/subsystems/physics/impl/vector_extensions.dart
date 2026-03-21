part of '../physics_engine.dart';

/// Extension for math vector operations on [Offset].
extension Vector2Extension on Offset {
  /// Dot product
  double dot(Offset other) {
    return dx * other.dx + dy * other.dy;
  }

  /// Cross product (returns scalar representing Z axis)
  double cross(Offset other) {
    return dx * other.dy - dy * other.dx;
  }

  /// Right perpendicular vector
  Offset get perpendicular => Offset(-dy, dx);
}
