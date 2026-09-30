/// A shot: one candidate view of the world.
library;

import 'dart:math' as math;

import '../../../ecs/ecs.dart';
import '../../../subsystems/camera/camera_lens.dart';

/// When a camera that is not live keeps evaluating its pipeline.
enum CameraStandbyUpdate {
  /// Only while live or blending out. Its first frame live is a snap to
  /// wherever its target is.
  never,

  /// Every frame, so it is already settled on its target when it goes live.
  always,
}

/// Makes its entity a virtual camera.
///
/// A virtual camera is a *shot*, not the camera: the brain picks the enabled
/// one with the highest [priority] and blends to it. Its entity's transform
/// is where the shot sits when nothing moves it; the stage components on the
/// same entity — framing, confiner, noise — are what move it.
///
/// The target is named rather than referenced, by entity name or by tag, and
/// looked up each frame. That is what lets a level's camera follow a player
/// who does not exist until the game spawns one.
class VirtualCameraComponent extends Component {
  VirtualCameraComponent({
    this.priority = 10,
    this.enabled = true,
    this.followName = '',
    this.followTag = '',
    this.zoom = 1.0,
    this.dutch = 0.0,
    this.standbyUpdate = CameraStandbyUpdate.never,
    this.projection = CameraProjection.orthographic,
    this.fieldOfView = math.pi / 3,
    this.nearClip = -10000,
    this.farClip = 10000,
  });

  /// Higher wins. Between equals, the one activated most recently.
  int priority;

  /// A disabled camera is never live and never evaluated.
  bool enabled;

  /// Name of the entity to follow. Tried before [followTag].
  String followName;

  /// `TagComponent.tag` of the entity to follow.
  String followTag;

  /// The lens: `1` = one world unit per pixel, larger is closer.
  double zoom;

  /// Roll added to the entity's own rotation, in radians.
  double dutch;

  CameraStandbyUpdate standbyUpdate;

  /// Orthographic — a 2-D shot, sized by [zoom] — or perspective.
  CameraProjection projection;

  /// Vertical field of view in radians, for a perspective shot.
  double fieldOfView;

  /// Nearest distance drawn. At or behind the camera, a perspective shot
  /// uses 1 instead (an orthographic one sees behind itself).
  double nearClip;

  /// Furthest distance drawn.
  double farClip;

  /// The lens these describe.
  CameraLens get lens => switch (projection) {
    CameraProjection.orthographic => CameraLens.orthographic(
      near: nearClip,
      far: farClip,
    ),
    CameraProjection.perspective => CameraLens.perspective(
      fieldOfView: fieldOfView,
      near: nearClip > 0 ? nearClip : 1,
      far: farClip,
    ),
  };

  bool get hasTarget => followName.isNotEmpty || followTag.isNotEmpty;

  @override
  String toString() => 'VirtualCamera(priority: $priority, zoom: $zoom)';
}
