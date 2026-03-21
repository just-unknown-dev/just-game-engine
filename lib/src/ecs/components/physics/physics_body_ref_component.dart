/// Component that links an ECS entity to a subsystem [PhysicsBody].
///
/// Attach this component to any entity that also has a [TransformComponent]
/// and should be driven by the subsystem [PhysicsEngine].
/// The [PhysicsBridgeSystem] will keep them in sync each frame.
library;

import '../../ecs.dart';
import '../../../subsystems/physics/physics_engine.dart';

/// Links an entity to a subsystem [PhysicsBody] for automatic position sync.
class PhysicsBodyRefComponent extends Component {
  /// The subsystem physics body managed by [PhysicsEngine].
  final PhysicsBody body;

  PhysicsBodyRefComponent(this.body);

  @override
  String toString() => 'PhysicsBodyRef(body: $body)';
}
