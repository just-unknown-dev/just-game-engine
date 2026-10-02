/// The project's collision layers, and the file they are kept in.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

import '../../ecs/ecs.dart' show TagNames;
import '../../foundation/unsupported_format_version.dart';

/// What collides with what, by layer: up to [count] layers, each with a
/// name, and a grid saying which pairs of them collide.
///
/// A `PhysicsBodyComponent` is on one layer (`layer`, 0 by default). Two
/// bodies collide when the grid says their layers do, unless a body names
/// the layers it collides with itself (`collidesWith`). Layer 0 is called
/// `Default`; until a project names more, everything is on it and
/// everything collides, as before layers existed.
///
/// A layer is in use once it has a name; an editor also keeps a colour and
/// a description for each. Bodies refer to a layer by its number, so a
/// rename changes nothing else.
///
/// Kept in [defaultPath], which the engine reads as it initializes when the
/// app bundles it, and an editor writes. Immutable: every change returns a
/// new set.
@immutable
final class PhysicsLayers {
  /// Layers named [names] (index 0 first; missing or blank entries are
  /// unnamed), colliding as [masks] say: bit `b` of `masks[a]` is set when
  /// layer `a` collides with layer `b`. Missing masks collide with
  /// everything. A pair collides only if both of its masks say so, so the
  /// grid is symmetric however it was given. [colors] and [descriptions]
  /// are how an editor shows each; missing ones are none.
  factory PhysicsLayers({
    List<String> names = const [],
    List<int> masks = const [],
    List<Color?> colors = const [],
    List<String> descriptions = const [],
  }) {
    final n = List<String>.generate(
      count,
      (i) => i < names.length ? names[i].trim() : '',
    );
    if (n[0].isEmpty) n[0] = defaultName;
    final m = List<int>.generate(
      count,
      (i) => i < masks.length ? masks[i] & all : all,
    );
    for (var a = 0; a < count; a++) {
      for (var b = a + 1; b < count; b++) {
        final both = _bit(m[a], b) && _bit(m[b], a);
        m[a] = _set(m[a], b, both);
        m[b] = _set(m[b], a, both);
      }
    }
    return PhysicsLayers._(
      List.unmodifiable(n),
      List.unmodifiable(m),
      List.unmodifiable(
        List<Color?>.generate(
          count,
          (i) => i < colors.length ? colors[i] : null,
        ),
      ),
      List.unmodifiable(
        List<String>.generate(
          count,
          (i) => i < descriptions.length ? descriptions[i].trim() : '',
        ),
      ),
    );
  }

  const PhysicsLayers._(
    this.names,
    this._masks,
    this._colors,
    this._descriptions,
  );

  /// How many layers there are: one per bit of a collision filter.
  static const int count = 16;

  /// Every layer, as a mask.
  static const int all = 0xFFFF;

  /// Layer 0's name until it is given another.
  static const String defaultName = 'Default';

  /// The longest name a layer may have.
  static const int maxNameLength = 24;

  /// The file format [toJson] writes; [fromJson] refuses newer ones.
  static const int formatVersion = 1;

  /// Where a project keeps its layers.
  static const String defaultPath = 'assets/project/physics.json';

  /// Layer 0 called `Default`, nothing else named, everything colliding.
  static final PhysicsLayers defaults = PhysicsLayers();

  /// Each layer's name, [count] of them; unnamed ones are empty.
  final List<String> names;

  final List<int> _masks;
  final List<Color?> _colors;
  final List<String> _descriptions;

  static bool _bit(int mask, int b) => (mask >> b) & 1 == 1;
  static int _set(int mask, int b, bool on) =>
      on ? mask | (1 << b) : mask & ~(1 << b);

  /// Whether [layer] is a layer number, 0 to [count] − 1.
  static bool isValid(int layer) => layer >= 0 && layer < count;

  /// [layer] brought into range.
  static int clampLayer(int layer) => layer.clamp(0, count - 1);

  /// The colour a layer is shown in when it has none of its own: one of
  /// sixteen, by number.
  static Color defaultColorOf(int layer) =>
      _palette[clampLayer(layer) % _palette.length];

  static const List<Color> _palette = [
    Color(0xFF90A4AE),
    Color(0xFF64B5F6),
    Color(0xFF81C784),
    Color(0xFFFFB74D),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFFFF176),
    Color(0xFFA1887F),
    Color(0xFFF06292),
    Color(0xFF7986CB),
    Color(0xFFAED581),
    Color(0xFFFF8A65),
    Color(0xFF4DB6AC),
    Color(0xFFDCE775),
    Color(0xFF9575CD),
  ];

  /// [layer]'s name; empty when it has none.
  String nameOf(int layer) => isValid(layer) ? names[layer] : '';

  /// Whether [layer] is in use: it has a name.
  bool isNamed(int layer) => nameOf(layer).isNotEmpty;

  /// What to call [layer] where something must be shown: its name, else
  /// `Layer n`.
  String labelOf(int layer) {
    final name = nameOf(layer);
    return name.isEmpty ? 'Layer $layer' : name;
  }

  /// [layer]'s colour: its own, else [defaultColorOf].
  Color colorOf(int layer) =>
      (isValid(layer) ? _colors[layer] : null) ?? defaultColorOf(layer);

  /// [layer]'s own colour, or null when it uses [defaultColorOf].
  Color? ownColorOf(int layer) => isValid(layer) ? _colors[layer] : null;

  /// What [layer] is for; empty for nothing.
  String descriptionOf(int layer) => isValid(layer) ? _descriptions[layer] : '';

  /// The number of the layer called [name] (case aside), or null.
  int? indexOf(String name) {
    final want = name.trim().toLowerCase();
    for (var i = 0; i < count; i++) {
      if (names[i].isNotEmpty && names[i].toLowerCase() == want) return i;
    }
    return null;
  }

  /// The layers that have a name, in order.
  Iterable<int> get named sync* {
    for (var i = 0; i < count; i++) {
      if (names[i].isNotEmpty) yield i;
    }
  }

  /// The first layer with no name — where a new one goes — or null when all
  /// [count] are in use.
  int? get firstFree {
    for (var i = 1; i < count; i++) {
      if (names[i].isEmpty) return i;
    }
    return null;
  }

  /// Why [name] cannot be a layer's name — [except] being the layer it
  /// would rename — or null when it can. Names are free text, but must be
  /// there, short, and not another layer's with only case, a plural `s` or
  /// `_` against `-` apart.
  String? problemWithName(String name, {int? except}) {
    final n = name.trim();
    if (n.isEmpty) return 'A layer needs a name.';
    if (n.length > maxNameLength) {
      return 'Keep it to $maxNameLength characters.';
    }
    for (final i in named) {
      if (i == except) continue;
      final other = names[i];
      if (other.toLowerCase() == n.toLowerCase()) {
        return 'There is already a "$other".';
      }
      if (TagNames.areNearDuplicates(n, other)) {
        return 'Too close to "$other" to tell apart.';
      }
    }
    return null;
  }

  /// The layers [layer] collides with, as a mask.
  int maskOf(int layer) => _masks[clampLayer(layer)];

  /// Whether bodies on layers [a] and [b] collide.
  bool collides(int a, int b) => _bit(maskOf(a), clampLayer(b));

  PhysicsLayers _copy({
    List<String>? names,
    List<int>? masks,
    List<Color?>? colors,
    List<String>? descriptions,
  }) => PhysicsLayers(
    names: names ?? this.names,
    masks: masks ?? _masks,
    colors: colors ?? _colors,
    descriptions: descriptions ?? _descriptions,
  );

  static List<T> _with<T>(List<T> list, int i, T value) => [
    for (var k = 0; k < list.length; k++) k == i ? value : list[k],
  ];

  /// A copy with [layer] called [name] (trimmed; empty unnames it — except
  /// layer 0, which goes back to [defaultName]).
  PhysicsLayers withName(int layer, String name) =>
      !isValid(layer) ? this : _copy(names: _with(names, layer, name));

  /// A copy with [layer] shown in [color]; null for its default.
  PhysicsLayers withColor(int layer, Color? color) =>
      !isValid(layer) ? this : _copy(colors: _with(_colors, layer, color));

  /// A copy with [layer] described as [description].
  PhysicsLayers withDescription(int layer, String description) =>
      !isValid(layer)
      ? this
      : _copy(descriptions: _with(_descriptions, layer, description));

  /// A copy with [layer] out of use: no name, colour or description, and
  /// colliding with everything again — how a layer made there later
  /// starts. Layer 0 is only given its default name back.
  PhysicsLayers cleared(int layer) {
    if (!isValid(layer)) return this;
    if (layer == 0) return withName(0, '');
    final m = [..._masks];
    m[layer] = all;
    for (var b = 0; b < count; b++) {
      m[b] = _set(m[b], layer, true);
    }
    return _copy(
      names: _with(names, layer, ''),
      masks: m,
      colors: _with(_colors, layer, null),
      descriptions: _with(_descriptions, layer, ''),
    );
  }

  /// A copy where layers [a] and [b] collide or not, both ways.
  PhysicsLayers withCollision(int a, int b, bool collide) {
    if (!isValid(a) || !isValid(b)) return this;
    final m = [..._masks];
    m[a] = _set(m[a], b, collide);
    m[b] = _set(m[b], a, collide);
    return _copy(masks: m);
  }

  /// What the project file keeps: the version, then each layer that has a
  /// name, a colour, a description or ignores another — by number, which a
  /// rename leaves alone.
  Map<String, dynamic> toJson() => {
    'version': formatVersion,
    'layers': [
      for (var i = 0; i < count; i++)
        if (names[i].isNotEmpty ||
            _masks[i] != all ||
            _colors[i] != null ||
            _descriptions[i].isNotEmpty)
          {
            'index': i,
            if (names[i].isNotEmpty) 'name': names[i],
            if (_colors[i] case final c?) 'color': c.toARGB32(),
            if (_descriptions[i].isNotEmpty) 'description': _descriptions[i],
            if (_masks[i] != all)
              'ignores': [
                for (var b = 0; b < count; b++)
                  if (!_bit(_masks[i], b)) b,
              ],
          },
    ],
  };

  /// Reads what [toJson] wrote. Throws [UnsupportedFormatVersionException]
  /// for a file from a newer engine, and [FormatException] for one that is
  /// not an object.
  static PhysicsLayers fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('The physics layers file is not an object.');
    }
    final version = (json['version'] as num?)?.toInt() ?? formatVersion;
    if (version > formatVersion) {
      throw UnsupportedFormatVersionException(
        'physics layers',
        version,
        formatVersion,
      );
    }
    final names = List<String>.filled(count, '');
    final masks = List<int>.filled(count, all);
    final colors = List<Color?>.filled(count, null);
    final descriptions = List<String>.filled(count, '');
    final layers = json['layers'];
    if (layers is List) {
      for (final entry in layers.whereType<Map>()) {
        final i = (entry['index'] as num?)?.toInt();
        if (i == null || !isValid(i)) continue;
        if (entry['name'] case final String name) names[i] = name;
        if (entry['color'] case final int color) colors[i] = Color(color);
        if (entry['description'] case final String text) {
          descriptions[i] = text;
        }
        if (entry['ignores'] case final List ignores) {
          for (final b in ignores.whereType<num>()) {
            if (isValid(b.toInt())) masks[i] = _set(masks[i], b.toInt(), false);
          }
        }
      }
    }
    return PhysicsLayers(
      names: names,
      masks: masks,
      colors: colors,
      descriptions: descriptions,
    );
  }

  /// Whether [other] collides the same — names, colours and descriptions
  /// aside. What a running game cares about.
  bool sameGrid(PhysicsLayers other) => _listEquals(other._masks, _masks);

  @override
  bool operator ==(Object other) =>
      other is PhysicsLayers &&
      _listEquals(other.names, names) &&
      _listEquals(other._masks, _masks) &&
      _listEquals(other._colors, _colors) &&
      _listEquals(other._descriptions, _descriptions);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(names),
    Object.hashAll(_masks),
    Object.hashAll(_colors),
    Object.hashAll(_descriptions),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'PhysicsLayers(${[for (final i in named) '$i: ${names[i]}'].join(', ')})';
}
