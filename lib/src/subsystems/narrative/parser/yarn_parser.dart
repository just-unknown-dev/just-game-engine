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
/// * `-> choice` options with optional indented bodies and `#if condition` tags
/// * `<<if>>` / `<<elseif>>` / `<<else>>` / `<<endif>>` conditional blocks
/// * `<<jump NodeTitle>>`, `<<stop>>`
/// * `<<set $var = expr>>` variable assignment
/// * Custom `<<commandName arg1 arg2>>` commands
/// * `// comment` stripping
///
/// **Usage**
/// ```dart
/// final graph = YarnParser.parse(yarnSource, id: 'innkeeper');
/// ```
class YarnParser {
  /// Parses [source] and returns a [DialogueGraph] with the given [id].
  ///
  /// Throws [YarnParseException] on malformed input.
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
        if (result.node != null) {
          nodes[result.node!.title] = result.node!;
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
      // Skip malformed node
      return _NodeResult(cursor: cursor, node: null);
    }

    final metadata = Map<String, String>.from(headers)..remove('title');

    // -- Content block --
    final stmtResult = _parseStatements(tokens, cursor, baseIndent: 0);
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
  /// * [stopAtElseOrEndIf] – stop at `<<elseif>>`, `<<else>>`, or `<<endif>>`
  ///   without consuming the token (used for if-block branches).
  static _StmtListResult _parseStatements(
    List<YarnToken> tokens,
    int start, {
    required int baseIndent,
    bool stopAtElseOrEndIf = false,
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

      if (stopAtElseOrEndIf &&
          (tok.type == TokenType.commandElseIf ||
              tok.type == TokenType.commandElse ||
              tok.type == TokenType.commandEndIf)) {
        break;
      }
      if (tok.type == TokenType.commandEndIf) break;

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
          );
          cursor = choiceResult.cursor;
          statements.add(ChoiceSetStatement(choices: choiceResult.choices));

        case TokenType.commandIf:
          final ifResult = _parseConditional(tokens, cursor);
          cursor = ifResult.cursor;
          statements.add(ifResult.statement);

        case TokenType.commandJump:
          statements.add(JumpStatement(target: tok.value));
          cursor++;

        case TokenType.commandStop:
          statements.add(const StopStatement());
          cursor++;

        case TokenType.commandSet:
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
    int start,
  ) {
    int cursor = start;
    final branches = <ConditionalBranch>[];

    // <<if condition>>
    final ifTok = tokens[cursor++];
    final ifBody = _parseStatements(
      tokens,
      cursor,
      baseIndent: 0,
      stopAtElseOrEndIf: true,
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
        break;
      }
      if (tok.type == TokenType.commandElseIf) {
        cursor++;
        final body = _parseStatements(
          tokens,
          cursor,
          baseIndent: 0,
          stopAtElseOrEndIf: true,
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
          stopAtElseOrEndIf: true,
        );
        cursor = body.cursor;
        branches.add(ConditionalBranch(condition: null, body: body.statements));
      } else if (tok.type == TokenType.blank || tok.type == TokenType.comment) {
        cursor++;
      } else {
        break;
      }
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

  /// Parses a `-> choice text #tags #if condition` header.
  static (
    String rawText,
    List<String> tags,
    String? lineKey,
    String? audioKey,
    String? condition,
  )
  _parseChoiceHeader(String raw) {
    final (text, tags) = _extractTags(raw);

    String? lineKey;
    String? audioKey;
    String? condition;
    final remaining = <String>[];

    for (final tag in tags) {
      if (tag.startsWith('line:')) {
        lineKey = tag.substring(5);
      } else if (tag.startsWith('audio:')) {
        audioKey = tag.substring(6);
      } else if (tag.startsWith('if ')) {
        condition = tag.substring(3).trim();
      } else {
        remaining.add(tag);
      }
    }

    return (text.trim(), remaining, lineKey, audioKey, condition);
  }

  static SetStatement _parseSet(YarnToken tok) {
    // tok.value = "$var = expression"
    final eqIdx = tok.value.indexOf('=');
    if (eqIdx < 0) {
      return SetStatement(
        variable: tok.value.replaceAll(r'$', '').trim(),
        expression: 'true',
      );
    }
    final varName = tok.value.substring(0, eqIdx).trim().replaceAll(r'$', '');
    final expr = tok.value.substring(eqIdx + 1).trim();
    return SetStatement(variable: varName, expression: expr);
  }

  /// Extracts trailing `#tag` annotations from [line].
  ///
  /// Tags are only recognised outside `{...}` interpolation blocks.
  /// Returns `(textWithoutTags, tagList)`.
  static (String, List<String>) _extractTags(String line) {
    final tags = <String>[];
    var text = line;
    while (true) {
      final hashIdx = _lastHashOutsideBraces(text);
      if (hashIdx < 0) break;
      tags.insert(0, text.substring(hashIdx + 1).trim());
      text = text.substring(0, hashIdx).trim();
    }
    return (text, tags);
  }

  static int _lastHashOutsideBraces(String text) {
    int depth = 0;
    for (int i = text.length - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '}') depth++;
      if (c == '{') depth--;
      if (c == '#' && depth == 0) return i;
    }
    return -1;
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Thrown when a Yarn Spinner source string cannot be parsed.
class YarnParseException implements Exception {
  const YarnParseException(this.message, {this.lineNumber});

  final String message;
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
