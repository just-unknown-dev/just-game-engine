library;

import 'dart:ui';

import '../../ecs.dart';

/// What a [TimelineTriggerComponent] does to its player.
enum TimelineTriggerAction {
  /// Leaves the player alone.
  nothing,

  /// Plays on from where it is.
  play,

  /// Plays from the start.
  restart,

  /// Plays backwards from where it is — a door that shuts behind you.
  reverse,

  /// Holds the player where it is.
  pause,

  /// Stops the player and rewinds it to the start of its range.
  stop,
}

/// A rectangle that starts a timeline when a target walks in — and may do
/// something else when it walks out. Centred on the entity's transform.
class TimelineTriggerComponent extends Component {
  /// A 128 × 128 rectangle set off by any entity tagged `player`: it
  /// restarts this entity's own Timeline Player on entry, does nothing on
  /// exit, and fires every time.
  TimelineTriggerComponent({
    this.width = 128,
    this.height = 128,
    this.target = const EntityTarget.tag('player'),
    this.playerName = '',
    this.onEnter = TimelineTriggerAction.restart,
    this.onExit = TimelineTriggerAction.nothing,
    this.oneShot = false,
  });

  /// Width of the rectangle, in world units. The transform's scale and
  /// rotation are not applied.
  double width;

  /// Height of the rectangle, in world units. The transform's scale and
  /// rotation are not applied.
  double height;

  /// Who sets it off: one entity by name, or any entity with a tag — in
  /// co-op, whichever player walks in first.
  EntityTarget target;

  /// The entity whose Timeline Player this drives; empty means this one.
  String playerName;

  /// What the player is told to do when a target comes in.
  TimelineTriggerAction onEnter;

  /// What the player is told to do when the last target inside has left.
  TimelineTriggerAction onExit;

  /// Fires on the first entry only.
  bool oneShot;

  // ── Runtime ──────────────────────────────────────────────────────────────

  /// Whether a target was inside at the last check. The system acts when
  /// this changes.
  bool isInside = false;

  /// Whether the trigger has done its entry — and its exit, when [onExit]
  /// does something. From then on a [oneShot] trigger does nothing.
  bool hasFired = false;

  /// The rectangle this trigger covers, centred on [centre] (the entity's
  /// position). A target is inside when its own position is.
  Rect regionAt(Offset centre) =>
      Rect.fromCenter(center: centre, width: width, height: height);

  @override
  String toString() => 'TimelineTrigger($width×$height, ${onEnter.name})';
}
