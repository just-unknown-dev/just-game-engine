import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/physics_3d.dart';

// The 3-D physics components. Plain data with no native code, so scenes
// that hold them load everywhere, the web included (where nothing simulates
// them). Units are metres; +Y is down.

/// Makes its entity a rigid body that [PhysicsSystem3D] simulates. It needs
/// a [Collider3D] on the same entity for its shape.
///
/// Gameplay moves a dynamic body with forces, impulses or a velocity — all
/// applied before the next step — and a kinematic or static one by writing
/// its entity's transform.
class RigidBody3D extends Component {
  /// A dynamic body on layer 0, by default.
  RigidBody3D({
    this.bodyType = BodyType3D.dynamic,
    this.continuousCollision = false,
    this.mass = 0.0,
    this.friction = 0.5,
    this.restitution = 0.0,
    this.linearDamping = 0.05,
    this.angularDamping = 0.05,
    this.gravityScale = 1.0,
    this.isSensor = false,
    this.layer = 0,
    this.canSleep = true,
    this.lockRotation = false,
    Vector3? initialVelocity,
    Vector3? initialAngularVelocity,
  }) : initialVelocity = initialVelocity ?? Vector3.zero(),
       initialAngularVelocity = initialAngularVelocity ?? Vector3.zero();

  /// Static, kinematic or dynamic. A change rebuilds the body.
  BodyType3D bodyType;

  /// Continuous collision: a fast body is swept from where it was to where
  /// it is each step, so it cannot pass through a thin wall. Costs more.
  bool continuousCollision;

  /// Mass in kg; 0 works it out from the collider's volume.
  double mass;

  /// Surface friction, usually 0–1.
  double friction;

  /// Bounciness, 0–1.
  double restitution;

  /// How quickly it slows by itself. A change rebuilds the body.
  double linearDamping;

  /// How quickly its spin slows by itself. A change rebuilds the body.
  double angularDamping;

  /// Gravity on it, times this: 0 floats, 2 falls hard.
  double gravityScale;

  /// Whether it only reports what enters and leaves it
  /// ([SensorEnter3DEvent]) instead of colliding. A change rebuilds it.
  bool isSensor;

  /// Its collision layer, 0–15 (the project's `physics.json`).
  int layer;

  /// Whether it may fall asleep at rest. A change rebuilds the body.
  bool canSleep;

  /// Whether it never turns. A change rebuilds the body.
  bool lockRotation;

  /// Velocity it starts with (m/s).
  Vector3 initialVelocity;

  /// Spin it starts with (rad/s).
  Vector3 initialAngularVelocity;

  // ── Runtime: never saved ──────────────────────────────────────────────

  /// The physics engine's body, or 0 while it has none.
  int body = 0;

  /// Its velocity after the last step (m/s).
  final Vector3 linearVelocity = Vector3.zero();

  /// Its spin after the last step (rad/s).
  final Vector3 angularVelocity = Vector3.zero();

  /// Whether it was awake after the last step.
  bool isAwake = false;

  /// Force, torque and impulses waiting for the next step.
  final Vector3 pendingForce = Vector3.zero();

  /// See [pendingForce].
  final Vector3 pendingTorque = Vector3.zero();

  /// See [pendingForce].
  final Vector3 pendingImpulse = Vector3.zero();

  /// See [pendingForce].
  final Vector3 pendingAngularImpulse = Vector3.zero();

  /// A velocity to set before the next step, or null.
  Vector3? pendingVelocity;

  /// A spin to set before the next step, or null.
  Vector3? pendingAngularVelocity;

  /// Whether to wake it before the next step.
  bool pendingWake = false;

  /// Pushes it during the next step (N).
  void addForce(Vector3 force) => pendingForce.add(force);

  /// Turns it during the next step (N·m).
  void addTorque(Vector3 torque) => pendingTorque.add(torque);

  /// Changes its velocity at once, before the next step (N·s).
  void addImpulse(Vector3 impulse) => pendingImpulse.add(impulse);

  /// Changes its spin at once, before the next step (N·m·s).
  void addAngularImpulse(Vector3 impulse) => pendingAngularImpulse.add(impulse);

  /// Sets its velocity before the next step.
  void setVelocity(Vector3 velocity) =>
      (pendingVelocity ??= Vector3.zero()).setFrom(velocity);

  /// Sets its spin before the next step.
  void setAngularVelocity(Vector3 velocity) =>
      (pendingAngularVelocity ??= Vector3.zero()).setFrom(velocity);

  /// Wakes it before the next step.
  void wakeUp() => pendingWake = true;
}

/// The shapes a [Collider3D] can be.
enum ColliderShape3D {
  /// A box [Collider3D.size] big.
  box,

  /// A sphere of [Collider3D.radius].
  sphere,

  /// A capsule along Y, [Collider3D.height] tall overall, of
  /// [Collider3D.radius].
  capsule,

  /// A cylinder along Y, [Collider3D.height] tall, of [Collider3D.radius].
  cylinder,

  /// The convex hull of a model's vertices ([Collider3D.model]).
  convexHull,

  /// A model's triangles ([Collider3D.model]); static and kinematic bodies
  /// only.
  mesh,

  /// Terrain from [Collider3D.heights]; static bodies only.
  heightField,

  /// The shape its entity is drawn as — a 3-D shape such as
  /// just_graphics_engine's `Cube3D` or `Stairs3D` (any [SolidShapeSource]
  /// on the entity) — following it as it changes. A concave one is made of
  /// convex parts, so it works on a dynamic body too.
  matchShape,
}

/// The shape of its entity's [RigidBody3D] — or, without one, of a static
/// body made for it. It follows the entity's scale. Set to
/// [ColliderShape3D.matchShape] it takes the shape its entity is drawn as.
class Collider3D extends Component {
  /// A 1 m box, by default.
  Collider3D({
    this.shape = ColliderShape3D.box,
    Vector3? size,
    this.radius = 0.5,
    this.height = 2.0,
    this.model = '',
    this.meshName = '',
    List<double>? heights,
    this.heightFieldSize = 0,
    this.cellSize = 1.0,
    Vector3? offset,
    Vector3? rotation,
    Vector3? scale,
  }) : size = size ?? Vector3(1, 1, 1),
       heights = heights ?? <double>[],
       offset = offset ?? Vector3.zero(),
       rotation = rotation ?? Vector3.zero(),
       scale = scale ?? Vector3(1, 1, 1);

  /// Which shape.
  ColliderShape3D shape;

  /// Box: its full size along X, Y and Z.
  Vector3 size;

  /// Sphere, capsule and cylinder: the radius.
  double radius;

  /// Capsule: its whole height, caps included. Cylinder: its height.
  double height;

  /// Convex hull and mesh: the model (`.glb`, `.gltf`) whose triangles it
  /// takes, loaded through the engine's assets.
  String model;

  /// Convex hull and mesh: the model's mesh to use; empty for all of them.
  String meshName;

  /// Height field: [heightFieldSize] rows of [heightFieldSize] heights,
  /// each how far up the ground is at that sample.
  List<double> heights;

  /// Height field: samples along each side; at least 4.
  int heightFieldSize;

  /// Height field: metres between samples.
  double cellSize;

  /// Where the shape sits in its entity's space.
  Vector3 offset;

  /// How the shape is turned in its entity's space (Euler angles, radians).
  Vector3 rotation;

  /// The shape's own scale, on top of its entity's.
  Vector3 scale;

  /// The shape's size before any scale, for an editor's outline:
  /// `size` for a box, `2 × radius` (and [height]) for the round ones.
  Vector3 get naturalSize => switch (shape) {
    ColliderShape3D.box => Vector3.copy(size),
    ColliderShape3D.sphere => Vector3(radius * 2, radius * 2, radius * 2),
    ColliderShape3D.capsule ||
    ColliderShape3D.cylinder => Vector3(radius * 2, height, radius * 2),
    _ => Vector3(1, 1, 1),
  };
}

/// A character controlled by gameplay rather than forces: a capsule that
/// walks on ground, slides along walls, climbs steps and slopes, and rides
/// moving platforms (Jolt's `CharacterVirtual`). Its entity's position is
/// its feet.
///
/// Each step gameplay sets [moveVelocity] (and may [jump]); with
/// [useGravity] the system adds gravity and the ground's own velocity, as
/// a platformer wants. Without it [moveVelocity] is the whole velocity
/// (flying, swimming, ladders).
class CharacterBody3D extends Component {
  /// A character 1.8 m tall and 0.3 m in radius, by default.
  CharacterBody3D({
    this.radius = 0.3,
    this.height = 1.8,
    this.maxSlopeAngle = 0.8726646259971648,
    this.stepHeight = 0.4,
    this.stickToFloor = 0.5,
    this.mass = 70.0,
    this.pushStrength = 100.0,
    this.gravityScale = 1.0,
    this.useGravity = true,
    this.layer = 0,
    this.detectable = true,
  });

  /// Radius of its capsule.
  double radius;

  /// Its whole height, feet to the top of its head.
  double height;

  /// Steepest slope it can walk up, radians (50° by default).
  double maxSlopeAngle;

  /// Tallest step it climbs; 0 climbs none.
  double stepHeight;

  /// How far down it keeps to the floor going down slopes and steps; 0
  /// leaves the ground at every edge.
  double stickToFloor;

  /// Its mass (kg): how hard it pushes bodies it walks into.
  double mass;

  /// The most force it pushes with (N).
  double pushStrength;

  /// Gravity on it, times this, with [useGravity].
  double gravityScale;

  /// Whether the system adds gravity and the ground's velocity.
  bool useGravity;

  /// Its collision layer, 0–15.
  int layer;

  /// Whether sensors detect it and rays hit it.
  bool detectable;

  // ── Runtime: never saved ──────────────────────────────────────────────

  /// The physics engine's character, or 0 while it has none.
  int character = 0;

  /// The velocity gameplay wants it to move at; kept until changed.
  final Vector3 moveVelocity = Vector3.zero();

  /// Its velocity after the last step.
  final Vector3 velocity = Vector3.zero();

  /// What it stands on after the last step.
  GroundState3D groundState = GroundState3D.inAir;

  /// The ground's normal after the last step.
  final Vector3 groundNormal = Vector3.zero();

  /// The ground's velocity after the last step (a moving platform's).
  final Vector3 groundVelocity = Vector3.zero();

  /// The entity it stands on, or null.
  Entity? groundEntity;

  /// A jump speed waiting for the next step, or null.
  double? pendingJump;

  /// Whether it stands on walkable ground.
  bool get isGrounded => groundState == GroundState3D.onGround;

  /// Jumps at [speed] m/s at the next step, if it is on the ground then
  /// (with [useGravity]).
  void jump(double speed) => pendingJump = speed;
}

/// What a joint holds its entity's body to. The joint is on one entity (A)
/// and names the other ([connectedBody], B); none joins A to the world.
///
/// Anchors are in each entity's own space; the joint is made where the
/// bodies are when both exist, and made again when a setting changes.
/// Jointed bodies still collide with each other: leave a gap between them,
/// or put them on layers that do not collide.
abstract class Joint3D extends Component {
  /// A joint to [connectedBody] at [anchor].
  Joint3D({
    this.connectedBody = EntityTarget.none,
    Vector3? anchor,
    this.enabled = true,
  }) : anchor = anchor ?? Vector3.zero();

  /// The other body's entity; none for the world.
  EntityTarget connectedBody;

  /// Where on this entity the joint holds, in its own space.
  Vector3 anchor;

  /// Whether the joint acts.
  bool enabled;

  /// Which kind of joint this is.
  JointKind3D get kind;

  /// The physics engine's joint, or 0 while it has none. Runtime only.
  int joint = 0;
}

/// Holds two bodies rigidly together.
class FixedJoint3D extends Joint3D {
  /// A fixed joint.
  FixedJoint3D({super.connectedBody, super.anchor, super.enabled});

  @override
  JointKind3D get kind => JointKind3D.fixed;
}

/// Holds two bodies at one point, free to turn about it (a ball joint).
class PointJoint3D extends Joint3D {
  /// A point joint.
  PointJoint3D({super.connectedBody, super.anchor, super.enabled});

  @override
  JointKind3D get kind => JointKind3D.point;
}

/// Lets two bodies turn about one axis: a door, a wheel, a lever.
class HingeJoint3D extends Joint3D {
  /// A hinge about [axis] (this entity's +Y by default).
  HingeJoint3D({
    super.connectedBody,
    super.anchor,
    super.enabled,
    Vector3? axis,
    this.useLimits = false,
    this.minAngle = -1.5707963267948966,
    this.maxAngle = 1.5707963267948966,
    this.friction = 0.0,
    this.motor = MotorState3D.off,
    this.motorTarget = 0.0,
    this.motorMaxTorque = 0.0,
  }) : axis = axis ?? Vector3(0, 1, 0);

  /// The axis it turns about, in this entity's space.
  Vector3 axis;

  /// Whether it turns only between [minAngle] and [maxAngle].
  bool useLimits;

  /// The limits, radians.
  double minAngle, maxAngle;

  /// Friction torque while no motor drives it (N·m).
  double friction;

  /// Off, a target speed, or a target angle.
  MotorState3D motor;

  /// The motor's target: rad/s, or radians.
  double motorTarget;

  /// The most torque the motor uses (N·m); 0 for no limit.
  double motorMaxTorque;

  @override
  JointKind3D get kind => JointKind3D.hinge;

  /// Its angle after the last step (radians). Runtime only.
  double angle = 0.0;
}

/// Lets two bodies slide along one axis: a drawer, a piston, a lift.
class SliderJoint3D extends Joint3D {
  /// A slider along [axis] (this entity's +X by default).
  SliderJoint3D({
    super.connectedBody,
    super.anchor,
    super.enabled,
    Vector3? axis,
    this.useLimits = false,
    this.minPosition = -1.0,
    this.maxPosition = 1.0,
    this.friction = 0.0,
    this.motor = MotorState3D.off,
    this.motorTarget = 0.0,
    this.motorMaxForce = 0.0,
  }) : axis = axis ?? Vector3(1, 0, 0);

  /// The axis it slides along, in this entity's space.
  Vector3 axis;

  /// Whether it slides only between [minPosition] and [maxPosition].
  bool useLimits;

  /// The limits, metres.
  double minPosition, maxPosition;

  /// Friction force while no motor drives it (N).
  double friction;

  /// Off, a target speed, or a target position.
  MotorState3D motor;

  /// The motor's target: m/s, or metres.
  double motorTarget;

  /// The most force the motor uses (N); 0 for no limit.
  double motorMaxForce;

  @override
  JointKind3D get kind => JointKind3D.slider;

  /// Its position after the last step (metres). Runtime only.
  double position = 0.0;
}

/// Keeps two anchors within a distance range: a rope, a chain link, a
/// spring.
class DistanceJoint3D extends Joint3D {
  /// A joint from [anchor] to [connectedAnchor]; the distance range is
  /// what they are apart when it is made, unless [minDistance] and
  /// [maxDistance] are given (0 or more).
  DistanceJoint3D({
    super.connectedBody,
    super.anchor,
    super.enabled,
    Vector3? connectedAnchor,
    this.minDistance = -1.0,
    this.maxDistance = -1.0,
    this.springFrequency = 0.0,
    this.springDamping = 0.0,
  }) : connectedAnchor = connectedAnchor ?? Vector3.zero();

  /// Where on the other entity it holds, in that entity's space (in world
  /// space when joined to the world).
  Vector3 connectedAnchor;

  /// The shortest and longest it allows; below 0 means "as it was made".
  double minDistance, maxDistance;

  /// Springiness in Hz (0 = a rigid rope), and damping (1 = critical).
  double springFrequency, springDamping;

  @override
  JointKind3D get kind => JointKind3D.distance;
}

/// Each of the six degrees of freedom free, limited or fixed — anything
/// the other joints cannot express.
class SixDofJoint3D extends Joint3D {
  /// Every axis fixed, by default; [axis] is the joint's X axis and
  /// [normal] its Y, in this entity's space.
  SixDofJoint3D({
    super.connectedBody,
    super.anchor,
    super.enabled,
    Vector3? axis,
    Vector3? normal,
    this.translationX = SixDofAxisMode3D.fixed,
    this.translationY = SixDofAxisMode3D.fixed,
    this.translationZ = SixDofAxisMode3D.fixed,
    this.rotationX = SixDofAxisMode3D.fixed,
    this.rotationY = SixDofAxisMode3D.fixed,
    this.rotationZ = SixDofAxisMode3D.fixed,
    Vector3? translationMin,
    Vector3? translationMax,
    Vector3? rotationMin,
    Vector3? rotationMax,
  }) : axis = axis ?? Vector3(1, 0, 0),
       normal = normal ?? Vector3(0, 1, 0),
       translationMin = translationMin ?? Vector3.zero(),
       translationMax = translationMax ?? Vector3.zero(),
       rotationMin = rotationMin ?? Vector3.zero(),
       rotationMax = rotationMax ?? Vector3.zero();

  /// The joint's X axis, in this entity's space.
  Vector3 axis;

  /// The joint's Y axis, in this entity's space.
  Vector3 normal;

  /// What each axis may do.
  SixDofAxisMode3D translationX, translationY, translationZ;

  /// See [translationX].
  SixDofAxisMode3D rotationX, rotationY, rotationZ;

  /// Limits of limited translation axes, metres.
  Vector3 translationMin, translationMax;

  /// Limits of limited rotation axes, radians.
  Vector3 rotationMin, rotationMax;

  @override
  JointKind3D get kind => JointKind3D.sixDof;

  /// The six modes in the physics engine's order.
  List<SixDofAxisMode3D> get modes => [
    translationX,
    translationY,
    translationZ,
    rotationX,
    rotationY,
    rotationZ,
  ];
}
