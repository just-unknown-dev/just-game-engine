/// Simple recursive-descent evaluator for Yarn Spinner condition expressions.
library;

import '../core/dialogue_variable_store.dart';
import 'dialogue_condition_registry.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Evaluates Yarn Spinner condition and assignment expressions at runtime.
///
/// **Supported syntax**
/// * Literals: `true`, `false`, integers, floats, `"strings"`, `'strings'`
/// * Variables: `$varName` — read from [DialogueVariableStore]
/// * Registered predicates: `[predicateName]` — see [DialogueConditionRegistry]
/// * Comparisons: `==`, `!=`, `>`, `>=`, `<`, `<=`
/// * Logical: `&&`, `||`, prefix `!`
/// * Grouping: `( … )`
///
/// ```dart
/// final eval = ExpressionEvaluator(variables: vars, conditions: registry);
///
/// eval.evaluateBool(r'$questDone == true && $gold >= 10');
/// eval.evaluateBool('[playerHasKey]');
/// eval.evaluate(r'$gold + 5');   // arithmetic not supported — returns raw
/// ```
class ExpressionEvaluator {
  ExpressionEvaluator({required this.variables, required this.conditions});

  final DialogueVariableStore variables;
  final DialogueConditionRegistry conditions;

  /// Evaluates [expression] and coerces the result to a [bool].
  bool evaluateBool(String expression) {
    try {
      final result = _Parser(expression.trim(), variables, conditions).parse();
      return _coerceBool(result);
    } catch (_) {
      return false;
    }
  }

  /// Evaluates [expression] and returns the raw value (`bool`, `int`,
  /// `double`, or `String`).
  dynamic evaluate(String expression) {
    try {
      return _Parser(expression.trim(), variables, conditions).parse();
    } catch (_) {
      return null;
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

  dynamic parse() => _parseOr();

  // -- || --
  dynamic _parseOr() {
    var left = _parseAnd();
    while (_peek('||')) {
      _consume('||');
      final right = _parseAnd();
      left = _bool(left) || _bool(right);
    }
    return left;
  }

  // -- && --
  dynamic _parseAnd() {
    var left = _parseNot();
    while (_peek('&&')) {
      _consume('&&');
      final right = _parseNot();
      left = _bool(left) && _bool(right);
    }
    return left;
  }

  // -- prefix ! --
  dynamic _parseNot() {
    _skipWs();
    if (_pos < src.length && src[_pos] == '!') {
      _pos++;
      return !_bool(_parseComparison());
    }
    return _parseComparison();
  }

  // -- ==  !=  >  >=  <  <= --
  dynamic _parseComparison() {
    final left = _parsePrimary();
    _skipWs();
    if (_pos >= src.length) return left;

    String? op;
    if (_peek('==')) {
      op = '==';
      _consume('==');
    } else if (_peek('!=')) {
      op = '!=';
      _consume('!=');
    } else if (_peek('>=')) {
      op = '>=';
      _consume('>=');
    } else if (_peek('<=')) {
      op = '<=';
      _consume('<=');
    } else if (_peek('>')) {
      op = '>';
      _consume('>');
    } else if (_peek('<')) {
      op = '<';
      _consume('<');
    }

    if (op == null) return left;
    final right = _parsePrimary();
    return _compare(left, op, right);
  }

  // -- literals, variables, predicates, groups --
  dynamic _parsePrimary() {
    _skipWs();
    if (_pos >= src.length) return false;

    final c = src[_pos];

    // Grouping
    if (c == '(') {
      _pos++;
      final result = _parseOr();
      _skipWs();
      if (_pos < src.length && src[_pos] == ')') _pos++;
      return result;
    }

    // Yarn variable  $name
    if (c == r'$') {
      _pos++;
      final name = _readIdent();
      return vars.getRaw(name);
    }

    // Registered predicate  [name]
    if (c == '[') {
      _pos++;
      final name = _readUntil(']');
      if (_pos < src.length) _pos++; // consume ']'
      return conds.evaluate(name.trim(), vars);
    }

    // String literal  "…"  '…'
    if (c == '"' || c == "'") {
      _pos++;
      final s = _readUntil(c);
      if (_pos < src.length) _pos++; // consume closing quote
      return s;
    }

    // Number / boolean keyword / fallback
    final word = _readWord();
    if (word.toLowerCase() == 'true') return true;
    if (word.toLowerCase() == 'false') return false;
    if (word.contains('.')) {
      final d = double.tryParse(word);
      if (d != null) return d;
    }
    final i = int.tryParse(word);
    if (i != null) return i;
    return word; // unknown identifier returned as-is
  }

  // -- helpers --

  bool _compare(dynamic left, String op, dynamic right) {
    if (left is num && right is num) {
      return switch (op) {
        '==' => left == right,
        '!=' => left != right,
        '>' => left > right,
        '>=' => left >= right,
        '<' => left < right,
        '<=' => left <= right,
        _ => false,
      };
    }
    return switch (op) {
      '==' => left == right,
      '!=' => left != right,
      _ => false,
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
    while (_pos < src.length && (src[_pos] == ' ' || src[_pos] == '\t')) {
      _pos++;
    }
  }

  bool _peek(String s) {
    _skipWs();
    return src.startsWith(s, _pos);
  }

  void _consume(String s) {
    _skipWs();
    if (src.startsWith(s, _pos)) _pos += s.length;
  }

  String _readIdent() {
    final start = _pos;
    while (_pos < src.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(src[_pos])) {
      _pos++;
    }
    return src.substring(start, _pos);
  }

  String _readWord() {
    _skipWs();
    final start = _pos;
    while (_pos < src.length) {
      final ch = src[_pos];
      if (ch == ' ' ||
          ch == '\t' ||
          ch == '(' ||
          ch == ')' ||
          ch == '&' ||
          ch == '|' ||
          ch == '!' ||
          ch == '=' ||
          ch == '<' ||
          ch == '>') {
        break;
      }
      _pos++;
    }
    return src.substring(start, _pos);
  }

  String _readUntil(String terminator) {
    final start = _pos;
    while (_pos < src.length && !src.startsWith(terminator, _pos)) {
      _pos++;
    }
    return src.substring(start, _pos);
  }
}
