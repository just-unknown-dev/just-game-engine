/// Where a collider really is: its shape turned, moved by its offset and
/// stretched by its entity's scale.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:just_physics_engine/just_physics_engine.dart';

import '../../../ecs/base/transform/transform_component.dart';
import '../../components/physics/physics_components_2d.dart';
import '../../components/shapes/shapes.dart';
import '../../ecs.dart';
import '../../serialization/component_definition_registry.dart';

/// The collider a [Collider2D] stands for, in its body's own space: what
/// `PhysicsSystem` gives the simulation, what the debug outline draws, what
/// an editor puts handles on.
///
/// The saved shape is in the entity's own space; the simulated one is
/// turned by the collider's `rotation`, has its `offset` added and the
/// entity's scale applied — so a sprite and its collider grow together.
abstract final class ColliderGeometry {
  /// Smallest scale factor a collider is built with, so a transform scaled
  /// to zero cannot make a shape with no area.
  static const double minScale = 1e-3;

  /// [shape] turned by [rotation] (radians), moved by [offset] and
  /// stretched by ([sx], [sy]) — signed: a negative factor mirrors. [shape]
  /// itself when nothing changes it.
  ///
  /// A circle grows by the larger factor and a rounded corner by the
  /// smaller; a capsule's radius by the factor across its axis. A mirrored
  /// polygon or chain keeps its winding.
  static CollisionShape build(
    CollisionShape shape, {
    Offset offset = Offset.zero,
    double rotation = 0,
    double sx = 1,
    double sy = 1,
  }) {
    if (offset == Offset.zero && rotation == 0 && sx == 1 && sy == 1) {
      return shape;
    }
    sx = _atLeast(sx);
    sy = _atLeast(sy);
    final ax = sx.abs(), ay = sy.abs();
    final cos = math.cos(rotation), sin = math.sin(rotation);
    Offset place(Offset p) {
      final x = p.dx * cos - p.dy * sin + offset.dx;
      final y = p.dx * sin + p.dy * cos + offset.dy;
      return Offset(x * sx, y * sy);
    }

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
      RectangleShape s when offset == Offset.zero && rotation == 0 =>
        RectangleShape(s.width * ax, s.height * ay),
      // Off-centre or turned, a box is a polygon: the native backend builds
      // a RectangleShape as an upright box about the body's centre.
      PolygonShape s => PolygonShape(placeAll(s.vertices)),
      CapsuleShape s => CapsuleShape(
        center1: place(s.center1),
        center2: place(s.center2),
        radius: s.radius * _across(place(s.center1), place(s.center2), ax, ay),
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

  /// [collider]'s shape in its own space, with its own scale but before its
  /// rotation and offset; null when it has none — a polygon of fewer than
  /// three points, a collider matching the shape of an entity that draws
  /// none. A collider matching its entity's shape needs the [entity] (and
  /// the [definitions] to size a sprite or anything else by).
  static CollisionShape? shapeOf(
    Collider2D collider, {
    Entity? entity,
    ComponentDefinitionRegistry? definitions,
  }) {
    final cx = _atLeast(collider.scale.x), cy = _atLeast(collider.scale.y);
    final ax = cx.abs(), ay = cy.abs();
    List<Offset> scaled(List<Offset> points) {
      final out = [for (final p in points) Offset(p.dx * cx, p.dy * cy)];
      return cx * cy < 0 ? out.reversed.toList() : out;
    }

    switch (collider.shape) {
      case ColliderShape2D.box:
        final w = math.max(collider.size.x.abs() * ax, 1e-3);
        final h = math.max(collider.size.y.abs() * ay, 1e-3);
        final r = math.min(collider.cornerRadius.abs() * math.min(ax, ay), math.min(w, h) / 2 - 1e-3);
        return r > 0
            ? RoundedPolygonShape.rect(width: w - 2 * r, height: h - 2 * r, cornerRadius: r)
            : RectangleShape(w, h);
      case ColliderShape2D.circle:
        return CircleShape(math.max(collider.radius.abs() * math.max(ax, ay), 1e-3));
      case ColliderShape2D.capsule:
        final r = math.max(collider.radius.abs() * ax, 1e-3);
        final h = math.max(collider.height.abs() * ay, 2 * r);
        return CapsuleShape.vertical(height: h, radius: r);
      case ColliderShape2D.polygon:
        if (collider.points.length < 3) return null;
        final points = scaled(collider.points);
        final r = collider.cornerRadius.abs() * math.min(ax, ay);
        return r > 0 ? RoundedPolygonShape(points, r) : PolygonShape(points);
      case ColliderShape2D.segment:
        if (collider.points.length < 2) return null;
        final points = scaled(collider.points.take(2).toList());
        return SegmentShape(points[0], points[1], thickness: collider.thickness * math.max(ax, ay));
      case ColliderShape2D.chain:
        if (collider.points.length < 2) return null;
        return ChainShape(
          scaled(collider.points),
          loop: collider.loop,
          thickness: collider.thickness * math.max(ax, ay),
        );
      case ColliderShape2D.matchShape:
        if (entity == null) return null;
        final visual = visualShapeOf(entity, definitions: definitions);
        return visual == null ? null : build(visual, sx: cx, sy: cy);
    }
  }

  /// [collider]'s collider for an entity with [transform] (none: unscaled):
  /// what the simulation gets. Null when it has no shape (see [shapeOf]).
  static CollisionShape? of(
    Collider2D collider, [
    TransformComponent? transform,
    Entity? entity,
    ComponentDefinitionRegistry? definitions,
  ]) {
    final shape = shapeOf(collider, entity: entity, definitions: definitions);
    if (shape == null) return null;
    return build(
      shape,
      offset: collider.offset,
      rotation: collider.rotation,
      sx: transform?.scale.x ?? 1,
      sy: transform?.scale.y ?? 1,
    );
  }

  /// The shape that covers what [entity] draws, in its own space (before
  /// its scale): a circle for a Circle, a capsule for a Capsule, the box of
  /// a Rectangle (its corners rounded as they are drawn), the polygon of a
  /// Polygon, the line of a Line — and a box round anything else that has a
  /// size (a sprite), the largest, sized by [definitions]. Null when it
  /// draws nothing with a size.
  static CollisionShape? visualShapeOf(
    Entity entity, {
    ComponentDefinitionRegistry? definitions,
  }) {
    for (final c in entity.components) {
      switch (c) {
        case CircleComponent v:
          return CircleShape(math.max(v.radius, 1e-3));
        case CapsuleComponent v:
          final r = math.max(math.min(v.width, v.height) / 2, 1e-3);
          final half = math.max(math.max(v.width, v.height) / 2 - r, 0.0);
          return v.height >= v.width
              ? CapsuleShape(center1: Offset(0, -half), center2: Offset(0, half), radius: r)
              : CapsuleShape(center1: Offset(-half, 0), center2: Offset(half, 0), radius: r);
        case RectangleComponent v:
          final w = math.max(v.width, 1e-3), h = math.max(v.height, 1e-3);
          final r = math.min(v.cornerRadius, math.min(w, h) / 2 - 1e-3);
          return r > 0
              ? RoundedPolygonShape.rect(width: w - 2 * r, height: h - 2 * r, cornerRadius: r)
              : RectangleShape(w, h);
        case PolygonComponent v when v.vertices.length >= 3:
          return PolygonShape([...v.vertices]);
        case LineComponent v:
          return SegmentShape(v.start, v.end, thickness: math.max(v.strokeWidth, 1e-3));
      }
    }
    final size = _largestSize(entity, definitions);
    return size == null ? null : RectangleShape(size.width, size.height);
  }

  /// Equal for as long as [visualShapeOf] would give the same shape — what
  /// the physics system compares to know a matching collider changed.
  static Object? visualKeyOf(
    Entity entity, {
    ComponentDefinitionRegistry? definitions,
  }) {
    for (final c in entity.components) {
      switch (c) {
        case CircleComponent v:
          return ('circle', v.radius);
        case CapsuleComponent v:
          return ('capsule', v.width, v.height);
        case RectangleComponent v:
          return ('box', v.width, v.height, v.cornerRadius);
        case PolygonComponent v when v.vertices.length >= 3:
          return ('polygon', Object.hashAll(v.vertices), v.vertices.length);
        case LineComponent v:
          return ('line', v.start, v.end, v.strokeWidth);
      }
    }
    final size = _largestSize(entity, definitions);
    return size == null ? null : ('size', size.width, size.height);
  }

  static Size? _largestSize(Entity entity, ComponentDefinitionRegistry? definitions) {
    if (definitions == null) return null;
    Size? best;
    for (final c in entity.components) {
      if (c is Collider2D || c is RigidBody2D) continue;
      final size = definitions.definitionFor(c)?.extent?.sizeOf(c);
      if (size == null || size.width <= 0 || size.height <= 0) continue;
      if (best == null || size.width * size.height > best.width * best.height) {
        best = size;
      }
    }
    return best;
  }

  /// Whether mirroring [shape] about its body's centre leaves it as it was
  /// — then only the size of a scale matters, not its sign, and a body
  /// flipped to face the other way need not be built again.
  static bool isMirrorSymmetric(CollisionShape shape, Offset offset, [double rotation = 0]) {
    if (offset != Offset.zero || rotation != 0) return false;
    return switch (shape) {
      CircleShape s => s.center == Offset.zero,
      RoundedPolygonShape() => false,
      RectangleShape() => true,
      CapsuleShape s => s.center1 == -s.center2 && (s.center1.dx == 0 || s.center1.dy == 0),
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

  /// The scale across a capsule's axis (its placed ends [a] and [b]): its
  /// width for an upright one, its height for a lying one, the larger
  /// otherwise.
  static double _across(Offset a, Offset b, double ax, double ay) {
    if ((a.dx - b.dx).abs() < 1e-9) return ax;
    if ((a.dy - b.dy).abs() < 1e-9) return ay;
    return math.max(ax, ay);
  }
}
