/// Physics Engine
///
/// Simulates realistic movement, gravity, collision detection, and object interactions.
/// This module provides physics simulation capabilities for game objects.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../math/vector2.dart';
import '../../memory/cache_manager.dart';

part 'impl/vector_extensions.dart';
part 'impl/collision_manifold.dart';
part 'impl/collision_shapes.dart';
part 'impl/physics_body.dart';
part 'impl/spatial_grid.dart';

/// Main physics engine class
class PhysicsEngine {
  /// All physics bodies
  final List<PhysicsBody> _bodies = [];

  /// Global gravity vector.
  final Vector2 gravity = Vector2(0, 98.0);

  /// Optional cache manager for physics caching
  CacheManager? cacheManager;

  /// Whether debug rendering is enabled
  bool debugRender = false;

  /// Initialize the physics engine
  void initialize() {
    debugPrint('Physics Engine initialized');
  }

  // ── Scratch vectors for the update loop (avoids per-frame allocation) ──
  final Vector2 _accel = Vector2.zero();

  int _lastPotentialPairCount = 0;
  int _lastResolvedCollisionCount = 0;
  int _lastAwakeBodyCount = 0;
  int _lastBroadphaseDirtyBodyCount = 0;
  int _lastTrackedCellCount = 0;
  double _lastStepMs = 0.0;

  // Persistent Stopwatch instance — reused every frame to avoid heap allocation.
  final Stopwatch _stepStopwatch = Stopwatch();

  /// Update physics simulation
  void update(double deltaTime) {
    _stepStopwatch
      ..reset()
      ..start();
    var awakeBodyCount = 0;
    _lastResolvedCollisionCount = 0;

    // Update all bodies
    for (final body in _bodies) {
      if (body.isActive) {
        if (body.isAwake) {
          awakeBodyCount++;
          // Calculate total acceleration for this frame (in-place)
          _accel.setFrom(body.acceleration);
          if (body.useGravity) {
            _accel.add(gravity);
          }

          // Check for sleeping
          if (body.velocity.lengthSquared <
                  body.sleepVelocityThreshold * body.sleepVelocityThreshold &&
              _accel.lengthSquared < 0.1) {
            body.sleepTimer += deltaTime;
            if (body.sleepTimer >= body.sleepTimeThreshold) {
              body.isAwake = false;
              body.velocity.setZero();
              body.acceleration.setZero();
            }
          } else {
            body.sleepTimer = 0.0;
          }

          if (body.isAwake) {
            // Semi-Implicit Euler Integration — all in-place Vec2 ops
            // 1. Update velocity: v += accel * dt
            body.velocity.addScaled(_accel, deltaTime);
            body.angularVelocity +=
                (body.torque * body.inverseInertia) * deltaTime;

            // Apply drag (simple linear drag)
            final dragFactor = 1.0 - body.drag * deltaTime;
            body.velocity.scale(dragFactor);
            body.angularVelocity *= dragFactor;

            // 2. Update position: x += v * dt
            body.position.addScaled(body.velocity, deltaTime);
            body.angle += body.angularVelocity * deltaTime;

            // Reset acceleration for the next frame
            body.acceleration.setZero();
            body.torque = 0.0;
          }
        }
      }
    }

    // Simple collision detection
    _detectCollisions();

    _stepStopwatch.stop();
    _lastAwakeBodyCount = awakeBodyCount;
    _lastStepMs = _stepStopwatch.elapsedMicroseconds / 1000.0;
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
    _grid.removeBody(body);
  }

  /// Broad-phase grid
  final SpatialGrid _grid = SpatialGrid(100.0);

  /// Detect collisions
  void _detectCollisions() {
    _grid.syncBodies(_bodies);
    _lastBroadphaseDirtyBodyCount = _grid.dirtyBodyCount;
    _lastTrackedCellCount = _grid.trackedCellCount;

    final potentialPairs = _grid.getPotentialCollisions();
    _lastPotentialPairCount = potentialPairs.length;

    for (final pair in potentialPairs) {
      final bodyA = pair.a;
      final bodyB = pair.b;

      // Note: isActive and checkCollision are already filtered during grid insertion

      final manifold = bodyA.shape.getManifold(
        bodyA.position.toOffset(),
        bodyB.shape,
        bodyB.position.toOffset(),
      );

      if (manifold.isColliding) {
        _lastResolvedCollisionCount++;
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

    // Only wake bodies for significant collisions
    if (penetration > 0.05 ||
        a.velocity.lengthSquared > 1.0 ||
        b.velocity.lengthSquared > 1.0) {
      a.isAwake = true;
      a.sleepTimer = 0.0;
      b.isAwake = true;
      b.sleepTimer = 0.0;
    }

    // ── Positional correction (mass-proportional) ─────────────────────────
    final inverseMassSum = a.inverseMass + b.inverseMass;

    if (inverseMassSum == 0) return; // both immovable

    const correctionPercent = 0.8;
    const slop = 0.05;
    final correctionMag =
        math.max(penetration - slop, 0.0) / inverseMassSum * correctionPercent;
    // In-place positional correction using Offset normal
    a.position.x -= normal.dx * correctionMag * a.inverseMass;
    a.position.y -= normal.dy * correctionMag * a.inverseMass;
    b.position.x += normal.dx * correctionMag * b.inverseMass;
    b.position.y += normal.dy * correctionMag * b.inverseMass;

    // ── Impulse resolution ────────────────────────────────────────────────
    // Relative velocity of B w.r.t. A (no allocation — compute inline)
    final rvx = b.velocity.x - a.velocity.x;
    final rvy = b.velocity.y - a.velocity.y;
    final velAlongNormal = rvx * normal.dx + rvy * normal.dy;

    if (velAlongNormal > 0) return; // separating

    final restitution = math.min(a.restitution, b.restitution);
    final j = -(1.0 + restitution) * velAlongNormal / inverseMassSum;

    // Apply normal impulse in-place
    final jnx = normal.dx * j;
    final jny = normal.dy * j;
    a.velocity.x -= jnx * a.inverseMass;
    a.velocity.y -= jny * a.inverseMass;
    b.velocity.x += jnx * b.inverseMass;
    b.velocity.y += jny * b.inverseMass;

    // ── Friction (Tangent Impulse) ──────────────────────────────────────────
    // Recompute relative velocity after impulse
    final rvx2 = b.velocity.x - a.velocity.x;
    final rvy2 = b.velocity.y - a.velocity.y;
    final rvDotN = rvx2 * normal.dx + rvy2 * normal.dy;
    var tx = rvx2 - normal.dx * rvDotN;
    var ty = rvy2 - normal.dy * rvDotN;

    final tangentLen = math.sqrt(tx * tx + ty * ty);
    if (tangentLen > 0.0001) {
      final invLen = 1.0 / tangentLen;
      tx *= invLen;
      ty *= invLen;

      final jt = -(rvx2 * tx + rvy2 * ty) / inverseMassSum;
      final mu = (a.friction + b.friction) / 2.0;

      double fScalar = jt;
      if (fScalar.abs() > j * mu) {
        fScalar = (fScalar > 0 ? 1.0 : -1.0) * j * mu;
      }

      a.velocity.x -= tx * fScalar * a.inverseMass;
      a.velocity.y -= ty * fScalar * a.inverseMass;
      b.velocity.x += tx * fScalar * b.inverseMass;
      b.velocity.y += ty * fScalar * b.inverseMass;
    }
  }

  // ── Cached debug paints ────────────────────────────────────────────────
  static final Paint _debugActivePaint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  static final Paint _debugInactivePaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  static final Paint _debugVelocityPaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 2.0;
  static final Paint _debugCenterPaint = Paint()..color = Colors.red;

  /// Render debug visualization
  void renderDebug(Canvas canvas, Size size) {
    if (!debugRender) return;

    for (final body in _bodies) {
      // Draw body
      final paint = body.isActive ? _debugActivePaint : _debugInactivePaint;

      final shape = body.shape;
      if (shape is CircleShape) {
        canvas.drawCircle(body.position.toOffset(), shape.radius, paint);
      } else if (shape is PolygonShape) {
        final path = Path();
        if (shape.vertices.isNotEmpty) {
          path.moveTo(
            body.position.x + shape.vertices[0].dx,
            body.position.y + shape.vertices[0].dy,
          );
          for (int i = 1; i < shape.vertices.length; i++) {
            path.lineTo(
              body.position.x + shape.vertices[i].dx,
              body.position.y + shape.vertices[i].dy,
            );
          }
          path.close();
        }
        canvas.drawPath(path, paint);
      }

      // Draw velocity vector
      if (body.velocity.lengthSquared > 0) {
        canvas.drawLine(
          body.position.toOffset(),
          Offset(
            body.position.x + body.velocity.x * 0.1,
            body.position.y + body.velocity.y * 0.1,
          ),
          _debugVelocityPaint,
        );
      }

      // Draw center point
      canvas.drawCircle(body.position.toOffset(), 3, _debugCenterPaint);
    }
  }

  /// Clean up physics resources
  void dispose() {
    _bodies.clear();
    _grid.clear();
    debugPrint('Physics Engine disposed');
  }

  /// Get all bodies
  List<PhysicsBody> get bodies => List.unmodifiable(_bodies);

  /// Lightweight physics diagnostics from the last simulation step.
  Map<String, dynamic> get stats => {
    'bodyCount': _bodies.length,
    'awakeBodies': _lastAwakeBodyCount,
    'potentialPairs': _lastPotentialPairCount,
    'resolvedCollisions': _lastResolvedCollisionCount,
    'broadphaseDirtyBodies': _lastBroadphaseDirtyBodyCount,
    'trackedCells': _lastTrackedCellCount,
    'lastStepMs': _lastStepMs,
  };

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
