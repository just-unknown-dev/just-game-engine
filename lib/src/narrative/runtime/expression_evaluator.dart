/// Simple recursive-descent evaluator for Yarn Spinner condition expressions.
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../core/dialogue_variable_store.dart';
import 'dialogue_condition_registry.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Evaluates Yarn Spinner condition and assignment expressions at runtime.
///
/// **Supported syntax**
/// * Literals: `true`, `false`, integers, floats, `"strings"`, `'strings'`
///   (a backslash escapes the next character)
/// * Variables: `$varName` — read from [DialogueVariableStore]
/// * Registered predicates: `[predicateName]` — see [DialogueConditionRegistry]
/// * Arithmetic: `+`, `-`, `*`, `/`, `%`, prefix `-`; `+` joins strings
/// * Comparisons: `==`, `!=`, `>`, `>=`, `<`, `<=` — or the Yarn words
///   `eq`, `is`, `neq`, `gt`, `gte`, `lt`, `lte`
/// * Logical: `&&` / `and`, `||` / `or`, `^` / `xor`, prefix `!` / `not`
/// * Grouping: `( … )`
///
/// Precedence follows Yarn Spinner's, tightest first: prefix `!` and `-`;
/// `*` `/` `%`; `+` `-`; `<` `<=` `>` `>=`; `==` `!=`; `and`; `or`; `xor`.
/// So `!$a == $b` is `(!$a) == $b`.
///
/// Anything else — a bare word with no `$`, a function call such as
/// `visited("Shop")`, an operator with nothing after it, text left over
/// after the expression — makes the expression unevaluable: see
/// [evaluateBool] and [evaluate].
///
/// ```dart
/// final eval = ExpressionEvaluator(variables: vars, conditions: registry);
///
/// eval.evaluateBool(r'$questDone == true && $gold >= 10');
/// eval.evaluateBool(r'$questDone and not $paid');
/// eval.evaluateBool('[playerHasKey]');
/// eval.evaluate(r'$gold + 5');
/// ```
class ExpressionEvaluator {
  /// An evaluator reading `$name` from [variables] and calling `[name]`
  /// from [conditions]; it keeps no state of its own between calls.
  ExpressionEvaluator({required this.variables, required this.conditions});

  /// Where `$name` variables are read from; evaluating never writes to it.
  final DialogueVariableStore variables;

  /// The predicates `[name]` in an expression calls.
  final DialogueConditionRegistry conditions;

  /// Evaluates [expression] and coerces the result to a [bool].
  ///
  /// An expression that cannot be evaluated counts as `false` — and, in a
  /// debug build, says so in the log, so a typo in a Yarn condition does not
  /// pass for a condition that is simply unmet.
  bool evaluateBool(String expression) {
    try {
      final result = _Parser(expression.trim(), variables, conditions).parse();
      return _coerceBool(result);
    } catch (e) {
      _report(expression, e);
      return false;
    }
  }

  /// Evaluates [expression] and returns the raw value (`bool`, `int`,
  /// `double`, or `String`) — `null`, logged in a debug build, when it
  /// cannot be evaluated.
  dynamic evaluate(String expression) {
    try {
      return _Parser(expression.trim(), variables, conditions).parse();
    } catch (e) {
      _report(expression, e);
      return null;
    }
  }

  static void _report(String expression, Object error) {
    if (kDebugMode) {
      debugPrint('Dialogue: could not evaluate "$expression" ($error)');
    }
  }

  static bool _coerceBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is double) return v != 0.0;
    if (v is String) return v.isNotEmpty;
    return v != null;
  }
}

// ---------------------------------------------------------------------------
// Internal recursive-descent parser
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this.src, this.vars, this.conds) : _pos = 0;

  final String src;
  final DialogueVariableStore vars;
  final DialogueConditionRegistry conds;
  int _pos;

  /// The whole of [src]: what is left over after the expression is a
  /// mistake, not something to ignore.
  dynamic parse() {
    final value = _parseXor();
    _skipWs();
    if (_pos < src.length) {
      throw FormatException('unexpected "${src.substring(_pos)}"');
    }
    return value;
  }

  // -- ^ xor --
  dynamic _parseXor() {
    var left = _parseOr();
    while (_match(const ['^'], const ['xor'])) {
      final right = _parseOr();
      left = _bool(left) != _bool(right);
    }
    return left;
  }

  // -- || or --
  dynamic _parseOr() {
    var left = _parseAnd();
    while (_match(const ['||'], const ['or'])) {
      final right = _parseAnd();
      left = _bool(left) || _bool(right);
    }
    return left;
  }

  // -- && and --
  dynamic _parseAnd() {
    var left = _parseEquality();
    while (_match(const ['&&'], const ['and'])) {
      final right = _parseEquality();
      left = _bool(left) && _bool(right);
    }
    return left;
  }

  // -- == != eq is neq --
  dynamic _parseEquality() {
    var left = _parseComparison();
    while (true) {
      if (_match(const ['=='], const ['eq', 'is'])) {
        left = left == _parseComparison();
      } else if (_match(const ['!='], const ['neq'])) {
        left = left != _parseComparison();
      } else {
        return left;
      }
    }
  }

  // -- > >= < <= gt gte lt lte --
  dynamic _parseComparison() {
    var left = _parseAdditive();
    while (true) {
      final String op;
      if (_match(const ['>='], const ['gte'])) {
        op = '>=';
      } else if (_match(const ['<='], const ['lte'])) {
        op = '<=';
      } else if (_match(const ['>'], const ['gt'])) {
        op = '>';
      } else if (_match(const ['<'], const ['lt'])) {
        op = '<';
      } else {
        return left;
      }
      left = _order(left, op, _parseAdditive());
    }
  }

  // -- + - --
  dynamic _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      if (_match(const ['+'])) {
        final right = _parseMultiplicative();
        left = left is String || right is String
            ? '${left ?? ''}${right ?? ''}'
            : _arithmetic(left, '+', right);
      } else if (_match(const ['-'])) {
        left = _arithmetic(left, '-', _parseMultiplicative());
      } else {
        return left;
      }
    }
  }

  // -- * / % --
  dynamic _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      final String op;
      if (_match(const ['*'])) {
        op = '*';
      } else if (_match(const ['/'])) {
        op = '/';
      } else if (_match(const ['%'])) {
        op = '%';
      } else {
        return left;
      }
      left = _arithmetic(left, op, _parseUnary());
    }
  }

  // -- prefix ! not - --
  dynamic _parseUnary() {
    _skipWs();
    if (_pos < src.length && src[_pos] == '!' && !src.startsWith('!=', _pos)) {
      _pos++;
      return !_bool(_parseUnary());
    }
    if (_match(const [], const ['not'])) return !_bool(_parseUnary());
    if (_match(const ['-'])) {
      final value = _parseUnary();
      if (value is num) return -value;
      throw FormatException('"-" needs a number, not $value');
    }
    return _parsePrimary();
  }

  // -- literals, variables, predicates, groups --
  dynamic _parsePrimary() {
    _skipWs();
    if (_pos >= src.length) throw const FormatException('a value is missing');

    final c = src[_pos];

    // Grouping
    if (c == '(') {
      _pos++;
      final result = _parseXor();
      _skipWs();
      if (_pos >= src.length || src[_pos] != ')') {
        throw const FormatException('a "(" is not closed');
      }
      _pos++;
      return result;
    }

    // Yarn variable  $name
    if (c == r'$') {
      _pos++;
      final name = _readIdent();
      if (name.isEmpty) throw const FormatException('a "\$" with no name');
      return vars.getRaw(name);
    }

    // Registered predicate  [name]
    if (c == '[') {
      final close = src.indexOf(']', _pos);
      if (close < 0) throw const FormatException('a "[" is not closed');
      final name = src.substring(_pos + 1, close).trim();
      _pos = close + 1;
      return conds.evaluate(name, vars);
    }

    // String literal  "…"  '…'
    if (c == '"' || c == "'") return _readString(c);

    // Number
    final number = _number.matchAsPrefix(src, _pos);
    if (number != null) {
      _pos = number.end;
      final text = number.group(0)!;
      return text.contains('.') ? double.parse(text) : int.parse(text);
    }

    // Boolean keyword — anything else is not a value.
    final word = _readIdent();
    if (word.isEmpty) {
      throw FormatException('unexpected "${src.substring(_pos)}"');
    }
    final lower = word.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    _skipWs();
    if (_pos < src.length && src[_pos] == '(') {
      throw FormatException('the function "$word" is not supported');
    }
    throw FormatException('"$word" is not a value (a variable needs a "\$")');
  }

  // -- helpers --

  bool _order(dynamic left, String op, dynamic right) {
    if (left is num && right is num) {
      return switch (op) {
        '>' => left > right,
        '>=' => left >= right,
        '<' => left < right,
        '<=' => left <= right,
        _ => false,
      };
    }
    // Ordering anything but numbers — an unset variable, say — is unmet.
    return false;
  }

  num _arithmetic(dynamic left, String op, dynamic right) {
    if (left is! num || right is! num) {
      throw FormatException('"$op" needs numbers, not $left and $right');
    }
    return switch (op) {
      '+' => left + right,
      '-' => left - right,
      '*' => left * right,
      '/' => left / right,
      _ => left % right,
    };
  }

  bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is double) return v != 0.0;
    if (v is String) return v.isNotEmpty;
    return v != null;
  }

  void _skipWs() {
    while (_pos < src.length &&
        (src[_pos] == ' ' ||
            src[_pos] == '\t' ||
            src[_pos] == '\r' ||
            src[_pos] == '\n')) {
      _pos++;
    }
  }

  /// Consumes the first of [symbols], or of the keywords [words] (whole
  /// words, any case), found next; false, consuming nothing, when none is.
  bool _match(List<String> symbols, [List<String> words = const []]) {
    _skipWs();
    for (final s in symbols) {
      if (src.startsWith(s, _pos)) {
        _pos += s.length;
        return true;
      }
    }
    for (final w in words) {
      final end = _pos + w.length;
      if (end > src.length) continue;
      if (src.substring(_pos, end).toLowerCase() != w) continue;
      if (end < src.length && _identChar.hasMatch(src[end])) continue;
      _pos = end;
      return true;
    }
    return false;
  }

  String _readIdent() {
    final start = _pos;
    while (_pos < src.length && _identChar.hasMatch(src[_pos])) {
      _pos++;
    }
    return src.substring(start, _pos);
  }

  String _readString(String quote) {
    _pos++; // the opening quote
    final out = StringBuffer();
    while (_pos < src.length) {
      final ch = src[_pos++];
      if (ch == quote) return out.toString();
      if (ch == r'\' && _pos < src.length) {
        out.write(src[_pos++]);
      } else {
        out.write(ch);
      }
    }
    throw const FormatException('a string is not closed');
  }
}

final RegExp _number = RegExp(r'\d+(?:\.\d+)?|\.\d+');

final RegExp _identChar = RegExp(r'[a-zA-Z0-9_]');
