/// Registry for named Dart condition predicates used in Yarn dialogue.
library;

import '../core/dialogue_variable_store.dart';

/// A Dart function used as a named dialogue condition in Yarn `<<if>>` blocks.
///
/// Receives the current [DialogueVariableStore] so it can read any previously
/// set Yarn variables alongside your own game state.
///
/// ```dart
/// bool Function(DialogueVariableStore) predicate = (vars) {
///   return player.hasItem('key') && vars.getOrDefault('door_unlocked', false);
/// };
/// ```
typedef DialoguePredicate = bool Function(DialogueVariableStore variables);

/// Registry for named [DialoguePredicate]s.
///
/// Register predicates under a string name on startup, then reference them
/// in Yarn source using the `[name]` syntax inside `<<if>>` expressions:
///
/// ```yarn
/// <<if [playerHasKey]>>
///     Guard: Go right ahead.
/// <<endif>>
/// ```
///
/// ```dart
/// manager.conditions.register('playerHasKey', (vars) => player.hasKey);
/// ```
class DialogueConditionRegistry {
  final Map<String, DialoguePredicate> _predicates = {};

  /// Registers a named [predicate].
  ///
  /// Overwrites any existing registration with the same [name].
  void register(String name, DialoguePredicate predicate) {
    _predicates[name] = predicate;
  }

  /// Evaluates the predicate registered under [name].
  ///
  /// Returns `false` silently if [name] is not registered — treat missing
  /// predicates as unsatisfied conditions.
  bool evaluate(String name, DialogueVariableStore variables) =>
      _predicates[name]?.call(variables) ?? false;

  /// Returns `true` if a predicate with [name] is registered.
  bool has(String name) => _predicates.containsKey(name);

  /// Removes the predicate registered under [name].
  void unregister(String name) => _predicates.remove(name);

  /// Removes all registered predicates.
  void clear() => _predicates.clear();
}
