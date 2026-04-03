/// AST node types produced by the Yarn Spinner parser.
///
/// Each [DialogueStatement] subclass represents one logical unit of a Yarn
/// Spinner dialogue node: a spoken line, a set of player choices, a jump, a
/// conditional block, a variable assignment, or a custom command.
library;

// ---------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------

/// Base class for every statement in a parsed dialogue node.
abstract class DialogueStatement {
  const DialogueStatement();
}

// ---------------------------------------------------------------------------
// Dialogue line
// ---------------------------------------------------------------------------

/// A single spoken line, optionally attributed to a character.
///
/// Corresponds to Yarn lines of the form:
/// ```
/// Innkeeper: Welcome, {$playerName}! #line:inn.welcome #audio:inn_welcome_vo
/// ```
class LineStatement extends DialogueStatement {
  const LineStatement({
    this.character,
    required this.rawText,
    this.lineKey,
    this.audioKey,
    this.tags = const [],
  });

  /// Speaker name, or `null` for narrator lines.
  final String? character;

  /// Raw text from the Yarn source. May contain `{$varName}` substitutions.
  final String rawText;

  /// Localization key from a `#line:key` tag — used to look up translated
  /// text at runtime.
  final String? lineKey;

  /// Audio clip key from a `#audio:key` tag — played by [DialogueRunner] if
  /// an audio system is connected.
  final String? audioKey;

  /// Remaining metadata tags (after stripping `line:` and `audio:` entries).
  final List<String> tags;
}

// ---------------------------------------------------------------------------
// Choices
// ---------------------------------------------------------------------------

/// A set of player-selectable options at the same indentation level.
///
/// Corresponds to a contiguous run of `->` lines in Yarn.
class ChoiceSetStatement extends DialogueStatement {
  const ChoiceSetStatement({required this.choices});

  final List<ChoiceOption> choices;
}

/// One option inside a [ChoiceSetStatement].
class ChoiceOption {
  const ChoiceOption({
    required this.rawText,
    this.lineKey,
    this.audioKey,
    this.condition,
    this.tags = const [],
    required this.body,
  });

  /// Raw display text; may contain `{$varName}` substitutions.
  final String rawText;

  /// Localization key from a `#line:key` tag.
  final String? lineKey;

  /// Audio key from a `#audio:key` tag.
  final String? audioKey;

  /// Optional Yarn expression string (from `#if <expr>` tag or `<<if>>` on
  /// the choice header). When `null` the choice is always available.
  final String? condition;

  /// Metadata tags found on the `->` line.
  final List<String> tags;

  /// Statements executed when the player selects this option.
  final List<DialogueStatement> body;
}

// ---------------------------------------------------------------------------
// Control flow
// ---------------------------------------------------------------------------

/// `<<jump NodeTitle>>` — unconditionally jumps to another node.
class JumpStatement extends DialogueStatement {
  const JumpStatement({required this.target});

  /// The title of the node to jump to.
  final String target;
}

/// `<<stop>>` — immediately ends the dialogue session.
class StopStatement extends DialogueStatement {
  const StopStatement();
}

// ---------------------------------------------------------------------------
// Variable assignment
// ---------------------------------------------------------------------------

/// `<<set $variable = expression>>` — assigns a value to a Yarn variable.
class SetStatement extends DialogueStatement {
  const SetStatement({required this.variable, required this.expression});

  /// Variable name **without** the leading `$`.
  final String variable;

  /// Raw right-hand-side expression string (e.g. `"true"`, `"42"`,
  /// `"$gold + 5"`).
  final String expression;
}

// ---------------------------------------------------------------------------
// Conditional block
// ---------------------------------------------------------------------------

/// An `<<if>> … <<elseif>> … <<else>> … <<endif>>` block.
class ConditionalStatement extends DialogueStatement {
  const ConditionalStatement({required this.branches});

  /// Ordered branches; the first branch whose [ConditionalBranch.condition]
  /// evaluates to `true` (or whose condition is `null` — the else branch)
  /// is executed.
  final List<ConditionalBranch> branches;
}

/// One arm of a [ConditionalStatement].
class ConditionalBranch {
  const ConditionalBranch({this.condition, required this.body});

  /// Yarn expression string, or `null` for the `<<else>>` branch.
  final String? condition;

  final List<DialogueStatement> body;
}

// ---------------------------------------------------------------------------
// Custom command
// ---------------------------------------------------------------------------

/// A generic `<<commandName arg1 arg2 …>>` statement.
///
/// Built-in commands (`jump`, `stop`, `set`, `if`) are parsed into their
/// own statement types. Everything else lands here and is dispatched through
/// [DialogueCommandRegistry].
class CommandStatement extends DialogueStatement {
  const CommandStatement({required this.name, this.rawArgs = ''});

  /// Command name (lowercased).
  final String name;

  /// Everything after the command name, raw and untrimmed.
  final String rawArgs;
}
