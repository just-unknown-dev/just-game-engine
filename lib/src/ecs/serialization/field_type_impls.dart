library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';

import '../components/components.dart';
import 'field_type.dart';

double _toDouble(Object? v) => v is num ? v.toDouble() : 0.0;

class BooleanFieldType extends FieldType<bool> {
  const BooleanFieldType();
  @override
  String get id => 'boolean';
  @override
  Object? encode(bool value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

class IntegerFieldType extends FieldType<int> {
  const IntegerFieldType();
  @override
  String get id => 'integer';
  @override
  Object? encode(int value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! num) return json;
    var v = json.toInt();
    if (c.min != null) v = math.max(v, c.min!.ceil());
    if (c.max != null) v = math.min(v, c.max!.floor());
    return v;
  }
}

class DecimalFieldType extends FieldType<double> {
  const DecimalFieldType();
  @override
  String get id => 'decimal';
  @override
  Object? encode(double value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! num) return json;
    var v = json.toDouble();
    if (c.min != null) v = math.max(v, c.min!);
    if (c.max != null) v = math.min(v, c.max!);
    return v;
  }
}

class TextFieldType extends FieldType<String> {
  const TextFieldType();
  @override
  String get id => 'text';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// A path into the asset bundle. Stored as text; the editor offers a picker.
class AssetRefFieldType extends FieldType<String> {
  const AssetRefFieldType();
  @override
  String get id => 'assetRef';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// The name of another entity. Stored as text: an entity is referred to by
/// what the author called it, which survives a reload and a respawn where an
/// id would not.
class EntityRefFieldType extends FieldType<String> {
  const EntityRefFieldType();
  @override
  String get id => 'entityRef';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// An enum stored by name and parsed back with [FieldConstraints.enumParser].
class EnumerationFieldType extends FieldType<Object> {
  const EnumerationFieldType();
  @override
  String get id => 'enumeration';
  @override
  Object? encode(Object value) => value.toString().split('.').last;
  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! String) return json;
    final parser = c.enumParser;
    return parser != null ? parser(json) : json;
  }
}

/// An enum that knows its own values, so it needs no parser and the editor
/// can list its options without being told them separately.
class EnumFieldType<E extends Enum> extends FieldType<E> {
  const EnumFieldType(this.values, {this.fallback, String? id})
    : _id = id ?? 'enum';

  /// The enum's values, in declaration order.
  final List<E> values;

  /// What an unknown stored name decodes to; the first value when unset.
  final E? fallback;

  final String _id;

  @override
  String get id => _id;

  /// The stored names, for an inspector dropdown.
  List<String> get names => [for (final v in values) v.name];

  @override
  Object? encode(E value) => value.name;

  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! String) return json;
    for (final v in values) {
      if (v.name == json) return v;
    }
    return fallback ?? values.first;
  }
}

class ListFieldType extends FieldType<List<Object?>> {
  const ListFieldType();
  @override
  String get id => 'list';
  @override
  Object? encode(List<Object?> value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// Space around something: `{l, t, r, b}`.
class EdgeInsetsFieldType extends FieldType<EdgeInsets> {
  const EdgeInsetsFieldType();
  @override
  String get id => 'edgeInsets';
  @override
  Object? encode(EdgeInsets value) => {
    'l': value.left,
    't': value.top,
    'r': value.right,
    'b': value.bottom,
  };
  @override
  Object? decode(Object? json, FieldConstraints c) => json is Map
      ? EdgeInsets.fromLTRB(
          _toDouble(json['l']),
          _toDouble(json['t']),
          _toDouble(json['r']),
          _toDouble(json['b']),
        )
      : json;
}

class MapFieldType extends FieldType<Map<Object?, Object?>> {
  const MapFieldType();
  @override
  String get id => 'map';
  @override
  Object? encode(Map<Object?, Object?> value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

class Vector2FieldType extends FieldType<Vector2> {
  const Vector2FieldType();
  @override
  String get id => 'vector2';
  @override
  List<String> get channels => const ['x', 'y'];
  @override
  Object? encode(Vector2 value) => {'x': value.x, 'y': value.y};
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is Map ? Vector2(_toDouble(json['x']), _toDouble(json['y'])) : json;
}

class Vector3FieldType extends FieldType<Vector3> {
  const Vector3FieldType();
  @override
  String get id => 'vector3';
  @override
  List<String> get channels => const ['x', 'y', 'z'];

  /// A 2-D scene shows x and y; z (depth) keeps its value.
  @override
  Set<String> get channels2D => const {'x', 'y'};
  @override
  Object? encode(Vector3 value) => {'x': value.x, 'y': value.y, 'z': value.z};
  @override
  Object? decode(Object? json, FieldConstraints c) => json is Map
      ? Vector3(
          _toDouble(json['x']),
          _toDouble(json['y']),
          _toDouble(json['z']),
        )
      : json;
}

/// A rotation as three Euler angles in radians, `{x, y, z}` — the engine's
/// one convention, `q = qY · qX · qZ` (see `Quaternion`). The value is a
/// [Vector3] of angles. A 2-D scene shows only z, the angle in the plane.
///
/// A plain number reads as a turn about Z, which is what a rotation was
/// before it had three angles.
class EulerFieldType extends FieldType<Vector3> {
  const EulerFieldType();
  @override
  String get id => 'euler';
  @override
  List<String> get channels => const ['x', 'y', 'z'];
  @override
  Set<String> get channels2D => const {'z'};
  @override
  Object? encode(Vector3 value) => {'x': value.x, 'y': value.y, 'z': value.z};
  @override
  Object? decode(Object? json, FieldConstraints c) => switch (json) {
    Map() => Vector3(
      _toDouble(json['x']),
      _toDouble(json['y']),
      _toDouble(json['z']),
    ),
    num() => Vector3(0, 0, json.toDouble()),
    _ => json,
  };
}

class ColorFieldType extends FieldType<Color> {
  const ColorFieldType();
  @override
  String get id => 'color';
  @override
  Object? encode(Color value) => value.toARGB32();
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is int ? Color(json) : json;
}

class OffsetFieldType extends FieldType<Offset> {
  const OffsetFieldType();
  @override
  String get id => 'offset';
  @override
  List<String> get channels => const ['dx', 'dy'];
  @override
  Object? encode(Offset value) => {'dx': value.dx, 'dy': value.dy};
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is Map ? Offset(_toDouble(json['dx']), _toDouble(json['dy'])) : json;
}

class OffsetListFieldType extends FieldType<List<Offset>> {
  const OffsetListFieldType();
  @override
  String get id => 'offsetList';
  @override
  Object? encode(List<Offset> value) => [
    for (final o in value) {'dx': o.dx, 'dy': o.dy},
  ];
  @override
  Object? decode(Object? json, FieldConstraints c) => json is List
      ? [
          for (final m in json.whereType<Map>())
            Offset(_toDouble(m['dx']), _toDouble(m['dy'])),
        ]
      : json;
}

/// Raw JSON, kept exactly as found.
class UnknownFieldType extends FieldType<Object> {
  const UnknownFieldType();
  @override
  String get id => 'unknown';
  @override
  Object? encode(Object value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// A [ShapePaintStyle]: colour, blend mode and optional gradient.
///
/// Writes the richer of the two shapes the engine has used (`begin`/`end`/
/// `center` as `{x, y}` maps, `tileMode` by name, plus `blendMode`) and reads
/// both — older schema-backed saves stored `beginX`/`beginY` and the tile
/// mode's index.
class ShapePaintStyleFieldType extends FieldType<ShapePaintStyle> {
  const ShapePaintStyleFieldType();

  @override
  String get id => 'shapePaintStyle';

  @override
  Object? encode(ShapePaintStyle value) => {
    'color': value.color.toARGB32(),
    'blendMode': value.blendMode.name,
    if (value.gradient != null) 'gradient': _gradientToJson(value.gradient!),
  };

  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! Map) return json;
    return decodeStyle(json, fallbackColor: const Color(0xFFFFFFFF));
  }

  /// [decode] with an explicit colour for a missing or malformed value.
  static ShapePaintStyle decodeStyle(
    Object? raw, {
    required Color fallbackColor,
  }) {
    if (raw is! Map) return ShapePaintStyle(color: fallbackColor);
    final colorRaw = raw['color'];
    final color = colorRaw is int ? Color(colorRaw) : fallbackColor;
    final blendName = raw['blendMode'];
    final blend = BlendMode.values.firstWhere(
      (m) => m.name == blendName,
      orElse: () => BlendMode.modulate,
    );
    return ShapePaintStyle(
      color: color,
      gradient: _gradientFromJson(raw['gradient']),
      blendMode: blend,
    );
  }

  static Map<String, dynamic> _gradientToJson(ShapeGradient g) => {
    'kind': g.kind.name,
    'colors': [for (final c in g.colors) c.toARGB32()],
    if (g.stops != null) 'stops': g.stops,
    'begin': _alignmentToJson(g.begin),
    'end': _alignmentToJson(g.end),
    'center': _alignmentToJson(g.center),
    'radius': g.radius,
    'startAngle': g.startAngle,
    'endAngle': g.endAngle,
    'tileMode': g.tileMode.name,
  };

  static ShapeGradient? _gradientFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = ShapeGradientKind.values.firstWhere(
      (k) => k.name == raw['kind'],
      orElse: () => ShapeGradientKind.linear,
    );
    final colorsRaw = raw['colors'];
    final colors = colorsRaw is List
        ? [for (final e in colorsRaw.whereType<num>()) Color(e.toInt())]
        : <Color>[];
    if (colors.isEmpty) return null;
    final stopsRaw = raw['stops'];
    final stops = stopsRaw is List
        ? [for (final e in stopsRaw.whereType<num>()) e.toDouble()]
        : null;
    final tileRaw = raw['tileMode'];
    final tileMode = tileRaw is num
        ? TileMode.values[tileRaw.toInt().clamp(0, TileMode.values.length - 1)]
        : TileMode.values.firstWhere(
            (m) => m.name == tileRaw,
            orElse: () => TileMode.clamp,
          );
    switch (kind) {
      case ShapeGradientKind.linear:
        return ShapeGradient.linear(
          colors: colors,
          stops: stops,
          begin: _alignment(raw, 'begin', Alignment.centerLeft),
          end: _alignment(raw, 'end', Alignment.centerRight),
          tileMode: tileMode,
        );
      case ShapeGradientKind.radial:
        return ShapeGradient.radial(
          colors: colors,
          stops: stops,
          center: _alignment(raw, 'center', Alignment.center),
          radius: _toDouble(raw['radius'] ?? 0.5),
          tileMode: tileMode,
        );
      case ShapeGradientKind.sweep:
        return ShapeGradient.sweep(
          colors: colors,
          stops: stops,
          center: _alignment(raw, 'center', Alignment.center),
          startAngle: _toDouble(raw['startAngle'] ?? 0.0),
          endAngle: _toDouble(raw['endAngle'] ?? 6.283185307179586),
          tileMode: tileMode,
        );
    }
  }

  /// Reads `key` as `{x, y}`, or the older `keyX`/`keyY` pair.
  static Alignment _alignment(Map raw, String key, Alignment fallback) {
    final m = raw[key];
    if (m is Map && m['x'] is num && m['y'] is num) {
      return Alignment(_toDouble(m['x']), _toDouble(m['y']));
    }
    final x = raw['${key}X'];
    final y = raw['${key}Y'];
    if (x is num || y is num) return Alignment(_toDouble(x), _toDouble(y));
    return fallback;
  }

  static Map<String, double> _alignmentToJson(AlignmentGeometry a) =>
      a is Alignment ? {'x': a.x, 'y': a.y} : {'x': 0.0, 'y': 0.0};
}
