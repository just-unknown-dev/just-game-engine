part of '../physics_engine.dart';

/// Base class for collision shapes.
abstract class CollisionShape {
  /// Check collision and return manifold.
  CollisionManifold getManifold(Offset posA, CollisionShape other, Offset posB);

  /// Get the axis-aligned bounding box for this shape.
  Rect getBounds(Offset position);
}

/// A circular collision shape.
class CircleShape extends CollisionShape {
  final double radius;

  CircleShape(this.radius);

  @override
  CollisionManifold getManifold(
    Offset posA,
    CollisionShape other,
    Offset posB,
  ) {
    if (other is CircleShape) {
      final delta = posB - posA;
      final distance = delta.distance;
      final totalRadius = radius + other.radius;

      if (distance < totalRadius) {
        final penetration = totalRadius - distance;
        final normal = distance > 0 ? delta / distance : const Offset(1, 0);
        return CollisionManifold(
          isColliding: true,
          normal: normal,
          penetration: penetration,
        );
      }
    }
    // Polygon collisions to be handled below
    return CollisionManifold.empty();
  }

  @override
  Rect getBounds(Offset position) {
    return Rect.fromCircle(center: position, radius: radius);
  }
}

/// A convex polygonal collision shape using SAT (Separating Axis Theorem).
class PolygonShape extends CollisionShape {
  /// Vertices defined relative to the center of the body.
  List<Offset> vertices;

  PolygonShape(this.vertices);

  @override
  CollisionManifold getManifold(
    Offset posA,
    CollisionShape other,
    Offset posB,
  ) {
    if (other is PolygonShape) {
      return _satPolygonVsPolygon(posA, this, posB, other);
    } else if (other is CircleShape) {
      // Invert the result so normal points A->B
      final manifold = _satCircleVsPolygon(posB, other, posA, this);
      return CollisionManifold(
        isColliding: manifold.isColliding,
        normal: -manifold.normal,
        penetration: manifold.penetration,
      );
    }
    return CollisionManifold.empty();
  }

  @override
  Rect getBounds(Offset position) {
    if (vertices.isEmpty) return Rect.zero;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final v in vertices) {
      final px = position.dx + v.dx;
      final py = position.dy + v.dy;
      if (px < minX) minX = px;
      if (py < minY) minY = py;
      if (px > maxX) maxX = px;
      if (py > maxY) maxY = py;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  CollisionManifold _satPolygonVsPolygon(
    Offset posA,
    PolygonShape polyA,
    Offset posB,
    PolygonShape polyB,
  ) {
    double minPenetration = double.infinity;
    Offset bestNormal = Offset.zero;

    // Test axes from polyA
    for (int i = 0; i < polyA.vertices.length; i++) {
      int j = (i + 1) % polyA.vertices.length;
      final edge = (polyA.vertices[j] + posA) - (polyA.vertices[i] + posA);
      final axis = edge.perpendicular;
      final distance = axis.distance;
      if (distance == 0) continue;
      final normal = axis / distance; // normalize

      final overlap = _getOverlapOnAxis(polyA, posA, polyB, posB, normal);
      if (overlap == null) {
        return CollisionManifold.empty(); // Separating axis found
      }
      if (overlap < minPenetration) {
        minPenetration = overlap;
        bestNormal = normal;
      }
    }

    // Test axes from polyB
    for (int i = 0; i < polyB.vertices.length; i++) {
      int j = (i + 1) % polyB.vertices.length;
      final edge = (polyB.vertices[j] + posB) - (polyB.vertices[i] + posB);
      final axis = edge.perpendicular;
      final distance = axis.distance;
      if (distance == 0) continue;
      final normal = axis / distance; // normalize

      final overlap = _getOverlapOnAxis(polyA, posA, polyB, posB, normal);
      if (overlap == null) {
        return CollisionManifold.empty(); // Separating axis found
      }
      if (overlap < minPenetration) {
        minPenetration = overlap;
        bestNormal = normal;
      }
    }

    // Ensure normal points from A to B
    if (bestNormal.dot(posB - posA) < 0) {
      bestNormal = -bestNormal;
    }

    return CollisionManifold(
      isColliding: true,
      normal: bestNormal,
      penetration: minPenetration,
    );
  }

  CollisionManifold _satCircleVsPolygon(
    Offset center,
    CircleShape circle,
    Offset polyPos,
    PolygonShape poly,
  ) {
    double minPenetration = double.infinity;
    Offset bestNormal = Offset.zero;

    // Find the polygon vertex closest to the circle center
    Offset closestVertex = poly.vertices[0] + polyPos;
    double minDistanceSq = (closestVertex - center).distanceSquared;
    for (int i = 1; i < poly.vertices.length; i++) {
      final v = poly.vertices[i] + polyPos;
      final distSq = (v - center).distanceSquared;
      if (distSq < minDistanceSq) {
        minDistanceSq = distSq;
        closestVertex = v;
      }
    }

    // Axis from closest vertex to circle center
    Offset circleAxis = center - closestVertex;
    if (circleAxis.distanceSquared > 0) {
      final normal = circleAxis / circleAxis.distance;
      final overlap = _getOverlapOnAxisCircle(
        poly,
        polyPos,
        center,
        circle.radius,
        normal,
      );
      if (overlap == null) return CollisionManifold.empty();

      minPenetration = overlap;
      bestNormal = normal;
    }

    // Test axes from polygon
    for (int i = 0; i < poly.vertices.length; i++) {
      int j = (i + 1) % poly.vertices.length;
      final edge = (poly.vertices[j] + polyPos) - (poly.vertices[i] + polyPos);
      final axis = edge.perpendicular;
      final distance = axis.distance;
      if (distance == 0) continue;
      final normal = axis / distance;

      final overlap = _getOverlapOnAxisCircle(
        poly,
        polyPos,
        center,
        circle.radius,
        normal,
      );
      if (overlap == null) return CollisionManifold.empty();

      if (overlap < minPenetration) {
        minPenetration = overlap;
        bestNormal = normal;
      }
    }

    if (bestNormal.dot(polyPos - center) < 0) {
      bestNormal = -bestNormal;
    }

    return CollisionManifold(
      isColliding: true,
      normal: bestNormal,
      penetration: minPenetration,
    );
  }

  double? _getOverlapOnAxis(
    PolygonShape polyA,
    Offset posA,
    PolygonShape polyB,
    Offset posB,
    Offset axis,
  ) {
    final projA = _projectPolygon(polyA, posA, axis);
    final projB = _projectPolygon(polyB, posB, axis);

    if (projA[0] > projB[1] || projB[0] > projA[1]) return null;

    final overlap1 = projA[1] - projB[0];
    final overlap2 = projB[1] - projA[0];
    return math.min(overlap1, overlap2);
  }

  double? _getOverlapOnAxisCircle(
    PolygonShape poly,
    Offset polyPos,
    Offset circleCenter,
    double radius,
    Offset axis,
  ) {
    final projPoly = _projectPolygon(poly, polyPos, axis);
    final centerProj = circleCenter.dot(axis);
    final projCircle = [centerProj - radius, centerProj + radius];

    if (projPoly[0] > projCircle[1] || projCircle[0] > projPoly[1]) return null;

    final overlap1 = projPoly[1] - projCircle[0];
    final overlap2 = projCircle[1] - projPoly[0];
    return math.min(overlap1, overlap2);
  }

  List<double> _projectPolygon(PolygonShape poly, Offset pos, Offset axis) {
    double min = double.infinity;
    double max = double.negativeInfinity;
    for (final v in poly.vertices) {
      final proj = (v + pos).dot(axis);
      if (proj < min) min = proj;
      if (proj > max) max = proj;
    }
    return [min, max];
  }
}

/// A rectangular collision shape (simplified Polygon).
class RectangleShape extends PolygonShape {
  final double width;
  final double height;

  RectangleShape(this.width, this.height)
    : super([
        Offset(-width / 2, -height / 2),
        Offset(width / 2, -height / 2),
        Offset(width / 2, height / 2),
        Offset(-width / 2, height / 2),
      ]);
}
