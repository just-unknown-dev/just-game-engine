/// Reactive observable state for the narrative system.
library;

import 'package:just_signals/just_signals.dart';

import '../core/dialogue_choice.dart';
import '../core/dialogue_line.dart';

// ---------------------------------------------------------------------------
// NarrativeSignals
// ---------------------------------------------------------------------------

/// All reactive state exposed by a running [DialogueRunner].
///
/// Subscribe to whichever signals you need to drive your UI or game logic.
///
/// ```dart
/// // Listen for new lines
/// runner.signals.currentLine.addListener(() {
///   final line = runner.signals.currentLine.value;
///   if (line != null) displayLine(line);
/// });
///
/// // Listen for choices
/// runner.signals.choices.addListener(() {
///   final opts = runner.signals.choices.value;
///   if (opts.isNotEmpty) openChoiceMenu(opts);
/// });
///
/// // React to dialogue ending
/// runner.signals.isDialogueActive.addListener(() {
///   if (!runner.signals.isDialogueActive.value) closeDialogueUI();
/// });
/// ```
///
/// Or use reactive builders directly in Flutter widgets:
/// ```dart
/// SignalBuilder<DialogueLine?>(
///   signal: runner.signals.currentLine,
///   builder: (ctx, line, _) => line == null
///       ? const SizedBox.shrink()
///       : Text(line.text),
/// )
/// ```
class NarrativeSignals {
  NarrativeSignals() {
    hasChoices = Computed<bool>(() => choices.value.isNotEmpty);
    hasLine = Computed<bool>(() => currentLine.value != null);
  }

  // ---- Writable signals (managed by DialogueRunner) -----------------------

  /// The dialogue line currently being presented, or `null` when no line is
  /// active (e.g. when waiting for a choice or between sessions).
  final currentLine = Signal<DialogueLine?>(null);

  /// The choices offered to the player; empty when no choice is pending.
  final choices = Signal<List<DialogueChoice>>(const []);

  /// Whether a dialogue session is currently running.
  final isDialogueActive = Signal<bool>(false);

  /// The [DialogueLine.character] of the currently speaking entity, or `null`.
  final activeSpeaker = Signal<String?>(null);

  /// The title of the [DialogueNode] currently being executed.
  final activeNodeTitle = Signal<String?>(null);

  // ---- Derived (computed) signals -----------------------------------------

  /// `true` while the runner is waiting for a player choice.
  late final Computed<bool> hasChoices;

  /// `true` when a [currentLine] is ready to display.
  late final Computed<bool> hasLine;

  // ---- Lifecycle ----------------------------------------------------------

  void dispose() {
    currentLine.dispose();
    choices.dispose();
    isDialogueActive.dispose();
    activeSpeaker.dispose();
    activeNodeTitle.dispose();
    hasChoices.dispose();
    hasLine.dispose();
  }
}

// ---------------------------------------------------------------------------
// DialogueEvent  (optional event-bus style integration)
// ---------------------------------------------------------------------------

/// Structured event emitted by [DialogueManager] to an optional event bus.
class DialogueEvent {
  const DialogueEvent({
    required this.type,
    this.graphId,
    this.nodeTitle,
    this.line,
    this.choices,
    this.choiceIndex,
    this.commandName,
    this.commandArgs,
  });

  final DialogueEventType type;

  /// ID of the [DialogueGraph] involved.
  final String? graphId;

  /// Node title where the event occurred.
  final String? nodeTitle;

  /// Resolved line, when [type] is [DialogueEventType.linePresented].
  final DialogueLine? line;

  /// Resolved choices, when [type] is [DialogueEventType.choicesPresented].
  final List<DialogueChoice>? choices;

  /// Index of the selected choice, when [type] is
  /// [DialogueEventType.choiceSelected].
  final int? choiceIndex;

  /// Command name, when [type] is [DialogueEventType.commandExecuted].
  final String? commandName;

  /// Command arguments, when [type] is [DialogueEventType.commandExecuted].
  final List<String>? commandArgs;
}

/// Types of events produced by the dialogue system.
enum DialogueEventType {
  /// A new dialogue session started.
  dialogueStarted,

  /// The dialogue session ended (either naturally or via [DialogueRunner.stop]).
  dialogueEnded,

  /// A line has been presented to [NarrativeSignals.currentLine].
  linePresented,

  /// Choices have been presented to [NarrativeSignals.choices].
  choicesPresented,

  /// The player selected a choice.
  choiceSelected,

  /// The active node changed (jump or start).
  nodeChanged,

  /// A custom `<<command>>` was executed.
  commandExecuted,
}
