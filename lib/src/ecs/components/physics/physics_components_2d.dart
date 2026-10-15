library;

import 'dart:ui' show Offset;

import 'package:just_dart/just_dart.dart' show Vector2;
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs.dart';

// The 2-D physics components, in step with the 3-D ones:
// `RigidBody2D` ↔ `RigidBody3D`, `Collider2D` ↔ `Collider3D`, with the same
// field names wherever the meaning is the same. `PhysicsSystem` simulates
// them. Units are the world's (pixels in a 2-D game); +Y is down.

/// Makes its entity a body that `PhysicsSystem` simulates: how it moves,
/// how heavy it is, what it is made of. It needs a [Collider2D] on the same
/// entity for its shape; a collider without one is a static body.
///
/// Gameplay moves a dynamic body with [addForce], [addImpulse] or
/// [setVelocity] — all applied before the next step — and a kinematic or
/// static one by writing its entity's transform (or a `VelocityComponent`).
class RigidBody2D extends Component {
  /// A dynamic body on layer 0, by default.
  RigidBody2D({
    this.bodyType = BodyType.dynamic,
    this.mass = 0.0,
    this.friction = 0.5,
    this.restitution = 0.0,
    this.linearDamping = 0.05,
    this.angularDamping = 0.05,
    this.gravityScale = 1.0,
    this.isSensor = false,
    this.lockRotation = false,
    this.continuousCollision = false,
    this.canSleep = true,
    this.initialVelocity = Offset.zero,
    this.initialAngularVelocity = 0.0,
    this.layer = 0,
    this.collidesWith,
    this.groupIndex = 0,
  });

  /// How the body takes part in the simulation: [BodyType.static] never
  /// moves (level geometry), [BodyType.kinematic] moves only as its
  /// velocity says and cannot be pushed (moving platforms),
  /// [BodyType.dynamic] is fully simulated.
  BodyType bodyType;

  /// Mass in kg; 0 works it out from the collider's area, as a 3-D body
  /// does from its volume (see `PhysicsSystem.autoMassPerSquareUnit`: a
  /// 100 × 100 square weighs 1000 kg). Only a dynamic body's mass matters.
  double mass;

  /// Surface friction, 0 (ice) up: how much a body sliding along this one
  /// is held back. A contact uses the two bodies' friction together.
  double friction;

  /// Bounciness, 0 (none) to 1 (all of it). A contact bounces as much as
  /// the *less* bouncy of its two bodies.
  double restitution;

  /// How much of its velocity a dynamic body loses on its own each second,
  /// as air resistance would. 0 keeps it moving; the default, 0.05 (as in
  /// 3-D), loses about 5% of its speed a second; 1 about two thirds.
  double linearDamping;

  /// As [linearDamping], for spin.
  double angularDamping;

  /// Gravity on it, times this: 0 floats, 2 falls hard. What variable jump
  /// height is driven through.
  double gravityScale;

  /// Whether it only reports what overlaps it ([SensorEnter2DEvent]) and
  /// stops nothing: triggers, pickups, zones.
  bool isSensor;

  /// Whether it never turns: a character that slides along scenery instead
  /// of tipping over when it clips a rock.
  bool lockRotation;

  /// Continuous collision: a small, fast body is swept from where it was to
  /// where it is each step, so it cannot pass through a thin wall between
  /// two. Costs more; on the native backend only.
  bool continuousCollision;

  /// Whether the body may fall asleep when it comes to rest. Sleeping bodies
  /// cost nothing until something touches them.
  bool canSleep;

  /// The velocity it starts with when its simulated body is made — a thrown
  /// crate, a platform already on its way. A `VelocityComponent` on the
  /// entity wins over it.
  Offset initialVelocity;

  /// The spin, in radians per second, it starts with.
  double initialAngularVelocity;

  /// Its collision layer, 0–15, named in the project's `physics.json`.
  int layer;

  /// The layers it collides with, as a mask — bit `n` for layer `n`. Null
  /// follows the project's grid for [layer]. Two bodies collide only if
  /// each collides with the other's layer.
  int? collidesWith;

  /// Collision group (positive: same group always collides; negative:
  /// never does; 0: layers decide).
  int groupIndex;

  /// Whether the body never moves ([BodyType.static]).
  bool get isStatic => bodyType == BodyType.static;

  /// Whether the body moves only by its velocity ([BodyType.kinematic]).
  bool get isKinematic => bodyType == BodyType.kinematic;

  /// Whether the body is fully simulated ([BodyType.dynamic]).
  bool get isDynamic => bodyType == BodyType.dynamic;

  // ── Runtime: never saved ──────────────────────────────────────────────

  /// Its velocity after the last step.
  Offset linearVelocity = Offset.zero;

  /// Its spin after the last step (rad/s).
  double angularVelocity = 0;

  /// Whether it was awake after the last step.
  bool isAwake = false;

  /// Whether it rests on a surface: true for as long as a contact from
  /// below lasts, not just its first frame. Kept by `PhysicsSystem` from
  /// contacts — what a platformer's controller reads.
  bool isGrounded = false;

  /// The entity it stands on, or null: a rider takes a moving platform's
  /// velocity from it.
  Entity? groundEntity;

  /// The ground's normal: straight up, `(0, -1)`, on flat ground, tilted on
  /// a slope — to stand still on one, and follow it walking down.
  Offset groundNormal = const Offset(0, -1);

  /// Force waiting for the next step (applied for that one step).
  Offset pendingForce = Offset.zero;

  /// Torque waiting for the next step.
  double pendingTorque = 0;

  /// Impulse waiting for the next step: a change of velocity times mass.
  Offset pendingImpulse = Offset.zero;

  /// Angular impulse waiting for the next step.
  double pendingAngularImpulse = 0;

  /// A velocity to set before the next step, or null.
  Offset? pendingVelocity;

  /// A spin to set before the next step, or null.
  double? pendingAngularVelocity;

  /// Whether to wake it before the next step.
  bool pendingWake = false;

  /// Pushes it during the next step.
  void addForce(Offset force) => pendingForce += force;

  /// Turns it during the next step.
  void addTorque(double torque) => pendingTorque += torque;

  /// Changes its velocity at once, before the next step: a jump, a hit.
  void addImpulse(Offset impulse) => pendingImpulse += impulse;

  /// Changes its spin at once, before the next step.
  void addAngularImpulse(double impulse) => pendingAngularImpulse += impulse;

  /// Sets its velocity before the next step.
  void setVelocity(Offset velocity) => pendingVelocity = velocity;

  /// Sets its spin before the next step.
  void setAngularVelocity(double velocity) => pendingAngularVelocity = velocity;

  /// Wakes it before the next step.
  void wakeUp() => pendingWake = true;

  @override
  String toString() => 'RigidBody2D(${bodyType.name}, mass: $mass)';
}

/// The shapes a [Collider2D] can be.
enum ColliderShape2D {
  /// A box [Collider2D.size] big, its corners rounded by
  /// [Collider2D.cornerRadius].
  box,

  /// A circle of [Collider2D.radius].
  circle,

  /// A capsule along Y, [Collider2D.height] tall overall, of
  /// [Collider2D.radius]; turn it with [Collider2D.rotation].
  capsule,

  /// The convex polygon through [Collider2D.points] (at most 8), its
  /// corners rounded by [Collider2D.cornerRadius].
  polygon,

  /// A line from [Collider2D.points]' first point to its second,
  /// [Collider2D.thickness] thick.
  segment,

  /// A line through every one of [Collider2D.points] — a closed outline
  /// with [Collider2D.loop] — [Collider2D.thickness] thick: terrain.
  chain,

  /// The shape its entity is drawn as — a Rectangle, Circle, Capsule,
  /// Polygon or Line component, else its sprite's box — following it as it
  /// changes.
  matchShape,
}

/// The shape of its entity's [RigidBody2D] — or, without one, of a static
/// body made for it. It follows the entity's scale. Set to
/// [ColliderShape2D.matchShape] it takes the shape its entity is drawn as.
class Collider2D extends Component {
  /// A 64 × 64 box, by default.
  Collider2D({
    this.shape = ColliderShape2D.box,
    Vector2? size,
    this.radius = 32.0,
    this.height = 64.0,
    List<Offset>? points,
    this.cornerRadius = 0.0,
    this.thickness = 2.0,
    this.loop = false,
    this.offset = Offset.zero,
    this.rotation = 0.0,
    Vector2? scale,
    this.oneWay = false,
    this.oneWayDirection = OneWayDirection.fromAbove,
    this.showDebugOutline = true,
  }) : size = size ?? Vector2(64, 64),
       points =
           points ??
           [
             const Offset(-32, -32),
             const Offset(32, -32),
             const Offset(32, 32),
             const Offset(-32, 32),
           ],
       scale = scale ?? Vector2(1, 1);

  /// Which shape.
  ColliderShape2D shape;

  /// Box: its full width and height.
  Vector2 size;

  /// Circle and capsule: the radius.
  double radius;

  /// Capsule: its whole height, ends included.
  double height;

  /// Polygon, segment and chain: the points, in order.
  List<Offset> points;

  /// Box and polygon: how much the corners are rounded.
  double cornerRadius;

  /// Segment and chain: how thick the line is.
  double thickness;

  /// Chain: whether the last point joins the first.
  bool loop;

  /// Where the shape sits in its entity's space — a feet box under a tall
  /// sprite. Scaled and turned with the entity.
  Offset offset;

  /// How the shape is turned in its entity's space, radians.
  double rotation;

  /// The shape's own scale, on top of its entity's.
  Vector2 scale;

  /// One-way platform: solid only to what comes from [oneWayDirection],
  /// passed through from every other side.
  bool oneWay;

  /// Which side [oneWay] makes it solid from.
  OneWayDirection oneWayDirection;

  /// Whether `PhysicsSystem` draws its outline while a debug build runs.
  bool showDebugOutline;

  @override
  String toString() => 'Collider2D(${shape.name})';
}

/// The shape a [CharacterBody2D] moves as.
enum CharacterShape2D {
  /// An upright capsule: rounded feet slide over bumps and off ledges.
  capsule,

  /// A box with slightly rounded corners: flat feet stand on a ledge's
  /// corner, as pixel platformers usually want.
  box,
}

/// A character gameplay moves rather than the simulation: it walks slopes
/// up to [maxSlopeAngle], climbs steps up to [stepHeight], keeps to the
/// floor going down, rides moving platforms, stands on one-way platforms and
/// jumps up through them, and pushes dynamic bodies — like
/// the 3-D `CharacterBody3D`, field for field. It needs no
/// [RigidBody2D] or [Collider2D]: its shape is its own, centred on the
/// entity (plus [offset]).
///
/// Each step, set [moveVelocity] (only its sideways part counts while
/// [useGravity]) and call [jump] to leave the ground; read [isGrounded],
/// [groundNormal], [groundEntity] and [velocity] after it.
class CharacterBody2D extends Component {
  /// A 32 × 48 capsule, by default.
  CharacterBody2D({
    this.shape = CharacterShape2D.capsule,
    this.radius = 16.0,
    this.width = 32.0,
    this.height = 48.0,
    this.offset = Offset.zero,
    this.maxSlopeAngle = 0.8726646259971648,
    this.stepHeight = 8.0,
    this.stickToFloor = 8.0,
    this.mass = 70.0,
    this.pushStrength = 2000.0,
    this.gravityScale = 1.0,
    this.useGravity = true,
    this.layer = 0,
    this.collidesWith,
    this.detectable = true,
  });

  /// The shape it moves as.
  CharacterShape2D shape;

  /// Radius of its capsule.
  double radius;

  /// Width of its box.
  double width;

  /// Its whole height, top to bottom.
  double height;

  /// Moves its shape off the entity's origin.
  Offset offset;

  /// Steepest slope it can walk up, radians (50° by default).
  double maxSlopeAngle;

  /// Tallest step it climbs; 0 climbs none.
  double stepHeight;

  /// How far down it keeps to the floor going down slopes and steps; 0
  /// leaves the ground at every edge.
  double stickToFloor;

  /// Its mass (kg), 70 as in 3-D: how hard it pushes bodies it walks into.
  double mass;

  /// The most force it pushes with.
  double pushStrength;

  /// Gravity on it, times this, with [useGravity].
  double gravityScale;

  /// Whether the system adds gravity and the ground's velocity.
  bool useGravity;

  /// Its collision layer, 0–15.
  int layer;

  /// The layers it collides with as a mask (bit n for layer n), or null for
  /// what the project's grid says for [layer].
  int? collidesWith;

  /// Whether sensors detect it, rays hit it and dynamic bodies bump into
  /// it.
  bool detectable;

  // ── Runtime: never saved ──────────────────────────────────────────────

  /// The velocity gameplay wants it to move at; kept until changed.
  Offset moveVelocity = Offset.zero;

  /// Its velocity after the last step.
  Offset velocity = Offset.zero;

  /// What it stands on after the last step.
  GroundState2D groundState = GroundState2D.inAir;

  /// The ground's normal after the last step.
  Offset groundNormal = Offset.zero;

  /// The ground's velocity after the last step (a moving platform's).
  Offset groundVelocity = Offset.zero;

  /// The entity it stands on, or null.
  Entity? groundEntity;

  /// A jump speed waiting for the next step, or null.
  double? pendingJump;

  /// Whether it stands on walkable ground.
  bool get isGrounded => groundState == GroundState2D.onGround;

  /// Jumps at [speed] (units per second) at the next step, if it is on the
  /// ground then (with [useGravity]).
  void jump(double speed) => pendingJump = speed;

  /// The shape the mover moves it as.
  MoverShape get moverShape => shape == CharacterShape2D.box
      ? MoverShape.box(width: width, height: height)
      : MoverShape.capsule(radius: radius, height: height);

  @override
  String toString() => 'CharacterBody2D(${shape.name})';
}
