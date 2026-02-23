/// Physics Engine
///
/// Simulates realistic movement, gravity, collision detection, and object interactions.
/// This module provides physics simulation capabilities for game objects.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Main physics engine class
class PhysicsEngine {
  /// All physics bodies
  final List<PhysicsBody> _bodies = [];

  /// Global gravity
  Offset gravity = const Offset(0, 500);

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
        // Apply gravity
        if (body.useGravity) {
          body.velocity += gravity * deltaTime;
        }

        // Update position
        body.position += body.velocity * deltaTime;

        // Apply drag
        body.velocity *= (1.0 - body.drag * deltaTime);
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

  /// Detect collisions
  void _detectCollisions() {
    for (int i = 0; i < _bodies.length; i++) {
      for (int j = i + 1; j < _bodies.length; j++) {
        final bodyA = _bodies[i];
        final bodyB = _bodies[j];

        if (!bodyA.isActive || !bodyB.isActive) continue;
        if (!bodyA.checkCollision || !bodyB.checkCollision) continue;

        if (_checkCollision(bodyA, bodyB)) {
          _resolveCollision(bodyA, bodyB);
        }
      }
    }
  }

  /// Check collision between two bodies
  bool _checkCollision(PhysicsBody a, PhysicsBody b) {
    // Simple circle collision
    final distance = (a.position - b.position).distance;
    return distance < (a.radius + b.radius);
  }

  /// Resolve collision
  void _resolveCollision(PhysicsBody a, PhysicsBody b) {
    final delta = b.position - a.position;
    final distance = delta.distance;

    if (distance == 0) return;

    final normal = delta / distance;
    final penetration = (a.radius + b.radius) - distance;

    if (penetration <= 0) return;

    // ── Positional correction (mass-proportional) ─────────────────────────
    // Push bodies apart weighted by inverse mass so heavier objects move less.
    final invMassA = a.mass > 0 ? 1.0 / a.mass : 0.0;
    final invMassB = b.mass > 0 ? 1.0 / b.mass : 0.0;
    final invMassSum = invMassA + invMassB;

    if (invMassSum == 0) return; // both immovable

    // Add a small correction bias so bodies are fully clear on the next frame.
    const correctionPercent = 0.8;
    const slop = 0.3; // ignore tiny overlaps to avoid jitter
    final correctionMag =
        math.max(penetration - slop, 0.0) / invMassSum * correctionPercent;
    a.position -= normal * (correctionMag * invMassA);
    b.position += normal * (correctionMag * invMassB);

    // ── Impulse resolution ────────────────────────────────────────────────
    final relativeVelocity = a.velocity - b.velocity;
    final velAlongNormal =
        relativeVelocity.dx * normal.dx + relativeVelocity.dy * normal.dy;

    // velAlongNormal > 0  →  A is moving toward B  →  collision to resolve.
    // velAlongNormal ≤ 0  →  bodies already separating, nothing to do.
    if (velAlongNormal <= 0) return;

    // Use the lesser restitution so collisions are never artificially springy.
    final restitution = math.min(a.restitution, b.restitution);

    // j = (1+e) * velAlongNormal / (1/mA + 1/mB)
    // A is pushed in −normal direction (away from B), B in +normal direction.
    final impulseScalar = (1.0 + restitution) * velAlongNormal / invMassSum;

    a.velocity -= normal * (impulseScalar * invMassA);
    b.velocity += normal * (impulseScalar * invMassB);
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

      canvas.drawCircle(body.position, body.radius, paint);

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
}

/// Physics body
class PhysicsBody {
  /// Position
  Offset position;

  /// Velocity
  Offset velocity;

  /// Radius (for circular collision)
  double radius;

  /// Mass
  double mass;

  /// Restitution (bounciness)
  double restitution;

  /// Drag
  double drag;

  /// Use gravity
  bool useGravity;

  /// Is active
  bool isActive;

  /// Check collisions
  bool checkCollision;

  /// Create a physics body
  PhysicsBody({
    required this.position,
    this.velocity = Offset.zero,
    this.radius = 10.0,
    this.mass = 1.0,
    this.restitution = 0.5,
    this.drag = 0.1,
    this.useGravity = true,
    this.isActive = true,
    this.checkCollision = true,
  });

  /// Apply force
  void applyForce(Offset force) {
    velocity += force / mass;
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
  /// Calculate collision with another shape
  bool checkCollision(CollisionShape other);
}
