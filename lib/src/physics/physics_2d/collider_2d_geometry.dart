/// Where a collider really is: its shape turned, moved by its offset and
/// stretched by its entity's scale.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:just_physics_engine/just_physics_engine.dart';

import 'physics_2d_components.dart';
import '../../foundation/solid_shape_2d.dart';
import '../../ecs/ecs.dart';

/// The collider a [Collider2DComponent] stands for, in its body's own space: what
/// `Physics2DSystem` gives the simulation, what the debug outline draws, what
/// an editor puts handles on.
///
/// The saved shape is in the entity's own space; the simulated one is
/// turned by the collider's `rotation`, has its `offset` added and the
/// entity's scale applied — so a sprite and its collider grow together.
abstract final class Collider2DGeometry {
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
      CapsuleShape s => _capsule(s, place(s.center1), place(s.center2), ax, ay),
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
    Collider2DComponent collider, {
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
      case Collider2DShape.box:
        final w = math.max(collider.size.x.abs() * ax, 1e-3);
        final h = math.max(collider.size.y.abs() * ay, 1e-3);
        final r = math.min(
          collider.cornerRadius.abs() * math.min(ax, ay),
          math.min(w, h) / 2 - 1e-3,
        );
        return r > 0
            ? RoundedPolygonShape.rect(
                width: w - 2 * r,
                height: h - 2 * r,
                cornerRadius: r,
              )
            : RectangleShape(w, h);
      case Collider2DShape.circle:
        return CircleShape(
          math.max(collider.radius.abs() * math.max(ax, ay), 1e-3),
        );
      case Collider2DShape.capsule:
        final r = math.max(collider.radius.abs() * ax, 1e-3);
        final h = math.max(collider.height.abs() * ay, 2 * r);
        return CapsuleShape.vertical(height: h, radius: r);
      case Collider2DShape.polygon:
        if (collider.points.length < 3) return null;
        final points = scaled(collider.points);
        final r = collider.cornerRadius.abs() * math.min(ax, ay);
        return r > 0 ? RoundedPolygonShape(points, r) : PolygonShape(points);
      case Collider2DShape.segment:
        if (collider.points.length < 2) return null;
        final points = scaled(collider.points.take(2).toList());
        return SegmentShape(
          points[0],
          points[1],
          thickness: collider.thickness * math.max(ax, ay),
        );
      case Collider2DShape.chain:
        if (collider.points.length < 2) return null;
        return ChainShape(
          scaled(collider.points),
          loop: collider.loop,
          thickness: collider.thickness * math.max(ax, ay),
        );
      case Collider2DShape.matchShape:
        if (entity == null) return null;
        final visual = visualShapeOf(entity, definitions: definitions);
        return visual == null ? null : build(visual, sx: cx, sy: cy);
    }
  }

  /// [collider]'s collider for an entity with [transform] (none: unscaled):
  /// what the simulation gets. Null when it has no shape (see [shapeOf]).
  static CollisionShape? of(
    Collider2DComponent collider, [
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
  /// its scale): the outline of its first [SolidShape2DSource] that has one
  /// (a Circle, Capsule, Rectangle — its corners rounded as they are drawn —
  /// Polygon or Line; see [shapeOfSolid]) — and otherwise a box round
  /// anything that has a size (a sprite), the largest, sized by
  /// [definitions]. Null when it draws nothing with a size.
  static CollisionShape? visualShapeOf(
    Entity entity, {
    ComponentDefinitionRegistry? definitions,
  }) {
    for (final c in entity.components) {
      if (c is! SolidShape2DSource) continue;
      final solid = (c as SolidShape2DSource).solidShape2D;
      if (solid != null) return shapeOfSolid(solid);
    }
    final size = largestSize(entity, definitions);
    return size == null ? null : RectangleShape(size.width, size.height);
  }

  /// The collision shape of [solid], in its entity's own space: a circle, a
  /// capsule upright or lying as its box is, a box (a rounded one for
  /// rounded corners), a polygon, or a line as thick as it is drawn.
  static CollisionShape shapeOfSolid(SolidShape2D solid) {
    switch (solid) {
      case SolidCircle2D(:final radius):
        return CircleShape(math.max(radius, 1e-3));
      case SolidCapsule2D(:final width, :final height):
        final r = math.max(math.min(width, height) / 2, 1e-3);
        final half = math.max(math.max(width, height) / 2 - r, 0.0);
        return height >= width
            ? CapsuleShape(
                center1: Offset(0, -half),
                center2: Offset(0, half),
                radius: r,
              )
            : CapsuleShape(
                center1: Offset(-half, 0),
                center2: Offset(half, 0),
                radius: r,
              );
      case SolidBox2D(:final width, :final height, :final cornerRadius):
        final w = math.max(width, 1e-3), h = math.max(height, 1e-3);
        final r = math.min(cornerRadius, math.min(w, h) / 2 - 1e-3);
        return r > 0
            ? RoundedPolygonShape.rect(
                width: w - 2 * r,
                height: h - 2 * r,
                cornerRadius: r,
              )
            : RectangleShape(w, h);
      case SolidPolygon2D(:final points):
        return PolygonShape([...points]);
      case SolidLine2D(:final start, :final end, :final width):
        return SegmentShape(start, end, thickness: math.max(width, 1e-3));
    }
  }

  /// Whether mirroring [solid] about its entity's centre can change it — a
  /// polygon or a line — so that a negative scale builds its collider
  /// again; a circle, a box and a capsule are the same either way.
  static bool solidMirrors(SolidShape2D solid) =>
      solid is SolidPolygon2D || solid is SolidLine2D;

  /// The largest size among what [entity] has a size for (a sprite), as
  /// [definitions] give it — the box [visualShapeOf] falls back to; null
  /// for none.
  static Size? largestSize(
    Entity entity,
    ComponentDefinitionRegistry? definitions,
  ) {
    if (definitions == null) return null;
    Size? best;
    for (final c in entity.components) {
      if (c is Collider2DComponent || c is RigidBody2DComponent) continue;
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
  static bool isMirrorSymmetric(
    CollisionShape shape,
    Offset offset, [
    double rotation = 0,
  ]) {
    if (offset != Offset.zero || rotation != 0) return false;
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

  /// [body]'s shapes as the distance and cast tests see them — convex
  /// cores with a radius, in the world, turned with the body and moved by
  /// [shift]: a circle as one point, a capsule or segment as two, a polygon
  /// as its corners, a chain as one piece per link. As the physics engine's
  /// own overlap and cast queries take them.
  static List<ShapeProxy2D> proxiesOf(
    PhysicsBody body, {
    Offset shift = Offset.zero,
  }) {
    final c = math.cos(body.angle), s = math.sin(body.angle);
    final px = body.position.x + shift.dx, py = body.position.y + shift.dy;
    Offset at(Offset p) =>
        Offset(c * p.dx - s * p.dy + px, s * p.dx + c * p.dy + py);
    final out = <ShapeProxy2D>[];
    void add(CollisionShape shape) {
      switch (shape) {
        case CircleShape():
          out.add(ShapeProxy2D([at(shape.center)], shape.radius));
        case CapsuleShape():
          out.add(
            ShapeProxy2D([at(shape.center1), at(shape.center2)], shape.radius),
          );
        case RoundedPolygonShape():
          out.add(
            ShapeProxy2D([
              for (final v in shape.vertices) at(v),
            ], shape.cornerRadius),
          );
        case PolygonShape():
          if (shape.vertices.isNotEmpty) {
            out.add(ShapeProxy2D([for (final v in shape.vertices) at(v)], 0));
          }
        case SegmentShape():
          out.add(
            ShapeProxy2D([at(shape.point1), at(shape.point2)], shape.thickness),
          );
        case ChainShape():
          final v = shape.vertices;
          if (v.length < 2) break;
          final n = shape.loop && v.length > 2 ? v.length : v.length - 1;
          for (var i = 0; i < n; i++) {
            out.add(
              ShapeProxy2D([
                at(v[i]),
                at(v[(i + 1) % v.length]),
              ], shape.thickness),
            );
          }
        default:
          break;
      }
    }

    add(body.shape);
    body.additionalShapes.forEach(add);
    return out;
  }

  /// The mass, in kg, of a square unit of a body whose own mass is 0: water
  /// 1 m (100 units) deep, as a 3-D body is worked out from its volume. A
  /// 100 × 100 square weighs 1000 kg, as a 1 m cube does.
  static const double autoMassPerSquareUnit = 0.1;

  /// What [rigid] weighs with [shape]: nothing when it is static, its own
  /// [RigidBody2DComponent.mass] when that is set, and otherwise
  /// [autoMassPerSquareUnit] for each square unit of [shape]. A line (a
  /// segment or a chain) counts its bounds, at least a unit each way, as a
  /// 3-D shape with no volume does.
  static double massOf(RigidBody2DComponent rigid, CollisionShape shape) {
    if (rigid.isStatic) return 0.0;
    if (rigid.mass > 0) return rigid.mass;
    var area = shape.area;
    if (!(area > 0)) {
      final bounds = shape.getBounds(Offset.zero);
      area = math.max(bounds.width, 1.0) * math.max(bounds.height, 1.0);
    }
    return area * autoMassPerSquareUnit;
  }

  /// The rotational inertia of [shape] weighing [mass], about its body's
  /// origin: what turns a torque or an angular impulse into spin. Box2D
  /// works it out from the shapes it is given; the pure-Dart engine is told
  /// this, so both turn alike. A rounded polygon counts as its bounds, and a
  /// line (a segment or a chain), which has no area, as its bounds at least
  /// a unit each way — as [massOf] weighs it. Zero for no mass.
  static double inertiaOf(CollisionShape shape, double mass) {
    if (!(mass > 0)) return 0.0;
    double box(Rect b, {double least = 0}) {
      final w = math.max(b.width, least), h = math.max(b.height, least);
      final c = b.center;
      return (w * w + h * h) / 12 + c.dx * c.dx + c.dy * c.dy;
    }

    final perMass = switch (shape) {
      CircleShape s =>
        0.5 * s.radius * s.radius +
            s.center.dx * s.center.dx +
            s.center.dy * s.center.dy,
      RoundedPolygonShape s => box(s.getBounds(Offset.zero)),
      PolygonShape s =>
        _polygonInertia(s.vertices) ?? box(s.getBounds(Offset.zero)),
      CapsuleShape s => _capsuleInertia(s.center1, s.center2, s.radius),
      _ => box(shape.getBounds(Offset.zero), least: 1),
    };
    return mass * perMass;
  }

  /// A polygon's rotational inertia per unit mass about the origin; null
  /// for one with no area.
  static double? _polygonInertia(List<Offset> v) {
    var cross = 0.0, sum = 0.0;
    for (var i = 0; i < v.length; i++) {
      final a = v[i], b = v[(i + 1) % v.length];
      final c = a.dx * b.dy - a.dy * b.dx;
      cross += c;
      sum +=
          c *
          (a.dx * a.dx +
              a.dy * a.dy +
              a.dx * b.dx +
              a.dy * b.dy +
              b.dx * b.dx +
              b.dy * b.dy);
    }
    if (cross.abs() < 1e-12) return null;
    return sum / (6 * cross);
  }

  /// A capsule's rotational inertia per unit mass about the origin, as
  /// Box2D works it out: a box and two half circles.
  static double _capsuleInertia(Offset c1, Offset c2, double r) {
    final rr = r * r;
    final length = (c2 - c1).distance;
    final circle = math.pi * rr, box = 2 * r * length;
    final total = circle + box;
    if (!(total > 0)) return 0;
    final lc = 4 * r / (3 * math.pi), h = length / 2;
    final centre = (c1 + c2) / 2;
    final inertia =
        circle * (0.5 * rr + h * h + 2 * h * lc) +
        box * (4 * rr + length * length) / 12;
    return inertia / total + centre.dx * centre.dx + centre.dy * centre.dy;
  }

  /// Draws [shape] in its body's space onto [canvas] — already moved and
  /// turned to the body — with [paint].
  ///
  /// [paths] keeps each shape's outline from one call to the next: a shape
  /// never changes, so a drawer outlining the same bodies every frame (the
  /// collider debugger) lists their points into a native path only once.
  static void paint(
    Canvas canvas,
    CollisionShape shape,
    Paint paint, {
    Expando<Path>? paths,
  }) {
    Path pathOf(Path Function() make) {
      if (paths == null) return make();
      return paths[shape] ??= make();
    }

    switch (shape) {
      case CircleShape s:
        canvas.drawCircle(s.center, s.radius, paint);
      case RoundedPolygonShape s:
        // The core polygon and its rounding.
        canvas.drawPath(pathOf(() => _polygon(s.vertices)), paint);
        for (final v in s.vertices) {
          canvas.drawCircle(v, s.cornerRadius, paint);
        }
      case RectangleShape s:
        // Upright in its body's space: no path needed.
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: s.width,
            height: s.height,
          ),
          paint,
        );
      case PolygonShape s:
        canvas.drawPath(pathOf(() => _polygon(s.vertices)), paint);
      case CapsuleShape s:
        canvas.drawPath(
          pathOf(() => capsulePath(s.center1, s.center2, s.radius)),
          paint,
        );
      case SegmentShape s:
        canvas.drawLine(s.point1, s.point2, paint);
      case ChainShape s:
        canvas.drawPath(pathOf(() => _chain(s.vertices, s.loop)), paint);
    }
  }

  static Path _chain(List<Offset> vertices, bool loop) {
    final path = Path();
    if (vertices.isEmpty) return path;
    path.moveTo(vertices.first.dx, vertices.first.dy);
    for (final v in vertices.skip(1)) {
      path.lineTo(v.dx, v.dy);
    }
    if (loop) path.close();
    return path;
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

  /// [s] with its centres placed at [p1] and [p2] and its radius grown by
  /// the scale across it: its ends pushed out so its caps reach as far as
  /// the scale stretches them, as a collider's own scale stretches its
  /// height — a capsule 64 tall at a scale of 2 up it is 128 tall, not 96.
  static CapsuleShape _capsule(
    CapsuleShape s,
    Offset p1,
    Offset p2,
    double ax,
    double ay,
  ) {
    final radius = s.radius * _across(p1, p2, ax, ay);
    final before = (s.center2 - s.center1).distance;
    final d = p2 - p1;
    final after = d.distance;
    if (before < 1e-9 || after < 1e-9) {
      return CapsuleShape(center1: p1, center2: p2, radius: radius);
    }
    // Each end: the cap reached s.radius past its centre, stretched as the
    // length was; less the new radius, and never past the middle.
    final push = math.max(s.radius * after / before - radius, -after / 2);
    final out = d * (push / after);
    return CapsuleShape(center1: p1 - out, center2: p2 + out, radius: radius);
  }

  /// The scale across a capsule's axis (its placed ends [a] and [b]): its
  /// width for an upright one, its height for a lying one, the larger
  /// otherwise.
  static double _across(Offset a, Offset b, double ax, double ay) {
    if ((a.dx - b.dx).abs() < 1e-9) return ax;
    if ((a.dy - b.dy).abs() < 1e-9) return ay;
    return math.max(ax, ay);
  }
}
