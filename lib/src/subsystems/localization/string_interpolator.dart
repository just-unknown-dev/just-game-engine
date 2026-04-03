/// String interpolation and plural rule engine.
library;

// ---------------------------------------------------------------------------
// StringInterpolator
// ---------------------------------------------------------------------------

/// Performs `{variable}` substitution and ICU-lite plural selection on a
/// localized string template.
///
/// **Variable substitution**
/// Use `{name}` placeholders — values come from the [args] map:
/// ```dart
/// StringInterpolator.process(
///   'Hello, {playerName}! You have {gold} gold.',
///   {'playerName': 'Aria', 'gold': 42},
/// );
/// // → 'Hello, Aria! You have 42 gold.'
/// ```
///
/// **Plural selection** (ICU-lite syntax)
/// ```
/// {count, plural, =0{No items} =1{One item} other{{count} items}}
/// ```
/// Supported selectors: `=0`, `=1`, `=2`, … exact matches, plus `other`
/// fallback.  Nested variables inside plural branches are also substituted.
///
/// **Gender selection**
/// ```
/// {gender, select, male{He arrived} female{She arrived} other{They arrived}}
/// ```
///
/// Nesting limit: ICU forms are resolved **once** (no recursive ICU inside
/// ICU) to prevent runaway parsing.
class StringInterpolator {
  /// Resolves all `{…}` expressions in [template] using [args].
  ///
  /// [args] values are converted to `String` via `.toString()`.
  static String process(
    String template, [
    Map<String, Object?> args = const {},
  ]) {
    if (!template.contains('{')) return template;
    return _resolve(template, args, depth: 0);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static const int _maxDepth = 2;

  static String _resolve(
    String template,
    Map<String, Object?> args, {
    // Depth guard: stop after 2 passes to handle one level of ICU nesting.
    required int depth,
  }) {
    if (depth >= _maxDepth) return template;

    final buf = StringBuffer();
    int i = 0;

    while (i < template.length) {
      if (template[i] != '{') {
        buf.write(template[i++]);
        continue;
      }

      // Find the matching closing brace, honouring nesting
      final end = _matchingBrace(template, i);
      if (end < 0) {
        // Unmatched '{' — emit literally
        buf.write(template[i++]);
        continue;
      }

      final inner = template.substring(i + 1, end);
      final resolved = _resolveBraced(inner, args, depth: depth);
      buf.write(resolved);
      i = end + 1;
    }

    return buf.toString();
  }

  /// Resolves the content *inside* `{}`.
  static String _resolveBraced(
    String inner,
    Map<String, Object?> args, {
    required int depth,
  }) {
    final commaIdx = inner.indexOf(',');
    if (commaIdx < 0) {
      // Simple variable: {varName}
      final key = inner.trim();
      return args[key]?.toString() ?? '{$key}';
    }

    // ICU-format: {varName, type, ...}
    final varName = inner.substring(0, commaIdx).trim();
    final rest = inner.substring(commaIdx + 1).trimLeft();
    final commaIdx2 = rest.indexOf(',');
    if (commaIdx2 < 0) {
      // malformed — return raw variable
      return args[varName]?.toString() ?? '{$varName}';
    }

    final type = rest.substring(0, commaIdx2).trim().toLowerCase();
    final choicesStr = rest.substring(commaIdx2 + 1).trim();

    return switch (type) {
      'plural' => _selectPlural(varName, choicesStr, args, depth: depth),
      'select' => _selectGeneric(varName, choicesStr, args, depth: depth),
      _ => args[varName]?.toString() ?? '{$varName}',
    };
  }

  // ---- Plural selection ----------------------------------------------------

  static String _selectPlural(
    String varName,
    String choicesStr,
    Map<String, Object?> args, {
    required int depth,
  }) {
    final value = args[varName];
    final count = switch (value) {
      int n => n,
      double d => d.truncate(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

    final choices = _parseChoices(choicesStr);

    final branch =
        choices['=$count'] // exact match first
        ??
        (count == 1 ? choices['one'] : null) ??
        choices['other'] ??
        choices.values.firstOrNull ??
        '';

    // Substitute variables inside the branch (one extra level)
    return _resolve(branch, {...args, varName: count}, depth: depth + 1);
  }

  // ---- Generic select -------------------------------------------------------

  static String _selectGeneric(
    String varName,
    String choicesStr,
    Map<String, Object?> args, {
    required int depth,
  }) {
    final value = args[varName]?.toString() ?? '';
    final choices = _parseChoices(choicesStr);
    final branch = choices[value] ?? choices['other'] ?? '';
    return _resolve(branch, args, depth: depth + 1);
  }

  // ---- Choice parser -------------------------------------------------------

  /// Parses `=0{text} =1{text} other{text}` into a map.
  static Map<String, String> _parseChoices(String src) {
    final result = <String, String>{};
    int i = 0;

    while (i < src.length) {
      // Skip whitespace
      while (i < src.length && _isWs(src[i])) {
        i++;
      }
      if (i >= src.length) break;

      // Read selector (everything up to '{')
      final keyStart = i;
      while (i < src.length && src[i] != '{') {
        i++;
      }
      if (i >= src.length) break;

      final selector = src.substring(keyStart, i).trim();

      // Read brace-delimited value
      final braceEnd = _matchingBrace(src, i);
      if (braceEnd < 0) break;

      result[selector] = src.substring(i + 1, braceEnd);
      i = braceEnd + 1;
    }

    return result;
  }

  // ---- Brace matcher -------------------------------------------------------

  static int _matchingBrace(String s, int openIdx) {
    int depth = 0;
    for (int i = openIdx; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static bool _isWs(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';
}
