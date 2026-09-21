library;

import 'dart:ui' show Offset;

import '../../../subsystems/timeline/timeline_track.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

/// Runs every [TimelineTriggerComponent]: watches its target cross the
/// rectangle's edge and tells the player what to do.
class TimelineTriggerSystem extends System {
  // Just before the timelines, so a timeline a trigger starts moves this
  // frame.
  @override
  int get priority => SystemPriorities.animation + 3;

  @override
  List<Type> get requiredComponents => [
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

      final action = inside ? trigger.onEnter : trigger.onExit;
      if (action == TimelineTriggerAction.nothing) return;
      final holder = trigger.playerName.isEmpty
          ? entity
          : TrackBinding.name(trigger.playerName).resolve(world, entity);
      final player = holder?.getComponent<TimelinePlayerComponent>();
      if (player == null) return;
      // One shot means one entry; what leaving does still happens once.
      if (!inside || trigger.onExit == TimelineTriggerAction.nothing) {
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
        player
          ..speed = player.speed.abs()
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
    Entity? target;
    if (trigger.targetName.isNotEmpty) {
      target = TrackBinding.name(trigger.targetName).resolve(world, entity);
    }
    if (target == null && trigger.targetTag.isNotEmpty) {
      target = TrackBinding.tag(trigger.targetTag).resolve(world, entity);
    }
    final at = target?.getComponent<TransformComponent>()?.position;
    final centre = entity.getComponent<TransformComponent>()!.position;
    if (at == null) return false;
    return trigger
        .regionAt(Offset(centre.x, centre.y))
        .contains(Offset(at.x, at.y));
  }
}
