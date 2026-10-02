/// ECS system that manages the lifecycle of dialogue components.
library;

import 'dart:math' as math;

import '../../ecs.dart';
import '../../base/transform/transform_component.dart';
import '../../serialization/tag_library.dart' show EngineTags;
import '../../base/system_priorities.dart';
import '../../../subsystems/narrative/dialogue_manager.dart';
import '../../../subsystems/narrative/runtime/dialogue_runner.dart';
import '../../components/narrative/dialogue_component.dart';

// ---------------------------------------------------------------------------
// DialogueSystem
// ---------------------------------------------------------------------------

/// ECS system that drives [DialogueComponent] and [DialogueTriggerComponent]
/// entities.
///
/// **Responsibilities**
/// * Tracks player proximity and sets [DialogueComponent.isInteractable].
/// * Keeps [DialogueComponent.isInDialogue] in step with the runner bound to
///   the entity (`DialogueManager.createRunnerForEntity`).
/// * Auto-advances [DialogueRunner] lines when [DialogueComponent.autoAdvance]
///   is `true` — and the dialogues a trigger with
///   [DialogueTriggerComponent.autoAdvance] started. A line is advanced
///   once it has been shown for the delay; a choice waits for the player.
/// * Fires [DialogueTriggerComponent] zones when a player entity enters range
///   — as it enters, not on every frame it stays.
///
/// **Setup**
/// ```dart
/// world.addSystem(DialogueSystem(manager: narrative, playerTag: 'player'));
/// ```
///
/// The system finds a "player" entity by its tag, [playerTag] (`'player'`
/// by default).  If none is found, proximity features
/// are skipped (dialogue can still be triggered from game code).
class DialogueSystem extends System {
  /// A system driving [manager]'s runners, finding the player by
  /// [playerTag] (`player` by default).
  DialogueSystem({required this.manager, this.playerTag = EngineTags.player});

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
    _forgetDestroyedEntities();

    // Find player world position (optional)
    final (double? px, double? py) = _playerPosition();

    // ---- DialogueComponent entities ----------------------------------------
    for (final entity in entities) {
      final dc = entity.getComponent<DialogueComponent>()!;

      // Proximity → isInteractable
      if (px != null && py != null && dc.interactionRadius > 0) {
        final tf = entity.getComponent<TransformComponent>();
        if (tf != null) {
          final dx = tf.position.x - px;
          final dy = tf.position.y - py;
          dc.isInteractable =
              math.sqrt(dx * dx + dy * dy) <= dc.interactionRadius;
        }
      }

      // In dialogue while the entity's runner runs.
      final runner = manager.getRunnerForEntity(entity.id);
      dc.isInDialogue = runner?.isRunning ?? false;

      // Auto-advance timer
      if (dc.isInDialogue && dc.autoAdvance) {
        dc.autoAdvanceTimer = _autoAdvance(
          runner!,
          delay: dc.autoAdvanceDelay,
          timer: dc.autoAdvanceTimer,
          deltaTime: deltaTime,
          lines: _timedLines,
          key: dc,
        );
      } else {
        dc.autoAdvanceTimer = 0.0;
      }
    }

    // ---- Dialogues started by auto-advancing triggers ----------------------
    _autoAdvancing.removeWhere((auto) => !auto.runner.isRunning);
    for (final auto in _autoAdvancing) {
      auto.timer = _autoAdvance(
        auto.runner,
        delay: auto.delay,
        timer: auto.timer,
        deltaTime: deltaTime,
        lines: _timedLines,
        key: auto,
      );
    }

    // ---- DialogueTriggerComponent entities ---------------------------------
    if (px == null || py == null) return;

    final triggerEntities = world.query([DialogueTriggerComponent]);
    for (final entity in triggerEntities) {
      final tc = entity.getComponent<DialogueTriggerComponent>()!;
      if (tc.hasTriggered) continue;

      final tf = entity.getComponent<TransformComponent>();
      if (tf == null) continue;

      final dx = tf.position.x - px;
      final dy = tf.position.y - py;
      final inside = math.sqrt(dx * dx + dy * dy) <= tc.triggerRadius;
      // Fires on the way in only. Firing whenever the player was inside
      // started a new dialogue every frame a repeating trigger was stood in.
      final entered = inside && !tc.isPlayerInside;
      tc.isPlayerInside = inside;
      if (!entered) continue;

      if (tc.triggerOnce) tc.hasTriggered = true;

      // Fire-and-forget the dialogue session
      final started = manager.startDialogue(
        graphId: tc.graphId,
        startNode: tc.startNode,
      );
      if (tc.autoAdvance) {
        final delay = tc.autoAdvanceDelay;
        started.then((runner) => _autoAdvancing.add(_AutoRun(runner, delay)));
      }
    }
  }

  /// Dialogues started by triggers that advance by themselves, until they
  /// end.
  final List<_AutoRun> _autoAdvancing = [];

  /// The line each auto-advance timer is timing, by its owner.
  final Expando<Object> _timedLines = Expando('auto-advance lines');

  /// One frame of auto-advance for [runner]: the new timer value. The timer
  /// counts how long the current line has been shown — from 0 again for a
  /// new line, however it came — and a line shown for [delay] is advanced.
  /// A choice, or no line at all, waits.
  static double _autoAdvance(
    DialogueRunner runner, {
    required double delay,
    required double timer,
    required double deltaTime,
    required Expando<Object> lines,
    required Object key,
  }) {
    final line = runner.signals.currentLine.value;
    if (line == null || runner.signals.hasChoices.value) {
      lines[key] = null;
      return 0.0;
    }
    if (!identical(lines[key], line)) {
      lines[key] = line;
      timer = 0.0;
    }
    timer += deltaTime;
    if (timer < delay) return timer;
    runner.advance();
    return 0.0;
  }

  /// Lets go of runners bound to entities that no longer exist, once the
  /// world's structure has changed — [DialogueManager] cannot tell a
  /// destroyed entity from a live one by its id alone.
  void _forgetDestroyedEntities() {
    final version = world.structureVersion;
    if (version == _seenStructureVersion) return;
    _seenStructureVersion = version;
    for (final id in manager.boundEntityIds.toList()) {
      if (world.getEntity(id) == null) manager.releaseRunnerForEntity(id);
    }
  }

  int _seenStructureVersion = -1;

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  /// Returns the world-space position of the first entity tagged [playerTag],
  /// or `(null, null)` if none is found.
  (double?, double?) _playerPosition() {
    final player = world.findTagged(playerTag);
    if (player == null) return (null, null);

    final tf = player.getComponent<TransformComponent>();
    return tf != null ? (tf.position.x, tf.position.y) : (null, null);
  }
}

/// A dialogue a trigger started that advances by itself.
class _AutoRun {
  _AutoRun(this.runner, this.delay);

  final DialogueRunner runner;
  final double delay;
  double timer = 0.0;
}
