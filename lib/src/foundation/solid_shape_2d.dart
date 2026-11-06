import 'dart:ui' show Offset;

/// A 2-D component whose look is an outline of known shape — a circle, a
/// box, a polygon — so that a collider can take the same shape without
/// being told it twice: the 2-D twin of `SolidShapeSource`.
///
/// The engine's 2-D shape components implement it (`Circle2DComponent`,
/// `Rectangle2DComponent` and the rest), and its 2-D physics reads it (a
/// `Collider2DComponent` set to match the shape). Plain data: nothing here
/// draws or collides. Units are the entity's own; +Y is down.
abstract interface class SolidShape2DSource {
  /// Its outline, in its entity's own space (before the entity's scale);
  /// null for none — a polygon of fewer than three points.
  ///
  /// Equal ([Object.==]) for as long as the outline stays the same: a reader
  /// builds its own shape again only when this changes. The engine's shapes
  /// give the same object back while nothing changed ([SolidCircle2D.reuse]
  /// and the rest), so asking every step makes nothing.
  SolidShape2D? get solidShape2D;
}

/// The outline of a [SolidShape2DSource], centred on its entity.
sealed class SolidShape2D {
  const SolidShape2D();
}

/// A circle of [radius].
final class SolidCircle2D extends SolidShape2D {
  /// A circle of [radius].
  const SolidCircle2D(this.radius);

  /// [last] when it is a circle of [radius] already, else a new one.
  static SolidCircle2D reuse(SolidCircle2D? last, double radius) =>
      last != null && last.radius == radius ? last : SolidCircle2D(radius);

  /// Its radius.
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is SolidCircle2D && other.radius == radius;

  @override
  int get hashCode => Object.hash(SolidCircle2D, radius);

  @override
  String toString() => 'SolidCircle2D($radius)';
}

/// A capsule filling a [width] × [height] box: upright when it is taller
/// than wide, lying otherwise, its ends rounded by half the shorter side.
final class SolidCapsule2D extends SolidShape2D {
  /// A capsule [width] wide and [height] tall.
  const SolidCapsule2D(this.width, this.height);

  /// [last] when it is a capsule of this size already, else a new one.
  static SolidCapsule2D reuse(
    SolidCapsule2D? last,
    double width,
    double height,
  ) => last != null && last.width == width && last.height == height
      ? last
      : SolidCapsule2D(width, height);

  /// Its size across and down.
  final double width, height;

  @override
  bool operator ==(Object other) =>
      other is SolidCapsule2D && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(SolidCapsule2D, width, height);

  @override
  String toString() => 'SolidCapsule2D($width × $height)';
}

/// A [width] × [height] box, its corners rounded by [cornerRadius].
final class SolidBox2D extends SolidShape2D {
  /// A box [width] wide and [height] tall.
  const SolidBox2D(this.width, this.height, {this.cornerRadius = 0});

  /// [last] when it is this box already, else a new one.
  static SolidBox2D reuse(
    SolidBox2D? last,
    double width,
    double height,
    double cornerRadius,
  ) =>
      last != null &&
          last.width == width &&
          last.height == height &&
          last.cornerRadius == cornerRadius
      ? last
      : SolidBox2D(width, height, cornerRadius: cornerRadius);

  /// Its size across and down.
  final double width, height;

  /// How far its corners are rounded.
  final double cornerRadius;

  @override
  bool operator ==(Object other) =>
      other is SolidBox2D &&
      other.width == width &&
      other.height == height &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(SolidBox2D, width, height, cornerRadius);

  @override
  String toString() => 'SolidBox2D($width × $height, r $cornerRadius)';
}

/// The polygon through [points] (three or more).
final class SolidPolygon2D extends SolidShape2D {
  /// The polygon through [points], copied.
  SolidPolygon2D(List<Offset> points) : points = List.unmodifiable(points);

  /// [last] when it runs through [points] already, else a new one; null for
  /// fewer than three points. [points] may be changed in place later: it is
  /// compared point by point, and copied.
  static SolidPolygon2D? reuse(SolidPolygon2D? last, List<Offset> points) {
    if (points.length < 3) return null;
    if (last != null && _same(last.points, points)) return last;
    return SolidPolygon2D(points);
  }

  /// Its corners, in order.
  final List<Offset> points;

  static bool _same(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is SolidPolygon2D && _same(other.points, points);

  @override
  int get hashCode => Object.hash(SolidPolygon2D, Object.hashAll(points));

  @override
  String toString() => 'SolidPolygon2D(${points.length} points)';
}

/// A line from [start] to [end], [width] thick.
final class SolidLine2D extends SolidShape2D {
  /// A line from [start] to [end].
  const SolidLine2D(this.start, this.end, this.width);

  /// [last] when it is this line already, else a new one.
  static SolidLine2D reuse(
    SolidLine2D? last,
    Offset start,
    Offset end,
    double width,
  ) =>
      last != null &&
          last.start == start &&
          last.end == end &&
          last.width == width
      ? last
      : SolidLine2D(start, end, width);

  /// Its ends.
  final Offset start, end;

  /// How thick it is.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is SolidLine2D &&
      other.start == start &&
      other.end == end &&
      other.width == width;

  @override
  int get hashCode => Object.hash(SolidLine2D, start, end, width);

  @override
  String toString() => 'SolidLine2D($start → $end, $width)';
}
