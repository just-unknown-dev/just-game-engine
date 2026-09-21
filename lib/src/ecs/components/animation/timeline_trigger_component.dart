library;

import 'dart:ui';

import '../../ecs.dart';

/// What a [TimelineTriggerComponent] does to its player.
enum TimelineTriggerAction {
  nothing,

  /// Plays on from where it is.
  play,

  /// Plays from the start.
  restart,

  /// Plays backwards from where it is — a door that shuts behind you.
  reverse,
  pause,
  stop,
}

/// A rectangle that starts a timeline when a target walks in — and may do
/// something else when it walks out. Centred on the entity's transform.
class TimelineTriggerComponent extends Component {
  TimelineTriggerComponent({
    this.width = 128,
    this.height = 128,
    this.targetName = '',
    this.targetTag = 'player',
    this.playerName = '',
    this.onEnter = TimelineTriggerAction.restart,
    this.onExit = TimelineTriggerAction.nothing,
    this.oneShot = false,
  });

  double width;
  double height;

  /// Who sets it off: the entity with this name, else the first with
  /// [targetTag].
  String targetName;
  String targetTag;

  /// The entity whose Timeline Player this drives; empty means this one.
  String playerName;

  TimelineTriggerAction onEnter;
  TimelineTriggerAction onExit;

  /// Fires on the first entry only.
  bool oneShot;

  // ── Runtime ──────────────────────────────────────────────────────────────

  bool isInside = false;
  bool hasFired = false;

  Rect regionAt(Offset centre) =>
      Rect.fromCenter(center: centre, width: width, height: height);

  @override
  String toString() => 'TimelineTrigger($width×$height, ${onEnter.name})';
}
