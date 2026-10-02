/// Where a body's collider really is: its shape moved by the body's
/// offset and stretched by its entity's scale.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:just_physics_engine/just_physics_engine.dart';

import '../../../ecs/base/transform/transform_component.dart';
import '../../components/physics/physics_body_component.dart';

/// The collider a `PhysicsBodyComponent` stands for, in its body's own
/// space: what `PhysicsSystem` gives the simulation, what the debug outline
/// draws, what an editor puts handles on.
///
/// The saved shape is in the entity's own space; the simulated one has the
/// body's `offset` added and the entity's scale applied — so a sprite and
/// its collider grow together. Rotation is the body's own, not part of the
/// shape.
abstract final class ColliderGeometry {
  /// Smallest scale factor a collider is built with, so a transform scaled
  /// to zero cannot make a shape with no area.
  static const double minScale = 1e-3;

  /// [shape] moved by [offset] and stretched by ([sx], [sy]) — signed: a
  /// negative factor mirrors. [shape] itself when nothing changes it.
  ///
  /// A circle grows by the larger factor and a rounded corner by the
  /// smaller; a capsule's radius by the factor across its axis. A mirrored
  /// polygon or chain keeps its winding.
  static CollisionShape build(
    CollisionShape shape, {
    Offset offset = Offset.zero,
    double sx = 1,
    double sy = 1,
  }) {
    if (offset == Offset.zero && sx == 1 && sy == 1) return shape;
    sx = _atLeast(sx);
    sy = _atLeast(sy);
    final ax = sx.abs(), ay = sy.abs();
    Offset place(Offset p) =>
        Offset((p.dx + offset.dx) * sx, (p.dy + offset.dy) * sy);
    List<Offset> placeAll(List<Offset> points) {
      final out = [for (final p in points) place(p)];
      // Mirrored on one axis, the outline runs the other way round.
      return sx * sy < 0 ? out.reversed.toList() : out;
    }

    return switch (shape) {
      CircleShape s => CircleShape(
        s.radius * math.max(ax, ay),
        center: place(s.center),
      ),
      RoundedPolygonShape s => RoundedPolygonShape(
        placeAll(s.vertices),
        s.cornerRadius * math.min(ax, ay),
      ),
      RectangleShape s when offset == Offset.zero => RectangleShape(
        s.width * ax,
        s.height * ay,
      ),
      // Off-centre, a box is a polygon: the native backend builds a
      // RectangleShape as a box about the body's centre.
      PolygonShape s => PolygonShape(placeAll(s.vertices)),
      CapsuleShape s => CapsuleShape(
        center1: place(s.center1),
        center2: place(s.center2),
        radius: s.radius * _across(s.center1, s.center2, ax, ay),
      ),
      SegmentShape s => SegmentShape(
        place(s.point1),
        place(s.point2),
        thickness: s.thickness * math.max(ax, ay),
      ),
      ChainShape s => ChainShape(
        placeAll(s.vertices),
        loop: s.loop,
        thickness: s.thickness * math.max(ax, ay),
      ),
      _ => shape,
    };
  }

  /// [body]'s collider for an entity with [transform] (none: unscaled).
  static CollisionShape of(
    PhysicsBodyComponent body, [
    TransformComponent? transform,
  ]) => build(
    body.shape,
    offset: body.offset,
    sx: transform?.scale.x ?? 1,
    sy: transform?.scale.y ?? 1,
  );

  /// Whether mirroring [shape] about its body's centre leaves it as it was
  /// — then only the size of a scale matters, not its sign, and a body
  /// flipped to face the other way need not be built again.
  static bool isMirrorSymmetric(CollisionShape shape, Offset offset) {
    if (offset != Offset.zero) return false;
    return switch (shape) {
      CircleShape s => s.center == Offset.zero,
      RoundedPolygonShape() => false,
      RectangleShape() => true,
      CapsuleShape s =>
        s.center1 == -s.center2 && (s.center1.dx == 0 || s.center1.dy == 0),
      _ => false,
    };
  }

  /// [shape]'s bounds in its body's space.
  static Rect boundsOf(CollisionShape shape) => shape.getBounds(Offset.zero);

  /// Draws [shape] in its body's space onto [canvas] — already moved and
  /// turned to the body — with [paint].
  static void paint(Canvas canvas, CollisionShape shape, Paint paint) {
    switch (shape) {
      case CircleShape s:
        canvas.drawCircle(s.center, s.radius, paint);
      case RoundedPolygonShape s:
        // The core polygon and its rounding.
        canvas.drawPath(_polygon(s.vertices), paint);
        for (final v in s.vertices) {
          canvas.drawCircle(v, s.cornerRadius, paint);
        }
      case PolygonShape s:
        canvas.drawPath(_polygon(s.vertices), paint);
      case CapsuleShape s:
        canvas.drawPath(capsulePath(s.center1, s.center2, s.radius), paint);
      case SegmentShape s:
        canvas.drawLine(s.point1, s.point2, paint);
      case ChainShape s:
        final path = Path();
        if (s.vertices.isNotEmpty) {
          path.moveTo(s.vertices.first.dx, s.vertices.first.dy);
          for (final v in s.vertices.skip(1)) {
            path.lineTo(v.dx, v.dy);
          }
          if (s.loop) path.close();
        }
        canvas.drawPath(path, paint);
    }
  }

  /// The outline of a capsule from [a] to [b] of radius [r].
  static Path capsulePath(Offset a, Offset b, double r) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-9) {
      return Path()..addOval(Rect.fromCircle(center: a, radius: r));
    }
    final angle = math.atan2(d.dy, d.dx);
    final n = Offset(-d.dy, d.dx) / len * r;
    return Path()
      ..moveTo(a.dx + n.dx, a.dy + n.dy)
      ..lineTo(b.dx + n.dx, b.dy + n.dy)
      ..arcTo(
        Rect.fromCircle(center: b, radius: r),
        angle + math.pi / 2,
        -math.pi,
        false,
      )
      ..lineTo(a.dx - n.dx, a.dy - n.dy)
      ..arcTo(
        Rect.fromCircle(center: a, radius: r),
        angle - math.pi / 2,
        -math.pi,
        false,
      )
      ..close();
  }

  static Path _polygon(List<Offset> vertices) {
    final path = Path();
    if (vertices.isEmpty) return path;
    path.moveTo(vertices.first.dx, vertices.first.dy);
    for (final v in vertices.skip(1)) {
      path.lineTo(v.dx, v.dy);
    }
    return path..close();
  }

  static double _atLeast(double s) =>
      s.abs() < minScale ? (s.isNegative ? -minScale : minScale) : s;

  /// The scale across a capsule's axis: its width for an upright one, its
  /// height for a lying one, the larger otherwise.
  static double _across(Offset a, Offset b, double ax, double ay) {
    if (a.dx == b.dx) return ax;
    if (a.dy == b.dy) return ay;
    return math.max(ax, ay);
  }
}
