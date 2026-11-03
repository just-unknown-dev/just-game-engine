library;

import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import 'field_type.dart';

double _d(Object? v) => v is num ? v.toDouble() : 0.0;

/// A physics [CollisionShape], stored as `{kind, ...dimensions}`.
class PhysicsShapeFieldType extends FieldType<CollisionShape> {
  /// Const constructor; the shared instance is [FieldTypes.physicsShape].
  const PhysicsShapeFieldType();

  @override
  String get id => 'physicsShape';

  @override
  Object? encode(CollisionShape value) => switch (value) {
    CircleShape s => {
      'kind': 'circle',
      'radius': s.radius,
      if (s.center != Offset.zero) 'center': _offset(s.center),
    },
    RoundedPolygonShape s => {
      'kind': 'rounded_polygon',
      'vertices': _offsets(s.vertices),
      'cornerRadius': s.cornerRadius,
    },
    RectangleShape s => {
      'kind': 'rectangle',
      'width': s.width,
      'height': s.height,
    },
    PolygonShape s => {'kind': 'polygon', 'vertices': _offsets(s.vertices)},
    CapsuleShape s => {
      'kind': 'capsule',
      'center1': _offset(s.center1),
      'center2': _offset(s.center2),
      'radius': s.radius,
    },
    SegmentShape s => {
      'kind': 'segment',
      'point1': _offset(s.point1),
      'point2': _offset(s.point2),
      'thickness': s.thickness,
    },
    ChainShape s => {
      'kind': 'chain',
      'vertices': _offsets(s.vertices),
      'loop': s.loop,
      'thickness': s.thickness,
    },
    _ => {'kind': 'rectangle', 'width': 64.0, 'height': 64.0},
  };

  @override
  Object? decode(Object? json, FieldConstraints c) {
    if (json is! Map) return json;
    return decodeShape(json);
  }

  /// The shape [raw] describes, or null when it describes none.
  static CollisionShape? decodeShape(Map raw) {
    switch (raw['kind']) {
      case 'circle':
        return CircleShape(
          _d(raw['radius'] ?? 16.0),
          center: _offsetFrom(raw['center']),
        );
      case 'rectangle':
        return RectangleShape(
          _d(raw['width'] ?? 64.0),
          _d(raw['height'] ?? 64.0),
        );
      case 'polygon':
        final v = _offsetsFrom(raw['vertices']);
        return v.isEmpty ? null : PolygonShape(v);
      case 'capsule':
        return CapsuleShape(
          center1: _offsetFrom(raw['center1']),
          center2: _offsetFrom(raw['center2']),
          radius: _d(raw['radius'] ?? 8.0),
        );
      case 'segment':
        return SegmentShape(
          _offsetFrom(raw['point1']),
          _offsetFrom(raw['point2']),
          thickness: _d(raw['thickness'] ?? 2.0),
        );
      case 'chain':
        final v = _offsetsFrom(raw['vertices']);
        return v.isEmpty
            ? null
            : ChainShape(
                v,
                loop: raw['loop'] == true,
                thickness: _d(raw['thickness'] ?? 2.0),
              );
      case 'rounded_polygon':
        final v = _offsetsFrom(raw['vertices']);
        return v.isEmpty
            ? null
            : RoundedPolygonShape(v, _d(raw['cornerRadius'] ?? 6.0));
      default:
        return null;
    }
  }

  static Map<String, double> _offset(Offset o) => {'dx': o.dx, 'dy': o.dy};
  static List<Map<String, double>> _offsets(List<Offset> v) => [
    for (final o in v) _offset(o),
  ];
  static Offset _offsetFrom(Object? raw) =>
      raw is Map ? Offset(_d(raw['dx'] ?? 0), _d(raw['dy'] ?? 0)) : Offset.zero;
  static List<Offset> _offsetsFrom(Object? raw) => raw is List
      ? [for (final m in raw.whereType<Map>()) _offsetFrom(m)]
      : const [];
}

/// A collision layer, 0 to 15, saved as its number. Reading clamps it into
/// range.
class PhysicsLayerFieldType extends FieldType<int> {
  /// Const constructor; the shared instance is [FieldTypes.physicsLayer].
  const PhysicsLayerFieldType();

  @override
  String get id => 'physicsLayer';

  @override
  Object? encode(int value) => value;

  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is num ? json.toInt().clamp(0, 15) : json;
}

/// A set of collision layers as a 16-bit mask, saved as its number — or
/// null, saved as null, for "as the project's grid says".
class PhysicsLayerMaskFieldType extends FieldType<int> {
  /// Const constructor; the shared instance is
  /// [FieldTypes.physicsLayerMask].
  const PhysicsLayerMaskFieldType();

  @override
  String get id => 'physicsLayerMask';

  @override
  Object? encode(int value) => value & 0xFFFF;

  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is num ? json.toInt() & 0xFFFF : json;
}
