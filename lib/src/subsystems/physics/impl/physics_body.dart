part of '../physics_engine.dart';

/// Physics body — the core simulation object in the physics engine.
///
/// Uses [Vector2] for position/velocity/acceleration to avoid per-frame
/// [Offset] allocations.
class PhysicsBody {
  /// Mutable position.
  final Vector2 position;

  /// Mutable velocity.
  final Vector2 velocity;

  /// Mutable acceleration accumulator.
  final Vector2 acceleration;

  /// The physical shape used for collision detection
  CollisionShape shape;

  /// Mass (0 means infinite mass / static body)
  double mass;

  /// Inverse Mass (calculated automatically)
  double get inverseMass => mass > 0 ? 1.0 / mass : 0.0;

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
  double get inverseInertia => inertia > 0 ? 1.0 / inertia : 0.0;

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
    required Vector2 position,
    required this.shape,
    Vector2? velocity,
    Vector2? acceleration,
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
  }) : position = Vector2(position.x, position.y),
       velocity = velocity != null
           ? Vector2(velocity.x, velocity.y)
           : Vector2.zero(),
       acceleration = acceleration != null
           ? Vector2(acceleration.x, acceleration.y)
           : Vector2.zero();

  /// Apply force
  void applyForce(Vector2 force) {
    if (mass > 0) {
      acceleration.x += force.x * inverseMass;
      acceleration.y += force.y * inverseMass;
    }
  }

  /// Apply torque
  void applyTorque(double applicationTorque) {
    if (inertia > 0) {
      torque += applicationTorque;
    }
  }

  /// Apply impulse
  void applyImpulse(Vector2 impulse) {
    velocity.x += impulse.x;
    velocity.y += impulse.y;
  }
}

/// Represents a rigid body with 2D force accumulation (convenience wrapper).
///
/// For most use cases, prefer [PhysicsBody] directly. This class exists for
/// code that needs a simpler interface without collision shape requirements.
class RigidBody {
  /// Mass of the rigid body
  double mass = 1.0;

  /// Accumulated force (reset each integration step).
  final Vector2 _force = Vector2.zero();

  /// Current velocity.
  final Vector2 velocity = Vector2.zero();

  /// Current position.
  final Vector2 position = Vector2.zero();

  /// Apply a 2D force. The z component is ignored (2D engine).
  void applyForce(double x, double y, [double z = 0]) {
    _force.x += x;
    _force.y += y;
  }

  /// Integrate forces → velocity → position for one timestep.
  void integrate(double dt) {
    if (mass <= 0) return;
    final inverseMass = 1.0 / mass;
    velocity.x += _force.x * inverseMass * dt;
    velocity.y += _force.y * inverseMass * dt;
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
    _force.setZero();
  }
}

/// Utility for manual broad-phase collision queries outside [PhysicsEngine].
///
/// Wraps the [SpatialGrid]-based check used internally by the engine and
/// exposes it for gameplay code that needs ad-hoc overlap tests.
class CollisionDetector {
  final List<PhysicsBody> _bodies = [];

  /// Register a body for detection.
  void addBody(PhysicsBody body) => _bodies.add(body);

  /// Remove a body.
  void removeBody(PhysicsBody body) => _bodies.remove(body);

  /// Return all overlapping body pairs using brute-force AABB check.
  List<(PhysicsBody, PhysicsBody)> detectCollisions() {
    final pairs = <(PhysicsBody, PhysicsBody)>[];
    for (var i = 0; i < _bodies.length; i++) {
      final a = _bodies[i];
      if (!a.isActive) continue;
      final aBounds = a.shape.getBounds(a.position.toOffset());
      for (var j = i + 1; j < _bodies.length; j++) {
        final b = _bodies[j];
        if (!b.isActive) continue;
        final bBounds = b.shape.getBounds(b.position.toOffset());
        if (aBounds.overlaps(bBounds)) {
          pairs.add((a, b));
        }
      }
    }
    return pairs;
  }
}

/// Applies global forces (gravity, wind, etc.) to a set of [PhysicsBody]s.
class ForceManager {
  /// Current gravity vector.
  final Vector2 gravity = Vector2(0, 980);

  /// Set gravity. The z component is ignored (2D engine).
  void setGravity(double x, double y, [double z = 0]) {
    gravity.x = x;
    gravity.y = y;
  }

  /// Apply gravity to all [bodies] that have [PhysicsBody.useGravity] enabled.
  void applyGravity(Iterable<PhysicsBody> bodies) {
    for (final body in bodies) {
      if (!body.isActive || !body.isAwake || !body.useGravity) continue;
      if (body.mass <= 0) continue; // static
      body.acceleration.x += gravity.x;
      body.acceleration.y += gravity.y;
    }
  }
}
