/// In-game developer terminal for cheat commands and debug tooling.
///
/// Register commands with [registerCommand], then attach the terminal to a
/// [GameWidget] via the [GameWidget.showTerminal] flag.  The backquote key
/// toggles visibility at runtime.
///
/// Usage example (inside GameBootstrapper or similar):
/// ```dart
/// engine.terminal.registerCommand(
///   name: 'collision',
///   description: 'Toggle ring-wall collision. Usage: collision <on|off|toggle>',
///   handler: (args) {
///     // ... toggle logic
///   },
/// );
/// ```
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

// ── Public types ───────────────────────────────────────────────────────────

/// Signature for a registered terminal command handler.
///
/// [args] contains every token after the command name, split on whitespace.
/// Return a non-null string to write output to the terminal history; return
/// null to produce no output line.
typedef TerminalCommandHandler = String? Function(List<String> args);

// ── GameTerminal ──────────────────────────────────────────────────────────

/// Manages all in-game terminal state: visibility, text input, scrollback
/// history, and the command registry.
///
/// This is a plain Dart object — no Flutter widget dependencies — so it can
/// be unit-tested without a widget tree.
class GameTerminal extends ChangeNotifier {
  GameTerminal() {
    // Register built-in commands.
    registerCommand(
      name: 'help',
      description: 'List all registered commands.',
      handler: _handleHelp,
    );
    registerCommand(
      name: 'clear',
      description: 'Clear terminal output.',
      handler: (_) {
        _history.clear();
        notifyListeners();
        return null;
      },
    );
  }

  // ── State ────────────────────────────────────────────────────────────

  /// Whether the terminal overlay is currently visible.
  bool isVisible = false;

  /// The current text being typed into the prompt line.
  String inputBuffer = '';

  /// Maximum number of lines retained in scrollback history.
  static const int _maxHistoryLines = 100;

  /// Lines of output shown above the prompt.
  final List<String> _history = [];

  /// Returns an unmodifiable view of the current scrollback history.
  List<String> get history => List.unmodifiable(_history);

  // ── Command registry ─────────────────────────────────────────────────

  final Map<String, _CommandEntry> _commands = {};

  /// Register a named command.
  ///
  /// [name] must be a single word (no spaces).  Registering the same name
  /// twice overwrites the previous handler.
  void registerCommand({
    required String name,
    required String description,
    required TerminalCommandHandler handler,
  }) {
    assert(!name.contains(' '), 'Command name must not contain spaces.');
    _commands[name.toLowerCase()] = _CommandEntry(
      name: name.toLowerCase(),
      description: description,
      handler: handler,
    );
  }

  // ── Toggle ────────────────────────────────────────────────────────────

  /// Toggle visibility.  Called by GameWidget on backquote key-down.
  void toggle() {
    isVisible = !isVisible;
    if (!isVisible) {
      // Clear the input buffer when closing so no stale text reappears.
      inputBuffer = '';
    }
    notifyListeners();
  }

  // ── Key event handling ───────────────────────────────────────────────

  /// Feed a [LogicalKeyboardKey] key-down event to the terminal.
  ///
  /// Returns `true` if the key was consumed (caller should suppress it from
  /// reaching normal gameplay input).
  ///
  /// Prefer [appendCharacter] for printable input so that Shift/CapsLock and
  /// platform IMEs are handled correctly by Flutter's key system.
  bool handleKeyDown(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      notifyListeners();
      return true;
    }

    if (key == LogicalKeyboardKey.backspace) {
      if (inputBuffer.isNotEmpty) {
        inputBuffer = inputBuffer.substring(0, inputBuffer.length - 1);
        notifyListeners();
      }
      return true;
    }

    // Printable ASCII fallback (used when .character is not available).
    final char = _logicalKeyToChar(key);
    if (char != null) {
      inputBuffer += char;
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Append a printable [character] (from [KeyEvent.character]) to the
  /// input buffer.  This is the preferred path because Flutter resolves
  /// Shift, CapsLock, and dead-key sequences before calling this.
  ///
  /// Returns `true` so callers can uniformly return [KeyEventResult.handled].
  bool appendCharacter(String character) {
    if (character.isEmpty) return false;
    // Skip control characters (ASCII < 32).
    if (character.codeUnitAt(0) < 32) return false;
    inputBuffer += character;
    notifyListeners();
    return true;
  }

  // ── Execution ────────────────────────────────────────────────────────

  /// Parse and execute [inputBuffer], then reset it.
  void _submit() {
    final raw = inputBuffer.trim();
    inputBuffer = '';
    if (raw.isEmpty) return;

    // Echo the typed line to history.
    _appendLine('> $raw');

    final parts = raw.split(RegExp(r'\s+'));
    final cmdName = parts.first.toLowerCase();
    final args = parts.skip(1).toList();

    final entry = _commands[cmdName];
    if (entry == null) {
      _appendLine(
        "Unknown command: '$cmdName'. Type 'help' for a list of commands.",
      );
      return;
    }

    final output = entry.handler(args);
    if (output != null && output.isNotEmpty) {
      _appendLine(output);
    }
  }

  void _appendLine(String line) {
    _history.add(line);
    if (_history.length > _maxHistoryLines) {
      _history.removeAt(0);
    }
    notifyListeners();
  }

  // ── Built-in handlers ────────────────────────────────────────────────

  String? _handleHelp(List<String> _) {
    final buf = StringBuffer('Available commands:');
    for (final entry in _commands.values) {
      buf.write('\n  ${entry.name.padRight(14)} ${entry.description}');
    }
    return buf.toString();
  }

  // ── Key-to-char mapping ──────────────────────────────────────────────

  /// Returns the printable character for [key], or null if non-printable.
  ///
  /// Handles a-z, A-Z (via Shift), 0-9, space, and common punctuation.
  static String? _logicalKeyToChar(LogicalKeyboardKey key) {
    // Digits
    final digitKeys = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
    };
    final digit = digitKeys[key];
    if (digit != null) return digit;

    // Numpad digits
    final numpadKeys = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    final numpad = numpadKeys[key];
    if (numpad != null) return numpad;

    // Space
    if (key == LogicalKeyboardKey.space) return ' ';

    // Letters (lowercase by default; Shift is not tracked here — the
    // GameWidget maps KeyDownEvent.character when available instead; this is
    // a fallback for environments that don't expose .character).
    final label = key.keyLabel;
    if (label.length == 1) {
      final codeUnit = label.codeUnitAt(0);
      if ((codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122)) {
        return label.toLowerCase();
      }
    }

    // Common punctuation / symbols
    final punctuation = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.minus: '-',
      LogicalKeyboardKey.equal: '=',
      LogicalKeyboardKey.bracketLeft: '[',
      LogicalKeyboardKey.bracketRight: ']',
      LogicalKeyboardKey.semicolon: ';',
      LogicalKeyboardKey.quote: "'",
      LogicalKeyboardKey.comma: ',',
      LogicalKeyboardKey.period: '.',
      LogicalKeyboardKey.slash: '/',
      LogicalKeyboardKey.backslash: '\\',
      LogicalKeyboardKey.underscore: '_',
    };
    return punctuation[key];
  }
}

// ── Internal types ────────────────────────────────────────────────────────

class _CommandEntry {
  const _CommandEntry({
    required this.name,
    required this.description,
    required this.handler,
  });

  final String name;
  final String description;
  final TerminalCommandHandler handler;
}
