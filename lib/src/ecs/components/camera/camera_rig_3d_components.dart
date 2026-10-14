/// 3-D camera rigs: orbiting a target, looking from its eyes, aiming at it.
library;

import 'package:just_dart/just_dart.dart';

import '../../../ecs/ecs.dart';

/// Body stage: a third-person camera circling its target at [distance],
/// turned by [yaw] and [pitch].
///
/// Gameplay turns the shot by writing [yaw] and [pitch] (from look input,
/// say); the stage keeps the pitch inside [minPitch]..[maxPitch] and eases
/// the pivot after the target over [damping] seconds. Angles follow the
/// camera's: [pitch] below zero looks down (the engine's +Y is down), [yaw]
/// turns about the up axis with 0 looking along +Z.
class OrbitFollowComponent extends Component {
  /// An orbit 4 m behind and a little above the target's head.
  OrbitFollowComponent({
    this.distance = 4.0,
    this.minDistance = 1.0,
    this.maxDistance = 12.0,
    this.yaw = 0.0,
    this.pitch = -0.3,
    this.minPitch = -1.3,
    this.maxPitch = 0.6,
    Vector3? pivot,
    this.shoulder = 0.0,
    this.damping = 0.1,
  }) : pivot = pivot ?? Vector3(0, -1.5, 0);

  /// Metres from the pivot to the camera.
  double distance;

  /// The closest [distance] may be set to.
  double minDistance;

  /// The furthest [distance] may be set to.
  double maxDistance;

  /// Turn about the up axis, radians.
  double yaw;

  /// Tilt, radians: below zero looks down.
  double pitch;

  /// The lowest [pitch] (looking down the most).
  double minPitch;

  /// The highest [pitch] (looking up the most).
  double maxPitch;

  /// Where the camera circles, from the target's origin, in world axes
  /// (metres; -Y is up, so (0, -1.5, 0) is head height).
  Vector3 pivot;

  /// Sideways offset from the pivot, metres: over-the-shoulder framing.
  double shoulder;

  /// Seconds the pivot takes to catch up with the target (0 snaps).
  double damping;
}

/// Body stage: the camera at its target's eyes, turned by [yaw] and
/// [pitch] — a first-person view.
class FirstPersonComponent extends Component {
  /// Eyes 1.7 m up, looking ahead.
  FirstPersonComponent({
    Vector3? eye,
    this.yaw = 0.0,
    this.pitch = 0.0,
    this.minPitch = -1.45,
    this.maxPitch = 1.45,
  }) : eye = eye ?? Vector3(0, -1.7, 0);

  /// The eyes, from the target's origin, in world axes (metres).
  Vector3 eye;

  /// Turn about the up axis, radians.
  double yaw;

  /// Tilt, radians: below zero looks down.
  double pitch;

  /// The lowest [pitch].
  double minPitch;

  /// The highest [pitch].
  double maxPitch;
}

/// Aim stage: points the camera at its target, wherever the body put it.
class LookAtComponent extends Component {
  /// Aims at the target's origin raised by [offset].
  LookAtComponent({Vector3? offset, this.damping = 0.0})
    : offset = offset ?? Vector3.zero();

  /// Where on the target to look, from its origin, in world axes (metres).
  Vector3 offset;

  /// Seconds the aim takes to catch up (0 snaps).
  double damping;
}
