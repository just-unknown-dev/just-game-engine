/// Registering the camera systems in one call.
library;

import '../ecs/ecs.dart';
import 'camera_brain_system.dart';
import 'camera_engine.dart';
import 'camera_target_systems.dart';

/// Adds every system the camera needs to [world]. Call it from boot, where
/// the game registers its other systems.
///
/// In frame order: target groups find their centre, triggers switch
/// cameras, then the brain picks and blends.
void registerCameraSystems(World world, CameraEngine cameraEngine) {
  world
    ..addSystem(CameraTargetGroupSystem())
    ..addSystem(CameraTriggerSystem())
    ..addSystem(CameraBrainSystem(cameraEngine: cameraEngine));
}
