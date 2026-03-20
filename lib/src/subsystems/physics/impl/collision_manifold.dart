part of '../physics_engine.dart';

/// Contains information about a collision between two bodies.
class CollisionManifold {
  /// Whether a collision occurred
  final bool isColliding;

  /// The normal vector pointing from body A to body B
  final Offset normal;

  /// The depth of the penetration along the normal
  final double penetration;

  CollisionManifold({
    required this.isColliding,
    this.normal = Offset.zero,
    this.penetration = 0.0,
  });

  factory CollisionManifold.empty() {
    return CollisionManifold(isColliding: false);
  }
}
