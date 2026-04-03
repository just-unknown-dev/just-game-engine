/// Yarn Spinner line tokenizer.
///
/// Converts raw Yarn Spinner source text into a flat list of [YarnToken]s,
/// one per logical line. The parser ([YarnParser]) then turns this token
/// stream into a [DialogueGraph] AST.
library;

// ---------------------------------------------------------------------------
// Token types
// ---------------------------------------------------------------------------

/// Classifies the role of a single Yarn Spinner source line.
enum TokenType {
  /// Header key:value pair (e.g. `title: Start`, `tags: hub npc`).
  header,

  /// The `---` divider that ends the header block.
  contentStart,

  /// The `===` divider that ends the content block.
  nodeEnd,

  /// A dialogue line (optionally prefixed with `Character: `).
  line,

  /// A `->` choice option line.
  choice,

  /// `<<if condition>>` — opens a conditional block.
  commandIf,

  /// `<<elseif condition>>` — alternative branch.
  commandElseIf,

  /// `<<else>>` — fallback branch.
  commandElse,

  /// `<<endif>>` — closes a conditional block.
  commandEndIf,

  /// `<<jump NodeTitle>>` — unconditional jump.
  commandJump,

  /// `<<stop>>` — ends dialogue.
  commandStop,

  /// `<<set $var = expr>>` — variable assignment.
  commandSet,

  /// Any other `<<name args>>` command.
  command,

  /// A `// comment` line (skipped by the parser).
  comment,

  /// A blank line (skipped by the parser).
  blank,
}

// ---------------------------------------------------------------------------
// YarnToken
// ---------------------------------------------------------------------------

/// A single logical line from a Yarn Spinner source file.
class YarnToken {
  const YarnToken({
    required this.type,
    required this.value,
    required this.indentLevel,
    required this.lineNumber,
  });

  final TokenType type;

  /// Meaningful content of the line, trimmed of its syntactic delimiters.
  ///
  /// * For [TokenType.header]: the full `key: value` string.
  /// * For [TokenType.line]: the line body (character prefix kept).
  /// * For [TokenType.choice]: text after `->` stripped.
  /// * For [TokenType.commandIf] / [TokenType.commandElseIf]: condition string.
  /// * For [TokenType.commandJump]: target node title.
  /// * For [TokenType.commandSet]: the `$var = expr` string.
  /// * For [TokenType.command]: the full inner text (`name args`).
  final String value;

  /// Number of leading space characters (tabs count as 2).
  final int indentLevel;

  /// 1-based line number in the original source file.
  final int lineNumber;

  @override
  String toString() =>
      'Token(${type.name}, indent=$indentLevel, ln=$lineNumber, "$value")';
}

// ---------------------------------------------------------------------------
// YarnTokenizer
// ---------------------------------------------------------------------------

/// Converts a Yarn Spinner source string into a flat [YarnToken] list.
///
/// Usage:
/// ```dart
/// final tokens = YarnTokenizer.tokenize(yarnSource);
/// ```
class YarnTokenizer {
  /// Tokenizes [source] and returns the full token list.
  static List<YarnToken> tokenize(String source) {
    final tokens = <YarnToken>[];
    final lines = source.split('\n');
    bool inContent = false;
    int lineNum = 0;

    for (final rawLine in lines) {
      lineNum++;
      // Normalize CRLF
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;

      final indent = _computeIndent(line);
      final trimmed = line.trim();

      // ---- Blank line -------------------------------------------------------
      if (trimmed.isEmpty) {
        tokens.add(
          YarnToken(
            type: TokenType.blank,
            value: '',
            indentLevel: indent,
            lineNumber: lineNum,
          ),
        );
        continue;
      }

      // Strip inline // comments (outside <<...>> command brackets)
      final stripped = _stripLineComment(trimmed);

      // ---- Full-line comment ------------------------------------------------
      if (stripped.isEmpty || stripped.startsWith('//')) {
        tokens.add(
          YarnToken(
            type: TokenType.comment,
            value: stripped,
            indentLevel: indent,
            lineNumber: lineNum,
          ),
        );
        continue;
      }

      if (!inContent) {
        // ---- Header zone ----------------------------------------------------
        if (stripped == '---') {
          inContent = true;
          tokens.add(
            YarnToken(
              type: TokenType.contentStart,
              value: '---',
              indentLevel: 0,
              lineNumber: lineNum,
            ),
          );
        } else if (stripped == '===') {
          tokens.add(
            YarnToken(
              type: TokenType.nodeEnd,
              value: '===',
              indentLevel: 0,
              lineNumber: lineNum,
            ),
          );
        } else if (stripped.contains(':')) {
          tokens.add(
            YarnToken(
              type: TokenType.header,
              value: stripped,
              indentLevel: 0,
              lineNumber: lineNum,
            ),
          );
        }
        // Otherwise ignore (malformed header content)
      } else {
        // ---- Content zone ---------------------------------------------------
        if (stripped == '===') {
          inContent = false;
          tokens.add(
            YarnToken(
              type: TokenType.nodeEnd,
              value: '===',
              indentLevel: 0,
              lineNumber: lineNum,
            ),
          );
        } else if (stripped.startsWith('->')) {
          tokens.add(
            YarnToken(
              type: TokenType.choice,
              value: stripped.substring(2).trim(),
              indentLevel: indent,
              lineNumber: lineNum,
            ),
          );
        } else if (stripped.startsWith('<<') && stripped.endsWith('>>')) {
          final inner = stripped.substring(2, stripped.length - 2).trim();
          tokens.add(_classifyCommand(inner, indent, lineNum));
        } else {
          tokens.add(
            YarnToken(
              type: TokenType.line,
              value: stripped,
              indentLevel: indent,
              lineNumber: lineNum,
            ),
          );
        }
      }
    }

    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Counts leading whitespace (tabs = 2 spaces).
  static int _computeIndent(String line) {
    int count = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        count++;
      } else if (line[i] == '\t') {
        count += 2;
      } else {
        break;
      }
    }
    return count;
  }

  /// Strips `// comment` from the end of a line, ignoring occurrences inside
  /// `<<...>>` command brackets.
  static String _stripLineComment(String line) {
    bool inCmd = false;
    for (int i = 0; i < line.length; i++) {
      if (i + 1 < line.length && line[i] == '<' && line[i + 1] == '<') {
        inCmd = true;
      }
      if (i + 1 < line.length && line[i] == '>' && line[i + 1] == '>') {
        inCmd = false;
      }
      if (!inCmd &&
          line[i] == '/' &&
          i + 1 < line.length &&
          line[i + 1] == '/') {
        return line.substring(0, i).trim();
      }
    }
    return line;
  }

  /// Maps the inner text of a `<< … >>` block to the correct [TokenType].
  static YarnToken _classifyCommand(String inner, int indent, int lineNum) {
    final lower = inner.toLowerCase();

    if (lower.startsWith('if ') || lower == 'if') {
      return YarnToken(
        type: TokenType.commandIf,
        value: inner.length > 3 ? inner.substring(3).trim() : '',
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower.startsWith('elseif ') || lower == 'elseif') {
      return YarnToken(
        type: TokenType.commandElseIf,
        value: inner.length > 7 ? inner.substring(7).trim() : '',
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower == 'else') {
      return YarnToken(
        type: TokenType.commandElse,
        value: '',
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower == 'endif') {
      return YarnToken(
        type: TokenType.commandEndIf,
        value: '',
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower.startsWith('jump ')) {
      return YarnToken(
        type: TokenType.commandJump,
        value: inner.substring(5).trim(),
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower == 'stop') {
      return YarnToken(
        type: TokenType.commandStop,
        value: '',
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }
    if (lower.startsWith('set ')) {
      // Value: everything after "set " — e.g. "$gold = 5"
      return YarnToken(
        type: TokenType.commandSet,
        value: inner.substring(4).trim(),
        indentLevel: indent,
        lineNumber: lineNum,
      );
    }

    // Generic command — first word is the name, rest are args
    return YarnToken(
      type: TokenType.command,
      value: inner,
      indentLevel: indent,
      lineNumber: lineNum,
    );
  }
}
