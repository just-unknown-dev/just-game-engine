library;

import '../../ecs.dart';
import '../../../subsystems/physics/physics_engine.dart';

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

  /// Collision layer (for filtering)
  int layer;

  /// Layers this body can collide with
  int collisionMask;

  /// Create a physics body component
  PhysicsBodyComponent({
    required this.shape,
    this.mass = 1.0,
    this.restitution = 0.8,
    this.drag = 0.98,
    this.isStatic = false,
    this.layer = 1,
    this.collisionMask = -1,
  });

  /// Check if can collide with layer
  bool canCollideWith(int otherLayer) {
    return (collisionMask & otherLayer) != 0;
  }

  @override
  String toString() =>
      'PhysicsBody(shape: $shape, m: $mass, static: $isStatic)';
}
