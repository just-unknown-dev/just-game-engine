/// Runtime storage for Yarn Spinner dialogue variables.
library;

/// Stores named dialogue variables used by `<<set>>` and `<<if>>` statements.
///
/// Variable names are case-insensitive and the leading `$` is stripped
/// automatically, so `$gold` and `gold` refer to the same entry.
///
/// Supported value types: `bool`, `int`, `double`, `String`.
///
/// ```dart
/// final store = DialogueVariableStore();
/// store.set('questAccepted', true);
/// store.set('gold', 42);
///
/// print(store.get<bool>('questAccepted')); // true
/// print(store.getOrDefault<int>('gold', 0)); // 42
/// ```
class DialogueVariableStore {
  final Map<String, dynamic> _vars = {};

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the value of [name] cast to [T], or `null` if absent / wrong type.
  T? get<T>(String name) {
    final v = _vars[_normalize(name)];
    if (v is T) return v;
    return null;
  }

  /// Returns the value of [name] cast to [T], or [defaultValue] if absent.
  T getOrDefault<T>(String name, T defaultValue) =>
      get<T>(name) ?? defaultValue;

  /// Returns the raw value without casting.
  dynamic getRaw(String name) => _vars[_normalize(name)];

  /// Returns `true` if [name] is defined.
  bool has(String name) => _vars.containsKey(_normalize(name));

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Stores [value] under [name].
  ///
  /// Only `bool`, `int`, `double`, and `String` are valid Yarn variable types.
  void set(String name, dynamic value) {
    assert(
      value is bool || value is int || value is double || value is String,
      'Dialogue variables must be bool, int, double, or String. '
      'Got ${value.runtimeType} for "\$$name".',
    );
    _vars[_normalize(name)] = value;
  }

  /// Removes [name] from the store.
  void unset(String name) => _vars.remove(_normalize(name));

  /// Removes all variables.
  void clear() => _vars.clear();

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  /// Variable names (without `$` prefix) currently in the store.
  Iterable<String> get names => _vars.keys;

  /// Returns a copy of the internal map suitable for JSON serialization.
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_vars);

  /// Restores state from a previously serialized [map].
  void loadFromMap(Map<String, dynamic> map) {
    _vars
      ..clear()
      ..addAll(map);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Strips a leading `$` and lower-cases the name for consistent lookup.
  static String _normalize(String name) {
    final stripped = name.startsWith(r'$') ? name.substring(1) : name;
    return stripped.toLowerCase();
  }
}
