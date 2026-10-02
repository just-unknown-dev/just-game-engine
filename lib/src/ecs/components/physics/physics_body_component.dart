library;

import 'dart:ui' show Offset;

import '../../ecs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

/// A body in the physics simulation: how it moves, what it is made of and
/// what it collides with. `PhysicsSystem` makes the simulated body from it
/// and keeps the entity's transform in step.
///
/// The [shape] is in the entity's own space: [offset] moves it off the
/// entity's origin, and the entity's transform scale stretches both — a
/// sprite scaled ×2 and its collider grow together.
class PhysicsBodyComponent extends Component {
  /// The collision shape, in the entity's own space.
  CollisionShape shape;

  /// Where [shape]'s centre is relative to the entity's origin — a feet box
  /// under a tall sprite, say. Scaled with the entity, turned with it.
  Offset offset;

  /// How the body takes part in the simulation: [BodyType.static] never
  /// moves (level geometry), [BodyType.kinematic] moves only as its
  /// velocity says and cannot be pushed (moving platforms),
  /// [BodyType.dynamic] is fully simulated.
  BodyType bodyType;

  /// Sensor mode: reports what overlaps it but stops nothing.
  bool isSensor;

  /// One-way / pass-through platform: solid only to what comes from
  /// [oneWayDirection], passed through from every other side. Honoured on
  /// both the pure-Dart and Box2D backends.
  bool isOneWay;

  /// Which side [isOneWay] makes this body solid from.
  OneWayDirection oneWayDirection;

  /// Mass of a dynamic body. Ignored by static and kinematic ones.
  double mass;

  /// Surface friction, 0 (ice) up: how much a body sliding along this one
  /// is held back. A contact uses the two bodies' friction together.
  double friction;

  /// Bounciness, 0 (none) to 1 (all of it). A contact bounces as much as
  /// the *less* bouncy of its two bodies.
  double restitution;

  /// Linear damping: how much of its velocity a dynamic body loses on its
  /// own each second, as air resistance would. 0 keeps it moving; 1 loses
  /// about two thirds of its speed every second.
  double drag;

  /// Angular damping: as [drag], for spin.
  double angularDamping;

  /// Per-body gravity multiplier. See [PhysicsBody.gravityScale] — this is
  /// what variable jump height is driven through.
  double gravityScale;

  /// Locks rotation: collisions (e.g. friction against a static obstacle)
  /// never change this body's [TransformComponent.angle]. Set this for
  /// characters that should slide along scenery instead of visibly spinning
  /// when they clip a tree, rock, or other body.
  bool fixedRotation;

  /// Continuous collision: a small, fast body is swept from where it was to
  /// where it is each step, so it cannot pass through a thin wall between
  /// two. Costs more; on the native backend only.
  bool isBullet;

  /// Whether the body may fall asleep when it comes to rest. Sleeping bodies
  /// cost nothing until something touches them.
  bool canSleep;

  /// The velocity the body starts with when its simulated body is made — a
  /// thrown crate, a platform already on its way. A `VelocityComponent` on
  /// the entity wins over it.
  Offset initialVelocity;

  /// The spin, in radians per second, the body starts with.
  double initialAngularVelocity;

  /// Which collision layer the body is on: 0 to 15, named in the project's
  /// `PhysicsLayers`.
  int layer;

  /// The layers this body collides with, as a mask — bit `n` for layer `n`.
  /// Null follows the project's grid for [layer]. Two bodies collide only
  /// if each collides with the other's layer.
  int? collidesWith;

  /// Collision group (positive: same group always collides; negative: never
  /// does; 0: layers decide).
  int groupIndex;

  /// Whether `PhysicsSystem.render` should draw this body's collider outline.
  /// Only ever drawn in debug builds regardless of this flag.
  bool showDebugOutline;

  /// Whether this body is currently resting on a surface.
  /// Maintained by [PhysicsSystem] from contact begin/end events — true for
  /// the whole duration a ground-normal contact persists, not just its
  /// first frame.
  bool isGrounded = false;

  /// Which entity this body is currently standing on, if any.
  ///
  /// Maintained by [PhysicsSystem] alongside [isGrounded]. Needed so a rider
  /// can inherit a moving platform's velocity — contact friction alone leaves
  /// the player sliding off the back of anything that moves.
  Entity? groundEntity;

  /// The surface normal of the ground this body stands on: straight up,
  /// `(0, -1)`, on flat ground, tilted on a slope.
  ///
  /// Maintained by [PhysicsSystem] alongside [isGrounded], from the contact
  /// that grounded the body. A character controller reads it to stand still
  /// on a slope and to follow the slope when walking down it.
  Offset groundNormal = const Offset(0, -1);

  /// Create a physics body component
  PhysicsBodyComponent({
    required this.shape,
    this.offset = Offset.zero,
    this.bodyType = BodyType.dynamic,
    this.isSensor = false,
    this.isOneWay = false,
    this.oneWayDirection = OneWayDirection.fromAbove,
    this.mass = 1.0,
    this.friction = 0.2,
    this.restitution = 0.8,
    this.drag = 0.0,
    this.angularDamping = 0.0,
    this.gravityScale = 1.0,
    this.fixedRotation = false,
    this.isBullet = false,
    this.canSleep = true,
    this.initialVelocity = Offset.zero,
    this.initialAngularVelocity = 0.0,
    this.layer = 0,
    this.collidesWith,
    this.groupIndex = 0,
    this.showDebugOutline = true,
  });

  /// Whether the body never moves ([BodyType.static]).
  bool get isStatic => bodyType == BodyType.static;

  /// Whether the body moves only by its velocity ([BodyType.kinematic]).
  bool get isKinematic => bodyType == BodyType.kinematic;

  /// Whether the body is fully simulated ([BodyType.dynamic]).
  bool get isDynamic => bodyType == BodyType.dynamic;

  @override
  String toString() =>
      'PhysicsBody(shape: $shape, m: $mass, type: ${bodyType.name})';
}
