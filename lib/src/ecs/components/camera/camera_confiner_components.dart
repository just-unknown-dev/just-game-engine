/// Keeping a shot inside the level.
library;

import 'package:flutter/painting.dart' show Offset, Rect;

import '../../../ecs/ecs.dart';

/// Something that can say where a camera is allowed to look.
///
/// A confiner asks the entity it names for a component that implements this.
/// [CameraBoundsComponent] is the engine's; a kit's own "level bounds"
/// component implements it too, so one rectangle serves the gameplay rules
/// and the camera.
abstract interface class CameraBoundsSource {
  /// The allowed area in world space, for an entity at [entityPosition].
  Rect cameraBoundsAt(Offset entityPosition);
}

/// A rectangle a camera can be confined to, centred on its entity.
///
/// It lives on an entity of its own rather than on the camera, so it is a
/// thing in the level: visible, selectable, resized with the same handles as
/// a shape — and shared by every camera that names it.
class CameraBoundsComponent extends Component implements CameraBoundsSource {
  CameraBoundsComponent({this.width = 4000, this.height = 800});

  double width;
  double height;

  @override
  Rect cameraBoundsAt(Offset entityPosition) =>
      Rect.fromCenter(center: entityPosition, width: width, height: height);

  @override
  String toString() => 'CameraBounds($width×$height)';
}

/// Keeps a virtual camera's **view** — not just its centre — inside the
/// bounds of the entity called [boundsName].
///
/// When the bounds are narrower than the view on an axis there is nowhere
/// legal to be, so the camera centres on them instead of jittering between
/// two wrong answers.
class CameraConfinerComponent extends Component {
  CameraConfinerComponent({this.boundsName = '', this.damping = 0.0});

  /// Name of the entity carrying a [CameraBoundsSource].
  String boundsName;

  /// Seconds for the confiner's push to take hold. `0` is a hard wall; a
  /// little softens the moment a fast camera reaches the edge of the level.
  double damping;

  @override
  String toString() => 'CameraConfiner($boundsName)';
}
