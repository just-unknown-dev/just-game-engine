/// ECS components for the Narrative/Dialogue System.
library;

import '../../../ecs/ecs.dart';

// ---------------------------------------------------------------------------
// DialogueComponent
// ---------------------------------------------------------------------------

/// Marks an entity (typically an NPC) as having associated dialogue.
///
/// Attach this component to indicate which [DialogueGraph] the entity uses
/// and how it should behave (interaction radius, auto-advance, etc.).
///
/// **Setup**
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(x: 200, y: 300),
///   SpriteComponent(texturePath: 'npc_innkeeper.png'),
///   DialogueComponent(
///     graphId: 'innkeeper',
///     characterName: 'Innkeeper',
///     interactionRadius: 80,
///   ),
/// ]);
/// ```
///
/// **Triggering dialogue from game code**
/// ```dart
/// // On interaction key press / tap:
/// if (npcEntity.get<DialogueComponent>()!.isInteractable) {
///   final runner = narrative.createRunnerForEntity(npcEntity.id, 'innkeeper');
///   await runner.start('Innkeeper_Hub');
/// }
/// ```
class DialogueComponent extends Component {
  DialogueComponent({
    required this.graphId,
    this.startNode = 'Start',
    this.characterName = '',
    this.interactionRadius = 64.0,
    this.autoAdvance = false,
    this.autoAdvanceDelay = 2.0,
  });

  // ---- Configuration -------------------------------------------------------

  /// ID of the [DialogueGraph] registered in [DialogueManager].
  final String graphId;

  /// The node title to start from.  Defaults to `'Start'`.
  final String startNode;

  /// This entity's character name as it appears in Yarn dialogue lines.
  final String characterName;

  /// World-space radius within which a player entity makes this NPC
  /// interactable.
  ///
  /// Set to `0` to disable proximity-based [isInteractable] tracking and
  /// manage it entirely from game code.
  final double interactionRadius;

  /// Whether the runner should automatically advance past lines after a delay.
  ///
  /// Useful for cutscene-style monologues that require no player input.
  final bool autoAdvance;

  /// Seconds to wait before auto-advancing to the next line.
  final double autoAdvanceDelay;

  // ---- Runtime state (managed by DialogueSystem) ---------------------------

  /// Set to `true` by [DialogueSystem] when a player entity is within
  /// [interactionRadius].
  bool isInteractable = false;

  /// `true` while a runner is executing dialogue for this entity.
  bool isInDialogue = false;

  /// Accumulated timer for auto-advance; reset after each advance.
  double autoAdvanceTimer = 0.0;
}

// ---------------------------------------------------------------------------
// DialogueTriggerComponent
// ---------------------------------------------------------------------------

/// Trigger zone that automatically starts dialogue when a player enters.
///
/// Attach this to an invisible trigger entity (no renderable needed).
/// [DialogueSystem] fires it once the player steps inside [triggerRadius].
///
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(x: 400, y: 200),
///   DialogueTriggerComponent(
///     graphId: 'cutscene_intro',
///     startNode: 'Start',
///     triggerRadius: 96,
///     triggerOnce: true,
///   ),
/// ]);
/// ```
class DialogueTriggerComponent extends Component {
  DialogueTriggerComponent({
    required this.graphId,
    this.startNode = 'Start',
    this.triggerRadius = 64.0,
    this.triggerOnce = true,
    this.autoAdvance = false,
    this.autoAdvanceDelay = 2.0,
  });

  final String graphId;
  final String startNode;

  /// World-space proximity radius that fires the trigger.
  final double triggerRadius;

  /// If `true` the trigger fires at most once per session and then becomes
  /// dormant.  Set to `false` for repeating triggers (e.g. shop re-entry).
  final bool triggerOnce;

  final bool autoAdvance;
  final double autoAdvanceDelay;

  // ---- Runtime state -------------------------------------------------------

  /// `true` after the trigger has fired (and [triggerOnce] is `true`).
  bool hasTriggered = false;
}
