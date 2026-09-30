/// Bridge system that synchronises subsystem [PhysicsBody] results back to
/// ECS [TransformComponent] each frame.
///
/// Runs at priority 89 (just **after** PhysicsSystem at 90) so the subsystem
/// physics step has already advanced positions before we copy them into ECS.
library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Syncs subsystem [PhysicsBody] → ECS [TransformComponent] each frame.
class PhysicsBridgeSystem extends System {
  /// Runs just after the ECS PhysicsSystem.
  @override
  int get priority => SystemPriorities.physics - 1; // 89

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    PhysicsBodyRefComponent,
  ];

  @override
  void update(double deltaTime) {
    // After the subsystem PhysicsEngine has run (driven by Engine.update),
    // copy body positions back into the ECS TransformComponent.
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final ref = entity.getComponent<PhysicsBodyRefComponent>()!;
      final body = ref.body;

      // Capture previous pose for sub-frame render interpolation.
      transform.capturePrevious();

      // Write subsystem body pose → ECS transform (z and the X/Y tilts are
      // the 2-D body's to keep, not to touch).
      transform.setPlanarPose(body.position.x, body.position.y, body.angle);

      // Optionally sync velocity if the entity has a VelocityComponent
      final vel = entity.getComponent<VelocityComponent>();
      if (vel != null) {
        vel.setVelocityXY(body.velocity.x, body.velocity.y);
      }
    });
  }
}
