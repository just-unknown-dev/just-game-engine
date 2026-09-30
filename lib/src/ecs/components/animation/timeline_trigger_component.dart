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
    EntityTarget target = const EntityTarget.tag('player'),
    @Deprecated('Use target: EntityTarget.name(…).') String? targetName,
    @Deprecated('Use target: EntityTarget.tag(…).') String? targetTag,
    this.playerName = '',
    this.onEnter = TimelineTriggerAction.restart,
    this.onExit = TimelineTriggerAction.nothing,
    this.oneShot = false,
  }) : target = targetName != null || targetTag != null
           ? EntityTarget.fromNameOrTag(targetName ?? '', targetTag ?? '')
           : target;

  double width;
  double height;

  /// Who sets it off: one entity by name, or any entity with a tag — in
  /// co-op, whichever player walks in first.
  EntityTarget target;

  /// The name [target] names, or empty.
  @Deprecated('Use target.')
  String get targetName => target.isName ? target.value : '';

  /// The tag [target] names, or empty.
  @Deprecated('Use target.')
  String get targetTag => target.isTag ? target.value : '';

  @Deprecated('Use target = EntityTarget.name(…).')
  set targetName(String value) => target = target.afterSettingName(value);

  @Deprecated('Use target = EntityTarget.tag(…).')
  set targetTag(String value) => target = target.afterSettingTag(value);

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
