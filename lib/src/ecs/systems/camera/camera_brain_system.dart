/// Runs the camera brain inside the ECS frame.
library;

import 'camera_brain.dart';
import 'camera_system.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../../base/system_priorities.dart';
import 'camera_target_systems.dart';

/// Evaluates the camera brain once per ECS update — or, with the brain's
/// `updateMode` set to [CameraUpdateMode.frame], once per rendered frame
/// (it is a [FrameSystem]), following targets between updates.
///
/// It runs at [SystemPriorities.camera]: after physics and movement have put
/// everything where it is this frame, and before anything draws — so the
/// camera frames where the player *is*, not where they were.
class CameraBrainSystem extends System implements FrameSystem {
  /// A system evaluating the brain of [cameraSystem], which must be
  /// initialized before the first update.
  CameraBrainSystem({required this.cameraSystem});

  /// Owner of the brain this system evaluates.
  final CameraSystem cameraSystem;

  @override
  int get priority => SystemPriorities.camera;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    VirtualCameraComponent,
  ];

  @override
  void update(double deltaTime) {
    final brain = cameraSystem.brain;
    if (brain.updateMode == CameraUpdateMode.fixed) {
      brain.evaluate(world, deltaTime);
    } else {
      brain.sampleTargets(world);
    }
  }

  @override
  void frame(double deltaTime, double alpha) {
    final brain = cameraSystem.brain;
    if (brain.updateMode != CameraUpdateMode.frame) return;
    brain.evaluate(world, deltaTime, alpha: alpha);
  }
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
