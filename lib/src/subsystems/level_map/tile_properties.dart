/// Custom properties on tiles, layers, maps and tilesets.
library;

/// The kinds of value a property can hold — Tiled's.
enum TilePropertyType {
  string,
  int,
  float,
  bool,

  /// An ARGB colour, held as an int.
  color,

  /// A path, held as a string.
  file,

  /// Another object's id, held as an int.
  object;

  static TilePropertyType fromName(String? name) => TilePropertyType.values
      .firstWhere((t) => t.name == name, orElse: () => TilePropertyType.string);
}

/// Named, typed values a designer attaches to a tile or a layer and a game
/// reads: a tile's `damage`, a layer's `ambient` sound.
///
/// Kept in the order they were added, and with their declared type, so a
/// property that is a file path or an object reference survives a round
/// trip through a TMX file as one.
class TileProperties {
  TileProperties([Map<String, (TilePropertyType, Object?)>? entries])
    : _entries = {...?entries};

  final Map<String, (TilePropertyType, Object?)> _entries;

  /// No properties.
  static TileProperties empty() => TileProperties();

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;
  Iterable<String> get names => _entries.keys;

  /// The value of [name], or null.
  Object? operator [](String name) => _entries[name]?.$2;

  /// The declared type of [name].
  TilePropertyType? typeOf(String name) => _entries[name]?.$1;

  /// Sets [name], inferring the type from [value] unless [type] is given.
  void set(String name, Object? value, [TilePropertyType? type]) {
    _entries[name] = (type ?? _infer(value), value);
  }

  void remove(String name) => _entries.remove(name);

  String? getString(String name) => this[name]?.toString();
  int? getInt(String name) => switch (this[name]) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };
  double? getDouble(String name) => switch (this[name]) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };
  bool? getBool(String name) => switch (this[name]) {
    final bool v => v,
    final String v => v == 'true',
    _ => null,
  };

  static TilePropertyType _infer(Object? value) => switch (value) {
    bool() => TilePropertyType.bool,
    int() => TilePropertyType.int,
    double() => TilePropertyType.float,
    _ => TilePropertyType.string,
  };

  /// As saved: a list of `{name, type, value}`, Tiled's own JSON shape.
  /// Empty properties save as an empty list.
  List<Map<String, dynamic>> toJson() => [
    for (final e in _entries.entries)
      {'name': e.key, 'type': e.value.$1.name, 'value': e.value.$2},
  ];

  /// Reads what [toJson] wrote; anything else is no properties.
  static TileProperties fromJson(Object? json) {
    final out = TileProperties();
    if (json is! List) return out;
    for (final raw in json) {
      if (raw is! Map) continue;
      final name = raw['name'];
      if (name is! String) continue;
      final type = TilePropertyType.fromName(raw['type'] as String?);
      final value = raw['value'];
      out._entries[name] = (
        type,
        switch (type) {
          TilePropertyType.int ||
          TilePropertyType.object ||
          TilePropertyType.color => (value as num?)?.toInt() ?? 0,
          TilePropertyType.float => (value as num?)?.toDouble() ?? 0.0,
          TilePropertyType.bool => value == true,
          _ => value?.toString() ?? '',
        },
      );
    }
    return out;
  }

  /// A separate copy.
  TileProperties copy() => TileProperties(_entries);

  @override
  bool operator ==(Object other) {
    if (other is! TileProperties || other._entries.length != _entries.length) {
      return false;
    }
    for (final e in _entries.entries) {
      if (other._entries[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _entries.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
