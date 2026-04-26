library;

import '../../ecs/ecs.dart';

/// Fired on the ECS event bus when an achievement is first unlocked.
///
/// Subscribe via [EventBus.on]:
/// ```dart
/// world.events.on<AchievementUnlockedEvent>((e) {
///   showUnlockToast(e.name);
/// });
/// ```
class AchievementUnlockedEvent extends GameEvent {
  final String id;
  final String name;
  AchievementUnlockedEvent({required this.id, required this.name});
}

/// Fired on the ECS event bus when a progress achievement advances.
///
/// [percentComplete] is in [0.0, 100.0]. When the goal is reached this event
/// fires alongside [AchievementUnlockedEvent].
class AchievementProgressUpdatedEvent extends GameEvent {
  final String id;
  final double percentComplete;
  AchievementProgressUpdatedEvent({
    required this.id,
    required this.percentComplete,
  });
}
