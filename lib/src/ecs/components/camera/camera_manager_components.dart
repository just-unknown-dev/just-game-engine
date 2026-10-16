/// Cameras made of cameras, and a camera on rails.
///
/// A manager is a virtual camera whose shot comes from its **child**
/// entities' virtual cameras. Children are not candidates on their own: the
/// brain sees only the manager, with the manager's priority.
library;

import 'package:flutter/painting.dart' show Offset;

import '../../../ecs/ecs.dart';

/// A named state a state-driven camera can read: `'grounded'`, `'falling'`,
/// `'boss'`. The game writes it; the camera follows it.
class CameraStateComponent extends Component {
  /// A state holder starting at [state]; empty — no state — by default.
  CameraStateComponent({this.state = ''});

  /// The current state's name, matched exactly against the keys of
  /// [CameraStateDrivenComponent.states]. Write it whenever it changes.
  String state;

  @override
  String toString() => 'CameraState($state)';
}

/// Manager: shows the child mapped to the current state of another entity.
class CameraStateDrivenComponent extends Component {
  /// Reads the first entity tagged `player` by default, with no states
  /// mapped yet and half-second blends. With neither a mapped nor a
  /// [defaultChild] camera to show, the first child is shown.
  CameraStateDrivenComponent({
    this.source = const EntityTarget.tag('player'),
    Map<String, String>? states,
    this.defaultChild = '',
    this.blend = 0.5,
  }) : states = states ?? {};

  /// The entity carrying the [CameraStateComponent]: one by name, or the
  /// first with a tag.
  EntityTarget source;

  /// State → name of the child camera to show.
  Map<String, String> states;

  /// Shown for a state with no entry, and while the source does not exist.
  String defaultChild;

  /// Seconds to blend between children.
  double blend;

  @override
  String toString() => 'CameraStateDriven(${states.length} states)';
}

/// One shot of a blend list.
class CameraBlendStep {
  /// A step showing [child] for a one-second hold after a half-second
  /// blend, unless told otherwise.
  CameraBlendStep({this.child = '', this.hold = 1.0, this.blend = 0.5});

  /// Reads the `{child, hold, blend}` map [toJson] writes. A missing key
  /// takes the constructor's default; a value of the wrong type throws.
  factory CameraBlendStep.fromJson(Map<Object?, Object?> json) =>
      CameraBlendStep(
        child: json['child'] as String? ?? '',
        hold: (json['hold'] as num?)?.toDouble() ?? 1.0,
        blend: (json['blend'] as num?)?.toDouble() ?? 0.5,
      );

  /// Name of the child camera.
  String child;

  /// Seconds the shot is held once it has blended in.
  double hold;

  /// Seconds to blend in from the previous shot. The first step cuts.
  double blend;

  /// This step as a JSON map with the keys `child`, `hold` and `blend`.
  Map<String, dynamic> toJson() => {
    'child': child,
    'hold': hold,
    'blend': blend,
  };
}

/// Manager: plays its children as a sequence of shots — a cutscene.
///
/// It starts over each time it goes live — whatever its
/// `VirtualCameraComponent.standbyUpdate` — so a cutscene is triggered by
/// raising this camera's priority and ends by lowering it. As a child of
/// another manager it is never live itself: it starts over when it comes
/// back after sitting out a frame.
class CameraBlendListComponent extends Component {
  /// A list playing [steps] (none when null) once through, unless [loop].
  CameraBlendListComponent({List<CameraBlendStep>? steps, this.loop = false})
    : steps = steps ?? [];

  /// The shots, in playing order. Empty, the manager shows its own shot.
  List<CameraBlendStep> steps;

  /// Back to the first shot after the last; otherwise the last is held.
  bool loop;

  @override
  String toString() => 'CameraBlendList(${steps.length} steps)';
}

/// Manager: a weighted mix of its children, all at once.
class CameraMixerComponent extends Component {
  /// A mixer over [weights] (none when null). A child with no weight, or
  /// one of zero or less, is left out; with no child weighted, the manager
  /// shows its own shot.
  CameraMixerComponent({Map<String, double>? weights})
    : weights = weights ?? {};

  /// Child name → weight. Animate these to steer between shots by hand.
  Map<String, double> weights;

  @override
  String toString() => 'CameraMixer(${weights.length})';
}

/// Body: a camera that rides a path.
class CameraDollyComponent extends Component {
  /// An open track through [waypoints] (none when null) that follows the
  /// target, easing over 0.4 seconds. Fewer than two points, or a track of
  /// no length, leaves the camera where it is.
  CameraDollyComponent({
    List<Offset>? waypoints,
    this.closed = false,
    this.autoDolly = true,
    this.pathPosition = 0.0,
    this.damping = 0.4,
  }) : waypoints = waypoints ?? [];

  /// The track, in world space.
  List<Offset> waypoints;

  /// Whether the last point joins the first.
  bool closed;

  /// Rides to the point on the track nearest the followed entity. Off, the
  /// camera sits at [pathPosition].
  bool autoDolly;

  /// Where on the track, `0`–`1` by length. Animate it for a scripted move.
  double pathPosition;

  /// Seconds to reach a new place on the track.
  double damping;

  @override
  String toString() => 'CameraDolly(${waypoints.length} points)';
}
