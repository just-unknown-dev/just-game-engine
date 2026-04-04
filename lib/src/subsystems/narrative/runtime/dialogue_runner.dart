/// Dialogue runner — the execution engine for a [DialogueGraph].
library;

import 'dart:async';

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
/// 2. Listen to [signals.currentLine] and [signals.choices].
/// 3. Call [advance] after the player reads a line.
/// 4. Call [selectChoice] when the player picks an option.
/// 5. The runner fires [signals.isDialogueActive] = `false` when finished.
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

  final DialogueGraph graph;
  final DialogueVariableStore variables;
  final DialogueConditionRegistry conditions;
  final DialogueCommandRegistry commands;

  /// Optional localizer — when provided, `#line:key` tags are resolved to
  /// translated strings before display.
  final DialogueLocalizer? localizer;

  // ---- Reactive state ------------------------------------------------------

  /// All observable state for the current session.
  final NarrativeSignals signals;

  // ---- Internal ------------------------------------------------------------

  late final ExpressionEvaluator _evaluator;

  /// Execution stack — enables nested choice bodies without recursion.
  final _stack = <_Frame>[];

  Completer<void>? _advanceCompleter;
  Completer<int>? _choiceCompleter;

  bool _loopRunning = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Whether a dialogue session is currently active.
  bool get isRunning => signals.isDialogueActive.value;

  /// Starts (or restarts) dialogue from [nodeTitle].
  ///
  /// Returns a [Future] that completes when the dialogue ends naturally
  /// (or [stop] is called).
  Future<void> start(String nodeTitle) async {
    final node = graph.getNode(nodeTitle);
    if (node == null) {
      throw ArgumentError(
        'Dialogue node "$nodeTitle" not found in graph "${graph.id}".',
      );
    }

    // Cancel any previous session
    if (_loopRunning) await _terminate();

    signals.isDialogueActive.value = true;
    signals.activeNodeTitle.value = nodeTitle;
    _stack.clear();
    _stack.add(_Frame(node.statements, 0));

    _loopRunning = true;
    await _runLoop();
    _loopRunning = false;
  }

  /// Advances past the current line.
  ///
  /// Call this when the player finishes reading.  Has no effect while waiting
  /// for a choice.
  void advance() {
    if (_advanceCompleter != null && !_advanceCompleter!.isCompleted) {
      _advanceCompleter!.complete();
    }
  }

  /// Selects a player choice by zero-based [index].
  ///
  /// Only has effect when [signals.hasChoices] is `true`.
  void selectChoice(int index) {
    if (_choiceCompleter != null && !_choiceCompleter!.isCompleted) {
      _choiceCompleter!.complete(index);
    }
  }

  /// Stops the current dialogue immediately.
  Future<void> stop() async {
    if (_loopRunning) await _terminate();
  }

  // ---------------------------------------------------------------------------
  // Execution loop
  // ---------------------------------------------------------------------------

  Future<void> _runLoop() async {
    while (_stack.isNotEmpty) {
      final frame = _stack.last;

      if (frame.index >= frame.statements.length) {
        _stack.removeLast();
        continue;
      }

      final stmt = frame.statements[frame.index];
      frame.index++;

      final shouldStop = await _executeStatement(stmt);
      if (shouldStop) break;
    }

    await _terminate();
  }

  /// Returns `true` when the loop should stop (e.g. [StopStatement]).
  Future<bool> _executeStatement(DialogueStatement stmt) async {
    switch (stmt) {
      case LineStatement():
        await _executeLine(stmt);
        return false;

      case ChoiceSetStatement():
        await _executeChoiceSet(stmt);
        return false;

      case JumpStatement():
        _executeJump(stmt);
        return false;

      case StopStatement():
        _stack.clear();
        return true;

      case SetStatement():
        _executeSet(stmt);
        return false;

      case ConditionalStatement():
        _executeConditional(stmt);
        return false;

      case CommandStatement():
        await _executeCommand(stmt);
        return false;
    }
    return false;
  }

  // ---- Statement handlers --------------------------------------------------

  Future<void> _executeLine(LineStatement stmt) async {
    final text = _resolveText(stmt.rawText, stmt.lineKey);
    signals.currentLine.value = DialogueLine(
      character: stmt.character,
      text: text,
      audioKey: stmt.audioKey,
      tags: stmt.tags,
      lineKey: stmt.lineKey,
    );
    signals.activeSpeaker.value = stmt.character;

    // Wait for advance()
    _advanceCompleter = Completer<void>();
    await _advanceCompleter!.future;
    _advanceCompleter = null;
  }

  Future<void> _executeChoiceSet(ChoiceSetStatement stmt) async {
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

    signals.choices.value = resolved;
    signals.currentLine.value = null;

    // Wait for selectChoice()
    _choiceCompleter = Completer<int>();
    final selected = await _choiceCompleter!.future;
    _choiceCompleter = null;

    signals.choices.value = const [];

    // Only process valid, available choices
    if (selected >= 0 &&
        selected < stmt.choices.length &&
        resolved[selected].isAvailable) {
      final body = stmt.choices[selected].body;
      if (body.isNotEmpty) {
        _stack.add(_Frame(body, 0));
      }
    }
  }

  void _executeJump(JumpStatement stmt) {
    final node = graph.getNode(stmt.target);
    if (node == null) return; // silently skip unknown targets
    _stack.clear();
    signals.activeNodeTitle.value = stmt.target;
    _stack.add(_Frame(node.statements, 0));
  }

  void _executeSet(SetStatement stmt) {
    variables.set(stmt.variable, _resolveExpressionValue(stmt.expression));
  }

  void _executeConditional(ConditionalStatement stmt) {
    for (final branch in stmt.branches) {
      if (branch.condition == null ||
          _evaluator.evaluateBool(branch.condition!)) {
        if (branch.body.isNotEmpty) {
          _stack.add(_Frame(branch.body, 0));
        }
        return;
      }
    }
  }

  Future<void> _executeCommand(CommandStatement stmt) async {
    await commands.execute(stmt.name, stmt.rawArgs);
  }

  // ---- Helpers -------------------------------------------------------------

  /// Resolves localization and `{$varName}` substitutions in [rawText].
  String _resolveText(String rawText, String? lineKey) {
    var text = rawText;

    // Localization: line key takes precedence over raw text
    if (lineKey != null && localizer != null) {
      text = localizer!.localize(lineKey, fallback: rawText);
    }

    // Inline variable substitution: {$varName}
    text = text.replaceAllMapped(
      RegExp(r'\{\$([a-zA-Z0-9_]+)\}'),
      (m) => variables.getRaw(m.group(1) ?? '')?.toString() ?? '',
    );

    return text;
  }

  /// Evaluates the RHS of a `<<set>>` expression.
  dynamic _resolveExpressionValue(String expr) {
    final trimmed = expr.trim();
    final lower = trimmed.toLowerCase();

    if (lower == 'true') return true;
    if (lower == 'false') return false;

    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) return asDouble;

    // String literals
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.substring(1, trimmed.length - 1);
    }

    // Variable reference
    if (trimmed.startsWith(r'$')) {
      return variables.getRaw(trimmed.substring(1));
    }

    return _evaluator.evaluate(expr);
  }

  Future<void> _terminate() async {
    // Unblock any pending awaits
    if (_advanceCompleter != null && !_advanceCompleter!.isCompleted) {
      _advanceCompleter!.complete();
    }
    if (_choiceCompleter != null && !_choiceCompleter!.isCompleted) {
      _choiceCompleter!.complete(-1);
    }
    _stack.clear();
    signals.currentLine.value = null;
    signals.choices.value = const [];
    signals.activeSpeaker.value = null;
    signals.activeNodeTitle.value = null;
    signals.isDialogueActive.value = false;
  }
}

// ---------------------------------------------------------------------------
// Internal frame
// ---------------------------------------------------------------------------

/// A single execution frame on the runner's statement stack.
class _Frame {
  _Frame(this.statements, this.index);
  final List<DialogueStatement> statements;
  int index;
}
