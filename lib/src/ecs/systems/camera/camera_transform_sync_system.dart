library;

import 'package:flutter/foundation.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';
import '../../../subsystems/camera/camera_system.dart';

/// Mirrors the scene's camera entity — an entity carrying both
/// [TransformComponent] and [CameraComponent] — onto [CameraSystem.mainCamera]
/// every frame.
///
/// This runs unconditionally, independent of [CameraFollowSystem]: whatever
/// currently moves the camera entity's transform (follow behaviors, manual
/// gizmo placement, or Timeline keyframe animation) is what the player sees.
///
/// ### Setup
/// ```dart
/// world.addSystem(CameraTransformSyncSystem(cameraSystem: engine.cameraSystem));
/// ```
class CameraTransformSyncSystem extends System {
  final CameraSystem cameraSystem;

  CameraTransformSyncSystem({required this.cameraSystem});

  /// Optional gate — while this returns `true` (e.g. the level editor is
  /// open and authoring, not the player actually playing), this system does
  /// nothing so the camera entity doesn't hijack the authoring viewport
  /// (there's no manual pan/zoom to fight it with).
  bool Function()? isAuthoringActive;

  bool _warnedMultipleCameras = false;

  @override
  int get priority => SystemPriorities.camera - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, CameraComponent];

  @override
  void update(double deltaTime) {
    if (isAuthoringActive?.call() ?? false) return;

    final cameraEntities = world.query(requiredComponents);
    if (cameraEntities.isEmpty) return;

    if (cameraEntities.length > 1 && !_warnedMultipleCameras) {
      _warnedMultipleCameras = true;
      debugPrint(
        '[CameraTransformSyncSystem] Multiple entities carry CameraComponent; '
        'only the first one found will drive the main camera.',
      );
    }

    final entity = cameraEntities.first;
    final transform = entity.getComponent<TransformComponent>()!;
    final camComponent = entity.getComponent<CameraComponent>()!;

    cameraSystem.mainCamera
      ..setPosition(transform.position.toOffset(), smooth: false)
      ..rotation = transform.rotation
      ..setZoom(camComponent.zoom, smooth: false);
  }
}
