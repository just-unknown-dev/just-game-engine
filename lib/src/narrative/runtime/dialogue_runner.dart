/// Dialogue runner — the execution engine for a [DialogueGraph].
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../core/dialogue_choice.dart';
import '../core/dialogue_graph.dart';
import '../core/dialogue_line.dart';
import '../core/dialogue_statement.dart';
import '../core/dialogue_variable_store.dart';
import '../localization/dialogue_localizer.dart';
import '../signals/narrative_signals.dart';
import 'dialogue_command_registry.dart';
import 'dialogue_condition_registry.dart';
import 'expression_evaluator.dart';

// ---------------------------------------------------------------------------
// DialogueRunner
// ---------------------------------------------------------------------------

/// Executes a [DialogueGraph] step-by-step and exposes the current state
/// through reactive [signals].
///
/// **Lifecycle**
/// 1. Call [start] with a node title — the runner begins executing.
/// 2. Listen to `signals.currentLine` and `signals.choices`.
/// 3. Call [advance] after the player reads a line.
/// 4. Call [selectChoice] when the player picks an option.
/// 5. The runner fires `signals.isDialogueActive` = `false` when finished.
///
/// ```dart
/// final runner = DialogueRunner(
///   graph: graph,
///   variables: variableStore,
///   conditions: conditionRegistry,
///   commands: commandRegistry,
/// );
///
/// runner.signals.currentLine.addListener(() {
///   final line = runner.signals.currentLine.value;
///   if (line != null) displayDialogueLine(line);
/// });
///
/// runner.signals.choices.addListener(() {
///   final opts = runner.signals.choices.value;
///   if (opts.isNotEmpty) showChoiceMenu(opts);
/// });
///
/// await runner.start('Start');
/// ```
class DialogueRunner {
  /// An idle runner for [graph]; nothing runs until [start]. It reports
  /// through [signals] — a fresh [NarrativeSignals] when null — and shows
  /// text untranslated when [localizer] is null.
  /// `DialogueManager.createRunner` wires these from the manager.
  DialogueRunner({
    required this.graph,
    required this.variables,
    required this.conditions,
    required this.commands,
    this.localizer,
    NarrativeSignals? signals,
  }) : signals = signals ?? NarrativeSignals() {
    _evaluator = ExpressionEvaluator(
      variables: variables,
      conditions: conditions,
    );
  }

  // ---- Configuration -------------------------------------------------------

  /// The dialogue this runner plays; [start] names one of its nodes.
  final DialogueGraph graph;

  /// Where `$name` variables are read from, and where `<<set>>` writes.
  final DialogueVariableStore variables;

  /// The `[name]` predicates that conditions may call.
  final DialogueConditionRegistry conditions;

  /// The handlers run for custom `<<name args>>` commands; one not
  /// registered here is skipped.
  final DialogueCommandRegistry commands;

  /// Optional localizer — when provided, `#line:key` tags are resolved to
  /// translated strings before display.
  final DialogueLocalizer? localizer;

  // ---- Reactive state ------------------------------------------------------

  /// All observable state for the current session.
  final NarrativeSignals signals;

  // ---- Internal ------------------------------------------------------------

  late final ExpressionEvaluator _evaluator;

  /// The session playing now; null while idle. A [start] replaces it, and
  /// the one replaced — still awaiting a line, a choice or a command —
  /// finds itself over the moment it wakes and goes no further.
  _Session? _session;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Whether a dialogue session is currently active.
  bool get isRunning => signals.isDialogueActive.value;

  /// Starts (or restarts) dialogue from [nodeTitle].
  ///
  /// Returns a [Future] that completes when the dialogue ends naturally,
  /// when [stop] is called, or when another [start] takes over. A command
  /// handler that throws ends the session, and the future completes with
  /// its error.
  ///
  /// Throws an [ArgumentError] when the graph has no node [nodeTitle];
  /// whatever was playing goes on then.
  Future<void> start(String nodeTitle) async {
    final node = graph.getNode(nodeTitle);
    if (node == null) {
      throw ArgumentError(
        'Dialogue node "$nodeTitle" not found in graph "${graph.id}".',
      );
    }

    // Cancel any previous session
    final previous = _session;
    if (previous != null) _finish(previous);

    final session = _session = _Session()
      ..stack.add(_Frame(node.statements, 0));
    signals.isDialogueActive.value = true;
    signals.activeNodeTitle.value = nodeTitle;

    try {
      await _runLoop(session);
    } finally {
      _finish(session);
    }
  }

  /// Advances past the current line.
  ///
  /// Call this when the player finishes reading.  Has no effect while waiting
  /// for a choice. It may be called from a `signals.currentLine` listener.
  void advance() {
    final waiting = _session?.advance;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  /// Selects a player choice by zero-based [index].
  ///
  /// Only has effect when `signals.hasChoices` is `true`, and only for an
  /// index in range whose choice is available: anything else is ignored
  /// (and said in the log in a debug build), and the choices stay up.
  void selectChoice(int index) {
    final session = _session;
    final waiting = session?.choice;
    if (session == null || waiting == null || waiting.isCompleted) return;
    final offered = session.offered;
    if (index < 0 || index >= offered.length || !offered[index].isAvailable) {
      if (kDebugMode) {
        debugPrint(
          'DialogueRunner: choice $index cannot be picked '
          '(${offered.length} offered); ignored.',
        );
      }
      return;
    }
    waiting.complete(index);
  }

  /// Stops the current dialogue immediately.
  Future<void> stop() async {
    final session = _session;
    if (session != null) _finish(session);
  }

  // ---------------------------------------------------------------------------
  // Execution loop
  // ---------------------------------------------------------------------------

  Future<void> _runLoop(_Session session) async {
    final stack = session.stack;
    // Each await may wake to a session that was stopped or replaced
    // meanwhile; it then goes no further.
    while (!session.over && stack.isNotEmpty) {
      final frame = stack.last;

      if (frame.index >= frame.statements.length) {
        stack.removeLast();
        continue;
      }

      final stmt = frame.statements[frame.index];
      frame.index++;

      final shouldStop = await _executeStatement(session, stmt);
      if (shouldStop) break;
    }
  }

  /// Returns `true` when the loop should stop (e.g. [StopStatement]).
  Future<bool> _executeStatement(
    _Session session,
    DialogueStatement stmt,
  ) async {
    switch (stmt) {
      case LineStatement():
        await _executeLine(session, stmt);
        return false;

      case ChoiceSetStatement():
        await _executeChoiceSet(session, stmt);
        return false;

      case JumpStatement():
        _executeJump(session, stmt);
        return false;

      case StopStatement():
        session.stack.clear();
        return true;

      case SetStatement():
        _executeSet(stmt);
        return false;

      case ConditionalStatement():
        _executeConditional(session, stmt);
        return false;

      case CommandStatement():
        await _executeCommand(stmt);
        return false;
    }
    return false;
  }

  // ---- Statement handlers --------------------------------------------------

  Future<void> _executeLine(_Session session, LineStatement stmt) async {
    final text = _resolveText(stmt.rawText, stmt.lineKey);
    final character = stmt.character == null
        ? null
        : _substitute(stmt.character!);
    // Waiting before the line is shown: a listener may advance at once.
    final waiting = session.advance = Completer<void>();
    signals.currentLine.value = DialogueLine(
      character: character,
      text: text,
      audioKey: stmt.audioKey,
      tags: stmt.tags,
      lineKey: stmt.lineKey,
    );
    if (session.over) return;
    signals.activeSpeaker.value = character;

    // Wait for advance()
    await waiting.future;
    if (identical(session.advance, waiting)) session.advance = null;
  }

  Future<void> _executeChoiceSet(
    _Session session,
    ChoiceSetStatement stmt,
  ) async {
    final resolved = <DialogueChoice>[];
    for (int i = 0; i < stmt.choices.length; i++) {
      final opt = stmt.choices[i];
      final available =
          opt.condition == null || _evaluator.evaluateBool(opt.condition!);
      resolved.add(
        DialogueChoice(
          index: i,
          text: _resolveText(opt.rawText, opt.lineKey),
          audioKey: opt.audioKey,
          tags: opt.tags,
          isAvailable: available,
        ),
      );
    }

    // Waiting before the choices are shown: a listener may pick at once.
    session.offered = resolved;
    final waiting = session.choice = Completer<int>();
    signals.choices.value = resolved;
    if (session.over) return;
    signals.currentLine.value = null;

    // Wait for selectChoice()
    final selected = await waiting.future;
    if (identical(session.choice, waiting)) session.choice = null;
    session.offered = const [];
    if (session.over) return;

    signals.choices.value = const [];

    // selectChoice only lets through valid, available choices.
    final body = stmt.choices[selected].body;
    if (body.isNotEmpty) {
      session.stack.add(_Frame(body, 0));
    }
  }

  void _executeJump(_Session session, JumpStatement stmt) {
    final node = graph.getNode(stmt.target);
    if (node == null) return; // silently skip unknown targets
    session.stack
      ..clear()
      ..add(_Frame(node.statements, 0));
    signals.activeNodeTitle.value = stmt.target;
  }

  void _executeSet(SetStatement stmt) {
    // A declaration only gives a first value.
    if (stmt.isDeclaration && variables.has(stmt.variable)) return;
    final value = _resolveExpressionValue(stmt.expression);
    if (value == null) {
      if (kDebugMode) {
        debugPrint(
          'Dialogue: \$${stmt.variable} was left as it was — '
          '"${stmt.expression}" has no value.',
        );
      }
      return;
    }
    variables.set(stmt.variable, value);
  }

  void _executeConditional(_Session session, ConditionalStatement stmt) {
    for (final branch in stmt.branches) {
      if (branch.condition == null ||
          _evaluator.evaluateBool(branch.condition!)) {
        if (branch.body.isNotEmpty) {
          session.stack.add(_Frame(branch.body, 0));
        }
        return;
      }
    }
  }

  Future<void> _executeCommand(CommandStatement stmt) async {
    await commands.execute(stmt.name, _substitute(stmt.rawArgs));
  }

  // ---- Helpers -------------------------------------------------------------

  /// Resolves localization and `{$varName}` substitutions in [rawText].
  String _resolveText(String rawText, String? lineKey) {
    var text = rawText;

    // Localization: line key takes precedence over raw text
    if (lineKey != null && localizer != null) {
      text = localizer!.localize(lineKey, fallback: rawText);
    }

    return _substitute(text);
  }

  /// [text] with each `{$varName}` replaced by the variable's value (empty
  /// when it has none).
  String _substitute(String text) {
    if (!text.contains(r'{$')) return text;
    return text.replaceAllMapped(
      RegExp(r'\{\$([a-zA-Z0-9_]+)\}'),
      (m) => variables.getRaw(m.group(1) ?? '')?.toString() ?? '',
    );
  }

  /// Evaluates the RHS of a `<<set>>` expression; null when it has no value.
  dynamic _resolveExpressionValue(String expr) {
    final trimmed = expr.trim();
    final lower = trimmed.toLowerCase();

    if (lower == 'true') return true;
    if (lower == 'false') return false;

    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) return asDouble;

    // A string literal and nothing else — `"a" == "b"` is a comparison.
    final literal = _stringLiteral.firstMatch(trimmed);
    if (literal != null) return literal.group(1) ?? literal.group(2);

    // A variable and nothing else — `$gold >= 100` is an expression.
    final variable = _variableOnly.firstMatch(trimmed);
    if (variable != null) return variables.getRaw(variable.group(1)!);

    return _evaluator.evaluate(trimmed);
  }

  /// Ends [session]: whatever it awaits is let go, and — while it is the
  /// one playing — the runner goes idle and its signals are cleared.
  void _finish(_Session session) {
    if (session.over) return;
    session.over = true;
    final advance = session.advance;
    if (advance != null && !advance.isCompleted) advance.complete();
    final choice = session.choice;
    if (choice != null && !choice.isCompleted) choice.complete(-1);
    session.stack.clear();
    if (!identical(_session, session)) return;
    _session = null;
    signals.currentLine.value = null;
    signals.choices.value = const [];
    signals.activeSpeaker.value = null;
    signals.activeNodeTitle.value = null;
    signals.isDialogueActive.value = false;
  }
}

// ---------------------------------------------------------------------------
// Internal session and frame
// ---------------------------------------------------------------------------

/// One run of the runner, from [DialogueRunner.start] to its end.
class _Session {
  /// Execution stack — enables nested choice bodies without recursion.
  final stack = <_Frame>[];

  /// What a line waits on, until [DialogueRunner.advance].
  Completer<void>? advance;

  /// What a choice set waits on, until [DialogueRunner.selectChoice].
  Completer<int>? choice;

  /// The choices on offer while [choice] waits.
  List<DialogueChoice> offered = const [];

  /// Stopped, replaced or finished: it does nothing more.
  bool over = false;
}

/// A single execution frame on the runner's statement stack.
class _Frame {
  _Frame(this.statements, this.index);
  final List<DialogueStatement> statements;
  int index;
}

final RegExp _stringLiteral = RegExp(r'''^(?:"([^"]*)"|'([^']*)')$''');

final RegExp _variableOnly = RegExp(r'^\$(\w+)$');
