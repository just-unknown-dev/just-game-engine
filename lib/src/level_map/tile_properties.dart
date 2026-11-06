/// Custom properties on tiles, layers, maps and tilesets.
library;

/// The kinds of value a property can hold — Tiled's.
enum TilePropertyType {
  /// Text.
  string,

  /// A whole number.
  int,

  /// A number that may have a fraction, held as a double.
  float,

  /// True or false.
  bool,

  /// An ARGB colour, held as an int.
  color,

  /// A path, held as a string.
  file,

  /// Another object's id, held as an int.
  object;

  /// The type Tiled and the saved form call [name] (`string`, `int`,
  /// `float`, `bool`, `color`, `file`, `object`); [string] for null or a
  /// name it does not know.
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
  /// Properties holding [entries] — name to (type, value) — in their order;
  /// none when null. The map is copied, so later changes to it do not
  /// reach these.
  TileProperties([Map<String, (TilePropertyType, Object?)>? entries])
    : _entries = {...?entries};

  final Map<String, (TilePropertyType, Object?)> _entries;

  /// Whether there are no properties.
  bool get isEmpty => _entries.isEmpty;

  /// Whether there is at least one property.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// The properties' names, in the order they were added.
  Iterable<String> get names => _entries.keys;

  /// The value of [name], or null.
  Object? operator [](String name) => _entries[name]?.$2;

  /// The declared type of [name].
  TilePropertyType? typeOf(String name) => _entries[name]?.$1;

  /// Sets [name] to [value] of [type].
  ///
  /// Without a [type], a property that has one keeps it while [value] fits
  /// it — a `float` stays a float when set to 2, a `file` stays a file when
  /// set to a string — and a new one is typed by [value]. Pass the type
  /// whenever it is known: on the web 2.0 and 2 are the same number, so a
  /// new whole-number float can only be told from an int by saying so.
  void set(String name, Object? value, [TilePropertyType? type]) {
    final t = type ?? _keep(_entries[name]?.$1, value) ?? _infer(value);
    _entries[name] = (t, _as(t, value));
  }

  static bool _whole(num v) => v.isFinite && v == v.truncateToDouble();

  /// [value] held as [type] holds it: a float as a double, a whole number
  /// of the int kinds as an int.
  static Object? _as(TilePropertyType type, Object? value) => switch (type) {
    TilePropertyType.float when value is num => value.toDouble(),
    TilePropertyType.int ||
    TilePropertyType.object ||
    TilePropertyType.color when value is num && _whole(value) => value.toInt(),
    _ => value,
  };

  /// [previous] if [value] can be one; null when it cannot.
  static TilePropertyType? _keep(TilePropertyType? previous, Object? value) =>
      switch (previous) {
        null => null,
        TilePropertyType.float => value is num ? previous : null,
        TilePropertyType.int ||
        TilePropertyType.object ||
        TilePropertyType.color =>
          value is num && _whole(value) ? previous : null,
        TilePropertyType.bool => value is bool ? previous : null,
        TilePropertyType.string ||
        TilePropertyType.file => value is String ? previous : null,
      };

  /// Removes [name], value and type; nothing happens when there is none.
  void remove(String name) => _entries.remove(name);

  /// [name]'s value as text (whatever it holds, through `toString`); null
  /// when there is no such property or its value is null.
  String? getString(String name) => this[name]?.toString();

  /// [name]'s value as an int: an int as it is, any other number truncated,
  /// a string parsed. Null when absent, unparseable or of another kind.
  int? getInt(String name) => switch (this[name]) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };

  /// [name]'s value as a double: any number, or a string parsed. Null when
  /// absent, unparseable or of another kind.
  double? getDouble(String name) => switch (this[name]) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };

  /// [name]'s value as a bool: a bool as it is, a string true only when it
  /// is exactly `true`. Null when absent or of another kind.
  bool? getBool(String name) => switch (this[name]) {
    final bool v => v,
    final String v => v == 'true',
    _ => null,
  };

  /// The type a new property's [value] says. A fraction is a float; a
  /// whole number an int — and on the web every whole number, 2.0 too.
  static TilePropertyType _infer(Object? value) => switch (value) {
    bool() => TilePropertyType.bool,
    double() when !_whole(value) => TilePropertyType.float,
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
