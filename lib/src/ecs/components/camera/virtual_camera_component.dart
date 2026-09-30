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
/// The target is an [EntityTarget] — an entity name or a tag — looked up
/// each frame. That is what lets a level's camera follow a player who does
/// not exist until the game spawns one.
class VirtualCameraComponent extends Component {
  VirtualCameraComponent({
    this.priority = 10,
    this.enabled = true,
    EntityTarget follow = EntityTarget.none,
    @Deprecated('Use follow: EntityTarget.name(…).') String? followName,
    @Deprecated('Use follow: EntityTarget.tag(…).') String? followTag,
    this.zoom = 1.0,
    this.dutch = 0.0,
    this.standbyUpdate = CameraStandbyUpdate.never,
    this.projection = CameraProjection.orthographic,
    this.fieldOfView = math.pi / 3,
    this.nearClip = -10000,
    this.farClip = 10000,
  }) : follow = followName != null || followTag != null
           ? EntityTarget.fromNameOrTag(followName ?? '', followTag ?? '')
           : follow;

  /// Higher wins. Between equals, the one activated most recently.
  int priority;

  /// A disabled camera is never live and never evaluated.
  bool enabled;

  /// Who it follows: an entity by name, or the first entity with a tag.
  EntityTarget follow;

  /// The name [follow] names, or empty.
  @Deprecated('Use follow.')
  String get followName => follow.isName ? follow.value : '';

  @Deprecated('Use follow = EntityTarget.name(…).')
  set followName(String value) => follow = follow.afterSettingName(value);

  /// The tag [follow] names, or empty.
  @Deprecated('Use follow.')
  String get followTag => follow.isTag ? follow.value : '';

  @Deprecated('Use follow = EntityTarget.tag(…).')
  set followTag(String value) => follow = follow.afterSettingTag(value);

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

  bool get hasTarget => !follow.isNone;

  @override
  String toString() => 'VirtualCamera(priority: $priority, zoom: $zoom)';
}
