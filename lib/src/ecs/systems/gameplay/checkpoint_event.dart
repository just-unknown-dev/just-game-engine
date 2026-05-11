library;

import '../../ecs.dart';
import 'package:just_dart/just_dart.dart';

/// Fired when a player entity touches and activates a checkpoint for the
/// first time.
class CheckpointActivatedEvent extends GameEvent {
  /// The checkpoint entity that was activated.
  final Entity checkpointEntity;

  /// The player entity that triggered activation.
  final Entity playerEntity;

  /// World-space respawn position stored by the checkpoint.
  final Vector3 respawnPosition;

  CheckpointActivatedEvent({
    required this.checkpointEntity,
    required this.playerEntity,
    required this.respawnPosition,
  });
}

/// Fired by [CheckpointSystem.respawn] to request the player be moved to
/// their last saved respawn position.
class PlayerRespawnEvent extends GameEvent {
  /// The player entity to respawn.
  final Entity playerEntity;

  /// World-space position the player should be moved to.
  final Vector3 respawnPosition;

  PlayerRespawnEvent({
    required this.playerEntity,
    required this.respawnPosition,
  });
}
