library;

import 'package:flutter/material.dart';

import '../../../ecs/ecs.dart';

/// Marks an entity as the scene's camera.
///
/// Presence of this component on an entity is what identifies it as the
/// camera — there is no separate boolean flag. [CameraTransformSyncSystem]
/// mirrors this entity's [TransformComponent] position/rotation and [zoom]
/// onto [CameraSystem.mainCamera] every frame; [CameraFollowSystem] targets
/// this entity's transform instead of the camera directly when one is
/// present in the world.
///
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(position: Vector3.fromXY(2000, 400)),
///   CameraComponent(bounds: Rect.fromLTWH(0, 0, 4000, 800)),
/// ], name: 'MainCamera');
/// ```
class CameraComponent extends Component {
  /// Zoom level (`1.0` = normal, `>1` = zoom-in, `<1` = zoom-out).
  double zoom;

  /// World-space rectangle the camera will not show outside of.
  Rect bounds;

  CameraComponent({
    this.zoom = 1.0,
    this.bounds = const Rect.fromLTWH(0, 0, 4000, 800),
  });

  @override
  String toString() => 'Camera(zoom: $zoom, bounds: $bounds)';
}
