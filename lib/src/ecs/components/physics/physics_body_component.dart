library;

import 'dart:ui' show Offset;

import '../../ecs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

/// Physics body component - Collision and physics properties
class PhysicsBodyComponent extends Component {
  /// The physical shape used for collision detection
  CollisionShape shape;

  /// Mass
  double mass;

  /// Restitution (bounciness, 0-1)
  double restitution;

  /// Drag coefficient
  double drag;

  /// Is this a static body (doesn't move)
  bool isStatic;

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

  /// One-way / pass-through platform flag.
  ///
  /// When true, a contact against this body is only resolved when approached
  /// from [oneWayDirection]; otherwise the other body passes through. Honoured
  /// on both the pure-Dart and Box2D backends.
  bool isOneWay;

  /// Which side [isOneWay] makes this body solid from.
  OneWayDirection oneWayDirection;

  /// How this body participates in the simulation.
  ///
  /// [isStatic] is the older, coarser switch and still wins when set — this
  /// exists so a body can be *kinematic*: moved only by explicit velocity
  /// writes and immovable by anything that pushes it, which is what a moving
  /// platform needs.
  BodyType bodyType;

  /// Per-body gravity multiplier. See [PhysicsBody.gravityScale] — this is
  /// what variable jump height is driven through.
  double gravityScale;

  /// Locks rotation: collisions (e.g. friction against a static obstacle)
  /// never change this body's [TransformComponent.rotation]. Set this for
  /// top-down characters that should slide along scenery instead of
  /// visibly spinning when they clip a tree, rock, or other body.
  bool fixedRotation;

  /// Sensor mode: detects overlaps but does not resolve collisions.
  bool isSensor;

  /// Collision filter category bits (Box2D / PhysicsEngine filtering).
  int categoryBits;

  /// Collision filter mask bits — collides only when (categoryBits & maskBits) != 0.
  int maskBits;

  /// Collision group index (positive: always collide; negative: never collide; 0: use mask).
  int groupIndex;

  /// Whether [PhysicsSystem.render] should draw this body's collider outline.
  /// Only ever drawn in debug builds regardless of this flag.
  bool showDebugOutline;

  /// Create a physics body component
  PhysicsBodyComponent({
    required this.shape,
    this.mass = 1.0,
    this.restitution = 0.8,
    this.drag = 0.98,
    this.isStatic = false,
    this.isOneWay = false,
    this.oneWayDirection = OneWayDirection.fromAbove,
    this.bodyType = BodyType.dynamic,
    this.gravityScale = 1.0,
    this.fixedRotation = false,
    this.isSensor = false,
    this.categoryBits = 0x0001,
    this.maskBits = 0xFFFF,
    this.groupIndex = 0,
    this.showDebugOutline = true,
  });

  /// The body type actually simulated, folding in the older [isStatic] flag.
  BodyType get effectiveBodyType => isStatic ? BodyType.static : bodyType;

  @override
  String toString() =>
      'PhysicsBody(shape: $shape, m: $mass, type: ${effectiveBodyType.name})';
}
