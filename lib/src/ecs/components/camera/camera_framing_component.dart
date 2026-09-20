/// Body stage: keep the target where you want it on screen.
library;

import '../../../ecs/ecs.dart';

/// Frames a virtual camera's target on screen.
///
/// Everything is in **screen fractions**, so a shot reads the same at any
/// zoom and any window size: `0.2` is a fifth of the view.
///
/// ```
/// ┌───────────── soft zone ─────────────┐   outside: the camera keeps up
/// │        ┌──── dead zone ────┐        │   no matter the damping
/// │        │   target rests    │        │   between: the camera eases
/// │        │   here, no move   │        │   toward the target
/// │        └───────────────────┘        │   inside: the camera holds still
/// └─────────────────────────────────────┘
/// ```
class CameraFramingComponent extends Component {
  CameraFramingComponent({
    this.screenX = 0.0,
    this.screenY = 0.0,
    this.deadZoneWidth = 0.1,
    this.deadZoneHeight = 0.1,
    this.softZoneWidth = 0.8,
    this.softZoneHeight = 0.8,
    this.dampingX = 0.5,
    this.dampingY = 0.5,
    this.lookaheadTime = 0.0,
    this.lookaheadSmoothing = 0.3,
    this.followX = true,
    this.followY = true,
  });

  /// Where the target sits, from the centre: `-0.5` is the left edge, `0.5`
  /// the right. A platformer often wants it a little below the middle.
  double screenX;
  double screenY;

  /// The target moves freely inside this without the camera moving.
  double deadZoneWidth;
  double deadZoneHeight;

  /// The target never leaves this, however heavy the damping.
  double softZoneWidth;
  double softZoneHeight;

  /// Seconds for the camera to close 99% of the gap on each axis. `0` is
  /// rigid.
  double dampingX;
  double dampingY;

  /// Looks this many seconds ahead along the target's velocity. `0` is off.
  double lookaheadTime;

  /// Seconds the velocity used for lookahead takes to settle — without it
  /// every change of direction jerks the view.
  double lookaheadSmoothing;

  /// Off holds that axis at the camera entity's own position: a room that
  /// scrolls sideways only, a boss arena that does not scroll at all.
  bool followX;
  bool followY;

  @override
  String toString() =>
      'CameraFraming(dead: $deadZoneWidth×$deadZoneHeight, '
      'soft: $softZoneWidth×$softZoneHeight)';
}
