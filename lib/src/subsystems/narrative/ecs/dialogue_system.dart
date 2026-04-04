/// ECS system that manages the lifecycle of dialogue components.
library;

import 'dart:math' as math;

import '../../../ecs/ecs.dart';
import '../../../ecs/components/core/transform_component.dart';
import '../../../ecs/components/others/tag_component.dart';
import '../../../ecs/systems/system_priorities.dart';
import '../dialogue_manager.dart';
import 'dialogue_component.dart';

// ---------------------------------------------------------------------------
// DialogueSystem
// ---------------------------------------------------------------------------

/// ECS system that drives [DialogueComponent] and [DialogueTriggerComponent]
/// entities.
///
/// **Responsibilities**
/// * Tracks player proximity and sets [DialogueComponent.isInteractable].
/// * Auto-advances [DialogueRunner] lines when [DialogueComponent.autoAdvance]
///   is `true`.
/// * Fires [DialogueTriggerComponent] zones when a player entity enters range.
///
/// **Setup**
/// ```dart
/// world.addSystem(DialogueSystem(manager: narrative, playerTag: 'player'));
/// ```
///
/// The system finds a "player" entity by querying for [TagComponent] with
/// [playerTag] (`'player'` by default).  If none is found, proximity features
/// are skipped (dialogue can still be triggered from game code).
class DialogueSystem extends System {
  DialogueSystem({required this.manager, this.playerTag = 'player'});

  /// The [DialogueManager] that owns all runners.
  final DialogueManager manager;

  /// Tag value used to locate the player entity for proximity checks.
  final String playerTag;

  @override
  List<Type> get requiredComponents => [DialogueComponent];

  @override
  int get priority => SystemPriorities.dialogue;

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  @override
  void update(double deltaTime) {
    // Find player world position (optional)
    final (double? px, double? py) = _playerPosition();

    // ---- DialogueComponent entities ----------------------------------------
    for (final entity in entities) {
      final dc = entity.getComponent<DialogueComponent>()!;

      // Proximity → isInteractable
      if (px != null && py != null && dc.interactionRadius > 0) {
        final tf = entity.getComponent<TransformComponent>();
        if (tf != null) {
          final dx = tf.position.dx - px;
          final dy = tf.position.dy - py;
          dc.isInteractable =
              math.sqrt(dx * dx + dy * dy) <= dc.interactionRadius;
        }
      }

      // Auto-advance timer
      if (dc.isInDialogue && dc.autoAdvance) {
        final runner = manager.getRunnerForEntity(entity.id);
        if (runner != null &&
            runner.signals.currentLine.value != null &&
            !runner.signals.hasChoices.value) {
          dc.autoAdvanceTimer += deltaTime;
          if (dc.autoAdvanceTimer >= dc.autoAdvanceDelay) {
            dc.autoAdvanceTimer = 0.0;
            runner.advance();
          }
        }
      }
    }

    // ---- DialogueTriggerComponent entities ---------------------------------
    if (px == null || py == null) return;

    final triggerEntities = world.query([DialogueTriggerComponent]);
    for (final entity in triggerEntities) {
      final tc = entity.getComponent<DialogueTriggerComponent>()!;
      if (tc.hasTriggered) continue;

      final tf = entity.getComponent<TransformComponent>();
      if (tf == null) continue;

      final dx = tf.position.dx - px;
      final dy = tf.position.dy - py;
      if (math.sqrt(dx * dx + dy * dy) <= tc.triggerRadius) {
        if (tc.triggerOnce) tc.hasTriggered = true;

        // Fire-and-forget the dialogue session
        manager.startDialogue(graphId: tc.graphId, startNode: tc.startNode);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  /// Returns the world-space position of the first entity tagged [playerTag],
  /// or `(null, null)` if none is found.
  (double?, double?) _playerPosition() {
    final candidates = world
        .query([TagComponent])
        .where((e) => e.getComponent<TagComponent>()?.tag == playerTag);

    if (candidates.isEmpty) return (null, null);

    final tf = candidates.first.getComponent<TransformComponent>();
    return tf != null ? (tf.position.dx, tf.position.dy) : (null, null);
  }
}
