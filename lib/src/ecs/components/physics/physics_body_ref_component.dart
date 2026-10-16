/// Component that links an ECS entity to a subsystem [PhysicsBody].
///
/// Attach this component to any entity that also has a [TransformComponent]
/// and should be driven by the subsystem [PhysicsEngine].
/// `PhysicsSystem` keeps them in sync each frame.
library;

import '../../ecs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

/// Links an entity to a subsystem [PhysicsBody] for automatic position sync.
class PhysicsBodyRefComponent extends Component {
  /// The subsystem physics body managed by [PhysicsEngine].
  final PhysicsBody body;

  /// A link to [body]. `PhysicsSystem` attaches one when it adds an
  /// entity's body to the physics engine.
  PhysicsBodyRefComponent(this.body);

  @override
  String toString() => 'PhysicsBodyRef(body: $body)';
}
