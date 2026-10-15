/// Yarn Spinner (.yarn) source parser.
///
/// Converts a tokenized Yarn Spinner file into a [DialogueGraph] AST.
library;

import '../core/dialogue_graph.dart';
import '../core/dialogue_statement.dart';
import 'yarn_tokenizer.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parses Yarn Spinner 2.x dialogue source into a [DialogueGraph].
///
/// Each `.yarn` file may contain one or more *nodes* (knots).  Multiple files
/// can be merged together via [DialogueGraph.merge].
///
/// **Supported features**
/// * Multi-node files (`title:` / `tags:` / custom header metadata)
/// * Dialogue lines with optional `Character: ` prefix
/// * `#line:key`, `#audio:key`, and arbitrary `#tag` annotations
/// * `{$varName}` inline variable substitution markers (preserved for runtime)
/// * `-> choice` options with optional indented bodies, and a condition as
///   `-> text <<if condition>>` or a `#if condition` tag
/// * `<<if>>` / `<<elseif>>` / `<<else>>` / `<<endif>>` conditional blocks
/// * `<<jump NodeTitle>>`, `<<stop>>`
/// * `<<set $var = expr>>` / `<<set $var to expr>>` variable assignment
/// * `<<declare $var = expr>>` (an `as Type` after it is ignored): the
///   variable's first value, set only while it has none
/// * Custom `<<commandName arg1 arg2>>` commands
/// * `// comment` stripping
/// * Escapes in lines and options: `\#`, `\\`, `\{`, `\}`, `\<`, `\>`,
///   `\[`, `\]` and `\/` stand for the character itself, so `Item \#5` is
///   text, not a tag. A `{$var}` written with escaped braces is still
///   filled in when the line runs.
///
/// **Usage**
/// ```dart
/// final graph = YarnParser.parse(yarnSource, id: 'innkeeper');
/// ```
class YarnParser {
  /// Parses [source] and returns a [DialogueGraph] with the given [id].
  ///
  /// Throws a [YarnParseException], with the line it is on, on malformed
  /// input: a node with no `title:`, two nodes with the same title, an
  /// `<<if>>` with no `<<endif>>` before its node ends, an
  /// `<<elseif>>`, `<<else>>` or `<<endif>>` with no `<<if>>`, or a
  /// `<<set>>` or `<<declare>>` that is not `$name = value` (or
  /// `$name to value`).
  static DialogueGraph parse(String source, {required String id}) {
    final tokens = YarnTokenizer.tokenize(source);
    final nodes = <String, DialogueNode>{};
    int cursor = 0;

    while (cursor < tokens.length) {
      final tok = tokens[cursor];

      // Skip blanks / comments between nodes
      if (tok.type == TokenType.blank || tok.type == TokenType.comment) {
        cursor++;
        continue;
      }

      // Expect a header line to start a new node
      if (tok.type == TokenType.header || tok.type == TokenType.contentStart) {
        final result = _parseNode(tokens, cursor);
        cursor = result.cursor;
        final node = result.node;
        if (node != null) {
          if (nodes.containsKey(node.title)) {
            throw YarnParseException(
              'Two nodes are titled "${node.title}"',
              lineNumber: tok.lineNumber,
            );
          }
          nodes[node.title] = node;
        }
      } else {
        cursor++;
      }
    }

    return DialogueGraph(id: id, nodes: nodes);
  }

  // ---------------------------------------------------------------------------
  // Node parsing
  // ---------------------------------------------------------------------------

  static _NodeResult _parseNode(List<YarnToken> tokens, int start) {
    int cursor = start;
    final headers = <String, String>{};
    List<String> tags = const [];

    // -- Header block --
    while (cursor < tokens.length) {
      final tok = tokens[cursor];
      if (tok.type == TokenType.contentStart) {
        cursor++;
        break;
      }
      if (tok.type == TokenType.nodeEnd) {
        cursor++;
        return _NodeResult(cursor: cursor, node: null);
      }
      if (tok.type == TokenType.header) {
        final colonIdx = tok.value.indexOf(':');
        if (colonIdx > 0) {
          final key = tok.value.substring(0, colonIdx).trim().toLowerCase();
          final val = tok.value.substring(colonIdx + 1).trim();
          if (key == 'tags') {
            tags = val
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .toList();
          } else {
            headers[key] = val;
          }
        }
      }
      cursor++;
    }

    final title = headers['title'];
    if (title == null || title.isEmpty) {
      throw YarnParseException(
        'A node has no "title:" header',
        lineNumber: tokens[start].lineNumber,
      );
    }

    final metadata = Map<String, String>.from(headers)..remove('title');

    // -- Content block --
    final stmtResult = _parseStatements(
      tokens,
      cursor,
      baseIndent: 0,
      depth: 0,
    );
    cursor = stmtResult.cursor;

    // Consume '==='
    if (cursor < tokens.length && tokens[cursor].type == TokenType.nodeEnd) {
      cursor++;
    }

    return _NodeResult(
      cursor: cursor,
      node: DialogueNode(
        title: title,
        tags: tags,
        metadata: metadata,
        statements: stmtResult.statements,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Statement list parsing
  // ---------------------------------------------------------------------------

  /// Recursively parses statements.
  ///
  /// * [baseIndent] – stop if a non-blank token has strictly lower indent
  ///   (used for choice bodies).
  /// * [depth] – how many `<<if>>` blocks the statements sit in. Inside one,
  ///   an `<<elseif>>`, `<<else>>` or `<<endif>>` stops the list without
  ///   being consumed, for the enclosing block to read; at 0 it has no
  ///   `<<if>>` and throws.
  static _StmtListResult _parseStatements(
    List<YarnToken> tokens,
    int start, {
    required int baseIndent,
    required int depth,
  }) {
    int cursor = start;
    final statements = <DialogueStatement>[];

    while (cursor < tokens.length) {
      final tok = tokens[cursor];

      if (tok.type == TokenType.blank || tok.type == TokenType.comment) {
        cursor++;
        continue;
      }

      // Hard stops
      if (tok.type == TokenType.nodeEnd) break;

      if (tok.type == TokenType.commandElseIf ||
          tok.type == TokenType.commandElse ||
          tok.type == TokenType.commandEndIf) {
        if (depth == 0) {
          throw YarnParseException(
            '<<${_commandName(tok.type)}>> without <<if>>',
            lineNumber: tok.lineNumber,
          );
        }
        // The enclosing <<if>> takes it from here.
        break;
      }

      // Indent-based stop for choice bodies
      if (tok.indentLevel < baseIndent) break;

      switch (tok.type) {
        case TokenType.line:
          statements.add(_parseLine(tok));
          cursor++;

        case TokenType.choice:
          final choiceResult = _parseChoiceSet(
            tokens,
            cursor,
            choiceIndent: tok.indentLevel,
            depth: depth,
          );
          cursor = choiceResult.cursor;
          statements.add(ChoiceSetStatement(choices: choiceResult.choices));

        case TokenType.commandIf:
          final ifResult = _parseConditional(tokens, cursor, depth: depth);
          cursor = ifResult.cursor;
          statements.add(ifResult.statement);

        case TokenType.commandJump:
          statements.add(JumpStatement(target: tok.value));
          cursor++;

        case TokenType.commandStop:
          statements.add(const StopStatement());
          cursor++;

        case TokenType.commandSet || TokenType.commandDeclare:
          statements.add(_parseSet(tok));
          cursor++;

        case TokenType.command:
          final spaceIdx = tok.value.indexOf(' ');
          final name = spaceIdx > 0
              ? tok.value.substring(0, spaceIdx)
              : tok.value;
          final rawArgs = spaceIdx > 0 ? tok.value.substring(spaceIdx + 1) : '';
          statements.add(CommandStatement(name: name, rawArgs: rawArgs));
          cursor++;

        default:
          cursor++;
      }
    }

    return _StmtListResult(cursor: cursor, statements: statements);
  }

  // ---------------------------------------------------------------------------
  // Choice set parsing
  // ---------------------------------------------------------------------------

  static _ChoiceSetResult _parseChoiceSet(
    List<YarnToken> tokens,
    int start, {
    required int choiceIndent,
    required int depth,
  }) {
    int cursor = start;
    final choices = <ChoiceOption>[];

    while (cursor < tokens.length) {
      final tok = tokens[cursor];

      if (tok.type == TokenType.blank || tok.type == TokenType.comment) {
        cursor++;
        continue;
      }

      // Stop: no longer a choice at the same indent level
      if (tok.type != TokenType.choice || tok.indentLevel != choiceIndent) {
        break;
      }
      if (tok.type == TokenType.nodeEnd) break;

      cursor++; // consume the `->` token

      // Parse choice header tags
      final (rawText, tags, lineKey, audioKey, condition) = _parseChoiceHeader(
        tok.value,
      );

      // Parse indented body
      final bodyResult = _parseStatements(
        tokens,
        cursor,
        baseIndent: choiceIndent + 1,
        depth: depth,
      );
      cursor = bodyResult.cursor;

      choices.add(
        ChoiceOption(
          rawText: rawText,
          lineKey: lineKey,
          audioKey: audioKey,
          condition: condition,
          tags: tags,
          body: bodyResult.statements,
        ),
      );
    }

    return _ChoiceSetResult(cursor: cursor, choices: choices);
  }

  // ---------------------------------------------------------------------------
  // Conditional block parsing
  // ---------------------------------------------------------------------------

  static _ConditionalResult _parseConditional(
    List<YarnToken> tokens,
    int start, {
    required int depth,
  }) {
    int cursor = start;
    final branches = <ConditionalBranch>[];
    var closed = false;

    // <<if condition>>
    final ifTok = tokens[cursor++];
    final ifBody = _parseStatements(
      tokens,
      cursor,
      baseIndent: 0,
      depth: depth + 1,
    );
    cursor = ifBody.cursor;
    branches.add(
      ConditionalBranch(condition: ifTok.value, body: ifBody.statements),
    );

    // <<elseif>> / <<else>> / <<endif>>
    while (cursor < tokens.length) {
      final tok = tokens[cursor];
      if (tok.type == TokenType.commandEndIf) {
        cursor++;
        closed = true;
        break;
      }
      if (tok.type == TokenType.commandElseIf) {
        cursor++;
        final body = _parseStatements(
          tokens,
          cursor,
          baseIndent: 0,
          depth: depth + 1,
        );
        cursor = body.cursor;
        branches.add(
          ConditionalBranch(condition: tok.value, body: body.statements),
        );
      } else if (tok.type == TokenType.commandElse) {
        cursor++;
        final body = _parseStatements(
          tokens,
          cursor,
          baseIndent: 0,
          depth: depth + 1,
        );
        cursor = body.cursor;
        branches.add(ConditionalBranch(condition: null, body: body.statements));
      } else if (tok.type == TokenType.blank || tok.type == TokenType.comment) {
        cursor++;
      } else {
        break;
      }
    }
    if (!closed) {
      throw YarnParseException(
        '<<if>> without <<endif>>',
        lineNumber: ifTok.lineNumber,
      );
    }

    return _ConditionalResult(
      cursor: cursor,
      statement: ConditionalStatement(branches: branches),
    );
  }

  // ---------------------------------------------------------------------------
  // Line helpers
  // ---------------------------------------------------------------------------

  static LineStatement _parseLine(YarnToken tok) {
    final (text, tags) = _extractTags(tok.value);

    // Separate "Character: body" — character names have no spaces
    String? character;
    String body = text.trim();
    final colonIdx = body.indexOf(':');
    if (colonIdx > 0) {
      final candidate = body.substring(0, colonIdx).trim();
      if (candidate.isNotEmpty && !candidate.contains(' ')) {
        character = candidate;
        body = body.substring(colonIdx + 1).trim();
      }
    }

    String? lineKey;
    String? audioKey;
    final remaining = <String>[];
    for (final tag in tags) {
      if (tag.startsWith('line:')) {
        lineKey = tag.substring(5);
      } else if (tag.startsWith('audio:')) {
        audioKey = tag.substring(6);
      } else {
        remaining.add(tag);
      }
    }

    return LineStatement(
      character: character,
      rawText: body,
      lineKey: lineKey,
      audioKey: audioKey,
      tags: remaining,
    );
  }

  /// Parses a `-> choice text <<if condition>> #tags #if condition` header.
  static (
    String rawText,
    List<String> tags,
    String? lineKey,
    String? audioKey,
    String? condition,
  )
  _parseChoiceHeader(String raw) {
    var header = raw;
    String? lineCondition;
    final inline = _optionCondition.firstMatch(header);
    if (inline != null) {
      lineCondition = inline.group(1)!.trim();
      header = header.replaceRange(inline.start, inline.end, ' ');
    }
    final (text, tags) = _extractTags(header);

    String? lineKey;
    String? audioKey;
    String? tagCondition;
    final remaining = <String>[];

    for (final tag in tags) {
      if (tag.startsWith('line:')) {
        lineKey = tag.substring(5);
      } else if (tag.startsWith('audio:')) {
        audioKey = tag.substring(6);
      } else if (tag.startsWith('if ')) {
        tagCondition = tag.substring(3).trim();
      } else {
        remaining.add(tag);
      }
    }

    final condition = switch ((lineCondition, tagCondition)) {
      (final a?, final b?) => '($a) && ($b)',
      (final a?, null) => a,
      (null, final b) => b,
    };
    return (text.trim(), remaining, lineKey, audioKey, condition);
  }

  static SetStatement _parseSet(YarnToken tok) {
    final declare = tok.type == TokenType.commandDeclare;
    final match = _assignment.firstMatch(tok.value);
    if (match == null) {
      // A lone `<<set $flag>>` sets it to true.
      final flag = RegExp(r'^\$?(\w+)$').firstMatch(tok.value);
      if (flag == null) {
        throw YarnParseException(
          '<<${declare ? 'declare' : 'set'} ${tok.value}>> is not '
          '"\$name = value" or "\$name to value"',
          lineNumber: tok.lineNumber,
        );
      }
      return SetStatement(
        variable: flag.group(1)!,
        expression: 'true',
        isDeclaration: declare,
      );
    }
    var expression = match.group(2)!.trim();
    if (declare) expression = expression.replaceFirst(_declaredType, '');
    return SetStatement(
      variable: match.group(1)!,
      expression: expression,
      isDeclaration: declare,
    );
  }

  /// [text] with its escapes replaced by the characters they stand for.
  static String _unescape(String text) => text.contains(r'\')
      ? text.replaceAllMapped(_escape, (m) => m.group(1)!)
      : text;

  /// Extracts trailing `#tag` annotations from [line], and resolves the
  /// escapes in what is left.
  ///
  /// Tags are only recognised outside `{...}` interpolation blocks, and an
  /// escaped `\#` is text. Returns `(textWithoutTags, tagList)`.
  static (String, List<String>) _extractTags(String line) {
    // Where tags start: `#`s outside braces that are not escaped.
    final hashes = <int>[];
    var depth = 0;
    for (var i = 0; i < line.length; i++) {
      switch (line[i]) {
        case r'\':
          i++; // the escaped character is text
        case '{':
          depth++;
        case '}':
          if (depth > 0) depth--;
        case '#':
          if (depth == 0) hashes.add(i);
      }
    }
    if (hashes.isEmpty) return (_unescape(line.trim()), <String>[]);
    final tags = <String>[
      for (var k = 0; k < hashes.length; k++)
        _unescape(
          line
              .substring(
                hashes[k] + 1,
                k + 1 < hashes.length ? hashes[k + 1] : line.length,
              )
              .trim(),
        ),
    ];
    return (_unescape(line.substring(0, hashes.first).trim()), tags);
  }

  static String _commandName(TokenType type) => switch (type) {
    TokenType.commandElseIf => 'elseif',
    TokenType.commandElse => 'else',
    _ => 'endif',
  };
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Thrown when a Yarn Spinner source string cannot be parsed.
class YarnParseException implements Exception {
  /// A failure described by [message], at source line [lineNumber] when
  /// known; [toString] prints both.
  const YarnParseException(this.message, {this.lineNumber});

  /// What is wrong with the source.
  final String message;

  /// The 1-based source line the failure is on, or null when it is not
  /// tied to one line.
  final int? lineNumber;

  @override
  String toString() => lineNumber != null
      ? 'YarnParseException (line $lineNumber): $message'
      : 'YarnParseException: $message';
}

// ---------------------------------------------------------------------------
// Internal result types
// ---------------------------------------------------------------------------

class _NodeResult {
  _NodeResult({required this.cursor, required this.node});
  final int cursor;
  final DialogueNode? node;
}

class _StmtListResult {
  _StmtListResult({required this.cursor, required this.statements});
  final int cursor;
  final List<DialogueStatement> statements;
}

class _ChoiceSetResult {
  _ChoiceSetResult({required this.cursor, required this.choices});
  final int cursor;
  final List<ChoiceOption> choices;
}

class _ConditionalResult {
  _ConditionalResult({required this.cursor, required this.statement});
  final int cursor;
  final ConditionalStatement statement;
}

/// An option's `<<if condition>>` (not an escaped `\<<`).
final RegExp _optionCondition = RegExp(r'(?<!\\)<<\s*if\s+(.*)>>');

/// `$name = value` or `$name to value` (the `$` optional).
final RegExp _assignment = RegExp(
  r'^\$?(\w+)\s*(?:=|\bto\b)\s*(.+)$',
  caseSensitive: false,
);

/// A `<<declare>>`'s type, which a dynamic store has no use for.
final RegExp _declaredType = RegExp(r'\s+as\s+\w+$', caseSensitive: false);

/// The escapes Yarn has in text: a backslash, then the character meant.
final RegExp _escape = RegExp(r'\\([\\#{}<>\[\]/])');
