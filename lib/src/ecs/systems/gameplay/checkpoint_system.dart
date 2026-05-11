library;

import 'package:flutter/painting.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';
import '../../../math/vector3.dart';
import 'checkpoint_event.dart';

/// Checkpoint / respawn system.
///
/// Scans entities that have a [CheckpointComponent] and, every frame, checks
/// whether any player entity (identified by [playerTag]) is within the
/// checkpoint's [CheckpointComponent.radius].  When a player enters an
/// unactivated checkpoint for the first time, the checkpoint is marked as
/// activated and a [CheckpointActivatedEvent] is fired.
///
/// The system also exposes [respawn] and [setRespawnPoint] helpers that game
/// code can call directly.
///
/// **Setup**:
/// ```dart
/// world.addSystem(CheckpointSystem(playerTag: 'player'));
/// ```
///
/// **Respawn on death**:
/// ```dart
/// world.events.on<PlayerRespawnEvent>((e) {
///   final transform = e.playerEntity.getComponent<TransformComponent>()!;
///   final velocity  = e.playerEntity.getComponent<VelocityComponent>()!;
///   transform.position.setFrom(e.respawnPosition);
///   velocity.setVelocityXY(0, 0);
/// });
/// ```
class CheckpointSystem extends System {
  /// Tag string used to identify player entities.
  final String playerTag;

  @override
  int get priority => SystemPriorities.checkpoint;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    CheckpointComponent,
  ];

  /// Last activated respawn position (world-space).  Defaults to zero
  /// until the player touches a checkpoint.
  Vector3 _currentRespawnPoint = Vector3.zero();
  Vector3 get currentRespawnPoint => _currentRespawnPoint;

  /// Creates a [CheckpointSystem] that looks for player entities tagged with
  /// [playerTag].
  CheckpointSystem({this.playerTag = 'player'});

  @override
  void update(double deltaTime) {
    // Collect player entities once per frame.
    final players = world.entities
        .where((e) {
          final tag = e.getComponent<TagComponent>();
          return tag != null && tag.tag == playerTag;
        })
        .toList(growable: false);

    if (players.isEmpty) return;

    forEach((checkpointEntity) {
      final cp = checkpointEntity.getComponent<CheckpointComponent>()!;
      if (cp.isActivated) return;

      final cpTransform = checkpointEntity.getComponent<TransformComponent>()!;
      final cpPos = cpTransform.position;

      for (final player in players) {
        final playerTransform = player.getComponent<TransformComponent>()!;
        final dx = playerTransform.position.x - cpPos.x;
        final dy = playerTransform.position.y - cpPos.y;
        final distSq = dx * dx + dy * dy;

        if (distSq <= cp.radius * cp.radius) {
          cp.isActivated = true;
          _currentRespawnPoint = Vector3.copy(cp.respawnPosition);

          world.events.fire(
            CheckpointActivatedEvent(
              checkpointEntity: checkpointEntity,
              playerEntity: player,
              respawnPosition: cp.respawnPosition,
            ),
          );
          break; // one activation per checkpoint per frame is enough
        }
      }
    });
  }

  /// Immediately teleport [playerEntity] to [_currentRespawnPoint] and fires
  /// a [PlayerRespawnEvent].  Call this when the player dies.
  void respawn(Entity playerEntity) {
    world.events.fire(
      PlayerRespawnEvent(
        playerEntity: playerEntity,
        respawnPosition: _currentRespawnPoint,
      ),
    );
  }

  /// Manually set the active respawn point without requiring the player to
  /// touch a checkpoint entity.  Useful for level-start defaults.
  void setRespawnPoint(Vector3 position) {
    _currentRespawnPoint = Vector3.copy(position);
  }

  // ── Debug rendering ──────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final cp = entity.getComponent<CheckpointComponent>()!;

      canvas.drawCircle(
        transform.position.toOffset(),
        cp.radius,
        cp.isActivated ? _activatedPaint : _inactivePaint,
      );
    });
  }

  static final Paint _inactivePaint = Paint()
    ..color = const Color(0x4400FFAA)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _activatedPaint = Paint()
    ..color = const Color(0x8800FFAA)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
}
