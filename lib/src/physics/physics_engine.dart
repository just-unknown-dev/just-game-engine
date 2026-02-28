/// Physics Engine
///
/// Simulates realistic movement, gravity, collision detection, and object interactions.
/// This module provides physics simulation capabilities for game objects.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../cache/cache_manager.dart';

/// Extension for math vector operations
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

/// Contains information about a collision
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

/// Main physics engine class
class PhysicsEngine {
  /// All physics bodies
  final List<PhysicsBody> _bodies = [];

  /// Global gravity
  Offset gravity = const Offset(0, 98.0); // Simple downward gravity

  /// Optional cache manager for physics caching
  CacheManager? cacheManager;

  /// Whether debug rendering is enabled
  bool debugRender = false;

  /// Initialize the physics engine
  void initialize() {
    debugPrint('Physics Engine initialized');
  }

  /// Update physics simulation
  void update(double deltaTime) {
    // Update all bodies
    for (final body in _bodies) {
      if (body.isActive) {
        if (body.isAwake) {
          // Calculate total acceleration for this frame
          Offset currentAcceleration = body.acceleration;

          // Apply gravity if enabled
          if (body.useGravity) {
            currentAcceleration += gravity;
          }

          // Check for sleeping (use currentAcceleration which includes gravity)
          if (body.velocity.distanceSquared <
                  body.sleepVelocityThreshold * body.sleepVelocityThreshold &&
              currentAcceleration.distanceSquared < 0.1) {
            body.sleepTimer += deltaTime;
            if (body.sleepTimer >= body.sleepTimeThreshold) {
              body.isAwake = false;
              body.velocity = Offset.zero;
              body.acceleration = Offset.zero;
            }
          } else {
            body.sleepTimer = 0.0;
          }

          if (body.isAwake) {
            // Semi-Implicit Euler Integration
            // 1. Update velocity
            body.velocity += currentAcceleration * deltaTime;
            body.angularVelocity += (body.torque * body.invInertia) * deltaTime;

            // Apply drag (simple linear drag)
            body.velocity *= (1.0 - body.drag * deltaTime);
            body.angularVelocity *=
                (1.0 - body.drag * deltaTime); // Add angular drag

            // 2. Update position
            body.position += body.velocity * deltaTime;
            body.angle += body.angularVelocity * deltaTime;

            // Reset acceleration for the next frame
            body.acceleration = Offset.zero;
            body.torque = 0.0;
          }
        }
      }
    }

    // Simple collision detection
    _detectCollisions();
  }

  /// Add a physics body
  void addBody(PhysicsBody body) {
    if (!_bodies.contains(body)) {
      _bodies.add(body);
    }
  }

  /// Remove a physics body
  void removeBody(PhysicsBody body) {
    _bodies.remove(body);
  }

  /// Broad-phase grid
  final SpatialGrid _grid = SpatialGrid(100.0);

  /// Detect collisions
  void _detectCollisions() {
    _grid.clear();
    for (final body in _bodies) {
      _grid.insert(body);
    }

    final potentialPairs = _grid.getPotentialCollisions();

    for (final pair in potentialPairs) {
      final bodyA = pair.a;
      final bodyB = pair.b;

      // Note: isActive and checkCollision are already filtered during grid insertion

      final manifold = bodyA.shape.getManifold(
        bodyA.position,
        bodyB.shape,
        bodyB.position,
      );

      if (manifold.isColliding) {
        _resolveCollision(bodyA, bodyB, manifold);
      }
    }
  }

  /// Resolve collision
  void _resolveCollision(
    PhysicsBody a,
    PhysicsBody b,
    CollisionManifold manifold,
  ) {
    final normal = manifold.normal;
    final penetration = manifold.penetration;

    if (penetration <= 0) return;

    // Wake bodies up
    a.isAwake = true;
    a.sleepTimer = 0.0;
    b.isAwake = true;
    b.sleepTimer = 0.0;

    // ── Positional correction (mass-proportional) ─────────────────────────
    // Push bodies apart weighted by inverse mass so heavier objects move less.
    final invMassSum = a.invMass + b.invMass;

    if (invMassSum == 0) return; // both immovable

    // Add a small correction bias so bodies are fully clear on the next frame.
    const correctionPercent = 0.8;
    const slop = 0.05; // ignore tiny overlaps to avoid jitter
    final correctionMag =
        math.max(penetration - slop, 0.0) / invMassSum * correctionPercent;
    a.position -= normal * (correctionMag * a.invMass);
    b.position += normal * (correctionMag * b.invMass);

    // ── Impulse resolution ────────────────────────────────────────────────
    final relativeVelocity =
        b.velocity - a.velocity; // Note: Velocity of B relative to A
    final velAlongNormal =
        relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;

    // velAlongNormal > 0  →  bodies already separating, nothing to do.
    if (velAlongNormal > 0) return;

    // Use the lesser restitution so collisions are never artificially springy.
    final restitution = math.min(a.restitution, b.restitution);

    final impulseValue = -(1.0 + restitution) * velAlongNormal;
    final j = impulseValue / invMassSum;

    // Apply normal impulse
    final impulse = normal * j;
    a.velocity -= impulse * a.invMass;
    b.velocity += impulse * b.invMass;

    // ── Friction (Tangent Impulse) ──────────────────────────────────────────
    var tangent = relativeVelocity - normal * relativeVelocity.dot(normal);

    final tangentLen = tangent.distance;
    if (tangentLen > 0.0001) {
      tangent = tangent / tangentLen; // normalize

      final jt = -relativeVelocity.dot(tangent) / invMassSum;

      // Coulomb friction law
      final mu = (a.friction + b.friction) / 2.0;

      // Clamp friction impulse
      double frictionImpulseScalar = jt;
      if (frictionImpulseScalar.abs() > j * mu) {
        frictionImpulseScalar =
            (frictionImpulseScalar > 0 ? 1.0 : -1.0) * j * mu;
      }

      final frictionImpulse = tangent * frictionImpulseScalar;

      a.velocity -= frictionImpulse * a.invMass;
      b.velocity += frictionImpulse * b.invMass;
    }
  }

  /// Render debug visualization
  void renderDebug(Canvas canvas, Size size) {
    if (!debugRender) return;

    for (final body in _bodies) {
      // Draw body
      final paint = Paint()
        ..color = body.isActive ? Colors.green : Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final shape = body.shape;
      if (shape is CircleShape) {
        canvas.drawCircle(body.position, shape.radius, paint);
      } else if (shape is PolygonShape) {
        final path = Path();
        if (shape.vertices.isNotEmpty) {
          path.moveTo(
            body.position.dx + shape.vertices[0].dx,
            body.position.dy + shape.vertices[0].dy,
          );
          for (int i = 1; i < shape.vertices.length; i++) {
            path.lineTo(
              body.position.dx + shape.vertices[i].dx,
              body.position.dy + shape.vertices[i].dy,
            );
          }
          path.close();
        }
        canvas.drawPath(path, paint);
      }

      // Draw velocity vector
      if (body.velocity.distance > 0) {
        final velocityPaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0;

        canvas.drawLine(
          body.position,
          body.position + body.velocity * 0.1,
          velocityPaint,
        );
      }

      // Draw center point
      canvas.drawCircle(body.position, 3, Paint()..color = Colors.red);
    }
  }

  /// Clean up physics resources
  void dispose() {
    _bodies.clear();
    debugPrint('Physics Engine disposed');
  }

  /// Get all bodies
  List<PhysicsBody> get bodies => List.unmodifiable(_bodies);

  /// ── Physics Caching (Phase 6) ────────────────────────────────────────────

  /// Caches a computationally expensive polygon shape (e.g., triangulated vertices)
  Future<void> cachePolygonShape(String cacheId, List<Offset> vertices) async {
    if (cacheManager == null || !cacheManager!.isInitialized) return;

    // Convert List<Offset> to standard JSON format
    final List<Map<String, double>> serialized = vertices
        .map((v) => {'dx': v.dx, 'dy': v.dy})
        .toList();

    await cacheManager!.setJson('physics_shape_$cacheId', serialized);
  }

  /// Retrieve a cached polygon shape
  Future<List<Offset>?> getCachedPolygonShape(String cacheId) async {
    if (cacheManager == null || !cacheManager!.isInitialized) return null;

    final data = await cacheManager!.getJson('physics_shape_$cacheId');
    if (data != null && data is List) {
      return data.map((item) {
        final map = item as Map<String, dynamic>;
        return Offset(
          (map['dx'] as num).toDouble(),
          (map['dy'] as num).toDouble(),
        );
      }).toList();
    }
    return null;
  }
}

/// Physics body
class PhysicsBody {
  /// Position
  Offset position;

  /// Velocity
  Offset velocity;

  /// Acceleration
  Offset acceleration;

  /// The physical shape used for collision detection
  CollisionShape shape;

  /// Mass (0 means infinite mass / static body)
  double mass;

  /// Inverse Mass (calculated automatically)
  double get invMass => mass > 0 ? 1.0 / mass : 0.0;

  /// Restitution (bounciness)
  double restitution;

  /// Surface Friction
  double friction;

  /// Current angle in radians
  double angle;

  /// Angular velocity (radians per second)
  double angularVelocity;

  /// Torque accumulator
  double torque;

  /// Moment of inertia
  double inertia;

  /// Inverse Inertia (calculated automatically)
  double get invInertia => inertia > 0 ? 1.0 / inertia : 0.0;

  /// Drag
  double drag;

  /// Use gravity
  bool useGravity;

  /// Is active
  bool isActive;

  /// Check collisions
  bool checkCollision;

  /// Object Sleeping: if true, physics integration happens
  bool isAwake;

  /// Object Sleeping: how long this body has been below movement threshold
  double sleepTimer;

  /// Object Sleeping: max velocity squared to be considered for sleeping
  double sleepVelocityThreshold;

  /// Object Sleeping: amount of time to stay below threshold before sleeping
  double sleepTimeThreshold;

  /// Create a physics body
  PhysicsBody({
    required this.position,
    required this.shape,
    this.velocity = Offset.zero,
    this.acceleration = Offset.zero,
    this.mass = 1.0,
    this.restitution = 0.5,
    this.friction = 0.2,
    this.angle = 0.0,
    this.angularVelocity = 0.0,
    this.torque = 0.0,
    this.inertia = 1.0,
    this.drag = 0.1,
    this.useGravity = true,
    this.isActive = true,
    this.checkCollision = true,
    this.isAwake = true,
    this.sleepTimer = 0.0,
    this.sleepVelocityThreshold = 5.0,
    this.sleepTimeThreshold = 0.5,
  });

  /// Apply force
  void applyForce(Offset force) {
    if (mass > 0) {
      acceleration += force * invMass;
    }
  }

  /// Apply torque
  void applyTorque(double applicationTorque) {
    if (inertia > 0) {
      torque += applicationTorque;
    }
  }

  /// Apply impulse
  void applyImpulse(Offset impulse) {
    velocity += impulse;
  }
}

/// Represents a rigid body in the physics simulation
class RigidBody {
  /// Mass of the rigid body
  double mass = 1.0;

  /// Apply force to the rigid body
  void applyForce(double x, double y, double z) {
    // TODO: Implement force application
  }
}

/// Handles collision detection between objects
class CollisionDetector {
  /// Check for collisions
  void detectCollisions() {
    // TODO: Implement collision detection
  }
}

/// Manages gravity and other physical forces
class ForceManager {
  /// Set gravity
  void setGravity(double x, double y, double z) {
    // TODO: Implement gravity
  }
}

/// Base class for collision shapes
abstract class CollisionShape {
  /// Check collision and return manifold
  CollisionManifold getManifold(Offset posA, CollisionShape other, Offset posB);

  /// Get the axis-aligned bounding box for this shape
  Rect getBounds(Offset position);
}

/// A circular collision shape
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

/// A convex polygonal collision shape
class PolygonShape extends CollisionShape {
  /// Vertices defined relative to the center of the body
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

/// A rectangular collision shape (simplified Polygon)
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

/// Pair of physics bodies for collision checking
class BodyPair {
  final PhysicsBody a;
  final PhysicsBody b;
  BodyPair(this.a, this.b);

  @override
  bool operator ==(Object other) =>
      other is BodyPair &&
      ((other.a == a && other.b == b) || (other.a == b && other.b == a));

  @override
  int get hashCode => a.hashCode ^ b.hashCode;
}

/// A uniform grid for broad-phase collision detection
class SpatialGrid {
  final double cellSize;
  final Map<int, List<PhysicsBody>> cells = {};

  SpatialGrid(this.cellSize);

  int _hash(int x, int y) {
    // A simple hash function for 2D grids (using prime numbers)
    return (x * 73856093) ^ ((y * 19349663) >> 1);
  }

  void clear() {
    cells.clear();
  }

  void insert(PhysicsBody body) {
    if (!body.isActive || !body.checkCollision) return;

    final bounds = body.shape.getBounds(body.position);
    final minX = (bounds.left / cellSize).floor();
    final minY = (bounds.top / cellSize).floor();
    final maxX = (bounds.right / cellSize).floor();
    final maxY = (bounds.bottom / cellSize).floor();

    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final hash = _hash(x, y);
        cells.putIfAbsent(hash, () => []).add(body);
      }
    }
  }

  /// Get potentially colliding pairs
  Set<BodyPair> getPotentialCollisions() {
    final pairs = <BodyPair>{};
    for (final bin in cells.values) {
      if (bin.length > 1) {
        for (int i = 0; i < bin.length; i++) {
          for (int j = i + 1; j < bin.length; j++) {
            pairs.add(BodyPair(bin[i], bin[j]));
          }
        }
      }
    }
    return pairs;
  }
}
