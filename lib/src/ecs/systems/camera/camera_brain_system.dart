/// Runs the camera brain inside the ECS frame.
library;

import '../../../subsystems/camera/camera_system.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';
import 'camera_target_systems.dart';

/// Evaluates the camera brain once per ECS update.
///
/// It runs at [SystemPriorities.camera]: after physics and movement have put
/// everything where it is this frame, and before anything draws — so the
/// camera frames where the player *is*, not where they were.
class CameraBrainSystem extends System {
  CameraBrainSystem({required this.cameraSystem});

  final CameraSystem cameraSystem;

  @override
  int get priority => SystemPriorities.camera;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    VirtualCameraComponent,
  ];

  @override
  void update(double deltaTime) =>
      cameraSystem.brain.evaluate(world, deltaTime);
}

/// Adds every system the camera needs to [world]. Call it from boot, where
/// the game registers its other systems.
///
/// In frame order: target groups find their centre, triggers switch
/// cameras, then the brain picks and blends.
void registerCameraSystems(World world, CameraSystem cameraSystem) {
  world
    ..addSystem(CameraTargetGroupSystem())
    ..addSystem(CameraTriggerSystem())
    ..addSystem(CameraBrainSystem(cameraSystem: cameraSystem));
}
