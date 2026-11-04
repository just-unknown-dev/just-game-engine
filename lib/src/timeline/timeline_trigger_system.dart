library;

import 'dart:ui' show Offset;

import 'timeline_track.dart';
import '../ecs/ecs.dart';
import 'timeline_player_component.dart';
import 'timeline_trigger_component.dart';

/// Runs every [TimelineTriggerComponent]: watches its target cross the
/// rectangle's edge and tells the player what to do.
///
/// A target that names a tag is any entity with it: in co-op the first
/// player in sets it off, and it counts as left once the last one is out.
class TimelineTriggerSystem extends System {
  // Just before the timelines, so a timeline a trigger starts moves this
  // frame.
  @override
  int get priority => SystemPriorities.animation + 3;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    TimelineTriggerComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      if (!entity.isActive) return;
      final trigger = entity.getComponent<TimelineTriggerComponent>()!;
      final inside = _isInside(entity, trigger);
      if (inside == trigger.isInside) return;
      trigger.isInside = inside;
      if (trigger.oneShot && trigger.hasFired) return;

      final action = inside ? trigger.enterAction : trigger.exitAction;
      if (action == TimelineTriggerAction.nothing) return;
      final holder = trigger.playerName.isEmpty
          ? entity
          : TrackBinding.name(trigger.playerName).resolve(world, entity);
      final player = holder?.getComponent<TimelinePlayerComponent>();
      if (player == null) return;
      // One shot means one entry; what leaving does still happens once.
      if (!inside || trigger.exitAction == TimelineTriggerAction.nothing) {
        trigger.hasFired = true;
      }
      _act(player, action);
    });
  }

  static void _act(
    TimelinePlayerComponent player,
    TimelineTriggerAction action,
  ) {
    switch (action) {
      case TimelineTriggerAction.nothing:
        break;
      case TimelineTriggerAction.play:
        player.forwards();
      case TimelineTriggerAction.restart:
        // From the start as authored: a direction an earlier action set
        // (reverse) is forgotten, and a player authored to run backwards
        // runs backwards from its end.
        player
          ..resetSpeed()
          ..restart();
      case TimelineTriggerAction.reverse:
        player.reverse();
      case TimelineTriggerAction.pause:
        player.pause();
      case TimelineTriggerAction.stop:
        player.stop();
    }
  }

  bool _isInside(Entity entity, TimelineTriggerComponent trigger) {
    final centre = entity.getComponent<TransformComponent>()!.position;
    final region = trigger.regionAt(Offset(centre.x, centre.y));
    for (final target in trigger.target.resolveAll(world, entity)) {
      final at = target.getComponent<TransformComponent>()?.position;
      if (at != null && region.contains(Offset(at.x, at.y))) return true;
    }
    return false;
  }
}
