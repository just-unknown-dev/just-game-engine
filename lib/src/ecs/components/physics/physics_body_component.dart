library;

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

  /// One-way / pass-through platform flag.
  /// When true, dynamic bodies moving upward (velocity.dy < 0) pass through
  /// this body without collision resolution.
  bool isOneWay;

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
    this.isSensor = false,
    this.categoryBits = 0x0001,
    this.maskBits = 0xFFFF,
    this.groupIndex = 0,
    this.showDebugOutline = true,
  });

  @override
  String toString() =>
      'PhysicsBody(shape: $shape, m: $mass, static: $isStatic)';
}
