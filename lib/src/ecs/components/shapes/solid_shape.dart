import 'dart:typed_data';

/// A component whose look is a solid of known shape — a 3-D primitive such
/// as a box, a sphere or a staircase — so that a collider can take the same
/// shape without being told it twice.
///
/// A renderer package's shape components implement it (just_graphics_engine's
/// `Primitive3D`), and the engine's 3-D physics reads it (a `Collider3D`
/// set to match the shape). Plain data: nothing here draws or
/// collides. Units are the entity's own (metres in 3-D); +Y is down.
abstract interface class SolidShapeSource {
  /// Equal ([Object.==]) for as long as the shape stays the same: a reader
  /// builds its own shape again only when this changes.
  Object get solidKey;

  /// The shape as convex parts whose union it is, in its entity's own space
  /// (before the entity's scale). Empty for none.
  List<SolidPart> get solidParts;
}

/// One convex part of a [SolidShapeSource]'s shape.
sealed class SolidPart {
  const SolidPart();
}

/// A box, axis-aligned in its entity's space.
final class SolidBox extends SolidPart {
  /// A box of half-sizes [halfX], [halfY], [halfZ] centred on
  /// ([x], [y], [z]).
  const SolidBox(
    this.halfX,
    this.halfY,
    this.halfZ, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// Half its size along X.
  final double halfX;

  /// Half its size along Y.
  final double halfY;

  /// Half its size along Z.
  final double halfZ;

  /// Its centre.
  final double x, y, z;

  @override
  bool operator ==(Object other) =>
      other is SolidBox &&
      other.halfX == halfX &&
      other.halfY == halfY &&
      other.halfZ == halfZ &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(SolidBox, halfX, halfY, halfZ, x, y, z);

  @override
  String toString() => 'SolidBox($halfX, $halfY, $halfZ at $x, $y, $z)';
}

/// A sphere.
final class SolidSphere extends SolidPart {
  /// A sphere of [radius] centred on ([x], [y], [z]).
  const SolidSphere(this.radius, {this.x = 0, this.y = 0, this.z = 0});

  /// Its radius.
  final double radius;

  /// Its centre.
  final double x, y, z;

  @override
  bool operator ==(Object other) =>
      other is SolidSphere &&
      other.radius == radius &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(SolidSphere, radius, x, y, z);

  @override
  String toString() => 'SolidSphere($radius at $x, $y, $z)';
}

/// A capsule standing along Y: a cylinder [halfHeight] × 2 tall with a
/// half-sphere on each end.
final class SolidCapsule extends SolidPart {
  /// A capsule centred on ([x], [y], [z]).
  const SolidCapsule(
    this.halfHeight,
    this.radius, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// Half the length of its straight part (caps not included).
  final double halfHeight;

  /// Its radius.
  final double radius;

  /// Its centre.
  final double x, y, z;

  @override
  bool operator ==(Object other) =>
      other is SolidCapsule &&
      other.halfHeight == halfHeight &&
      other.radius == radius &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(SolidCapsule, halfHeight, radius, x, y, z);

  @override
  String toString() => 'SolidCapsule($halfHeight, $radius at $x, $y, $z)';
}

/// A cylinder standing along Y.
final class SolidCylinder extends SolidPart {
  /// A cylinder [halfHeight] × 2 tall, centred on ([x], [y], [z]).
  const SolidCylinder(
    this.halfHeight,
    this.radius, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// Half its height.
  final double halfHeight;

  /// Its radius.
  final double radius;

  /// Its centre.
  final double x, y, z;

  @override
  bool operator ==(Object other) =>
      other is SolidCylinder &&
      other.halfHeight == halfHeight &&
      other.radius == radius &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(SolidCylinder, halfHeight, radius, x, y, z);

  @override
  String toString() => 'SolidCylinder($halfHeight, $radius at $x, $y, $z)';
}

/// The convex hull of a set of points: a cone, a wedge, one piece of an
/// arch.
final class SolidHull extends SolidPart {
  /// The hull of [points] (x, y, z per point; at least four, not all in one
  /// plane).
  const SolidHull(this.points);

  /// Three floats per point.
  final Float32List points;

  /// How many points there are.
  int get length => points.length ~/ 3;

  @override
  bool operator ==(Object other) {
    if (other is! SolidHull || other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(SolidHull, Object.hashAll(points));

  @override
  String toString() => 'SolidHull($length points)';
}

/// A surface of triangles — a road swept along a path, a bridge — for what
/// stands still or is moved by hand (static and kinematic bodies): one
/// thrown about by forces needs convex parts.
final class SolidMesh extends SolidPart {
  /// Triangles [indices] (three per triangle) of [positions] (x, y, z per
  /// point).
  const SolidMesh(this.positions, this.indices);

  /// Three floats per point.
  final Float32List positions;

  /// Three per triangle.
  final Uint32List indices;

  /// How many triangles there are.
  int get triangleCount => indices.length ~/ 3;

  // Large: the same mesh only by identity; the source's key says when it
  // changed.
  @override
  bool operator ==(Object other) =>
      other is SolidMesh && identical(other.positions, positions) && identical(other.indices, indices);

  @override
  int get hashCode => Object.hash(identityHashCode(positions), identityHashCode(indices));

  @override
  String toString() => 'SolidMesh($triangleCount triangles)';
}

/// Ground as a grid of heights — a terrain: [sampleCount] by [sampleCount]
/// samples [cellSize] apart, row by row along Z, each along X, its first
/// at ([x], [y], [z]). Each height is how far *up* the ground is there
/// (+Y is down: it is subtracted). [holeHeight] or more marks a hole:
/// nothing there.
final class SolidHeightField extends SolidPart {
  const SolidHeightField(
    this.heights,
    this.sampleCount,
    this.cellSize, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// A height that marks a hole.
  static const double holeHeight = 3.0e38;

  /// Row-major heights, [sampleCount] squared of them.
  final Float32List heights;

  /// Samples along each side.
  final int sampleCount;

  /// Metres between samples.
  final double cellSize;

  /// Where its first sample is, in its entity's space.
  final double x, y, z;

  @override
  bool operator ==(Object other) =>
      other is SolidHeightField &&
      identical(other.heights, heights) &&
      other.sampleCount == sampleCount &&
      other.cellSize == cellSize &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(identityHashCode(heights), sampleCount, cellSize, x, y, z);

  @override
  String toString() => 'SolidHeightField($sampleCount × $sampleCount)';
}
