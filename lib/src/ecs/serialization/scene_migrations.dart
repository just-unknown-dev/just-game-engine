library;

/// One step of the scene-format migration chain: from version [from] to
/// [from] + 1.
abstract class SceneMigration {
  const SceneMigration();

  int get from;

  /// Rewrites [json] (a private copy) in place and returns it.
  Map<String, dynamic> apply(Map<String, dynamic> json);
}

/// Rewrites one component's v0 JSON to its v1 shape. Receives the component
/// map with `type` already read; must return `{type, fields}`.
typedef ComponentMigration =
    Map<String, dynamic> Function(Map<String, dynamic> component);

/// v0 → v1: every component becomes `{type, fields}`.
///
/// Most core components were stored flat — `{type, width, height, ...}` — so
/// the general rule hoists every key but `type` under `fields`. Two of them
/// stored vectors as `{dx, dy}` where their definitions read `{x, y}`, and
/// `customComponentId` is dropped (definitions know their aliases). A kit
/// with its own v0 shapes registers rules in [perType].
class V0ToV1 extends SceneMigration {
  const V0ToV1();

  @override
  int get from => 0;

  /// Per-type rewrites, applied after the general hoist. Open so a kit can
  /// add its own.
  static final Map<String, ComponentMigration> perType = {
    'TransformComponent': (c) {
      final f = c['fields'] as Map<String, dynamic>;
      f['position'] = _dxdyToXy(f['position']);
      final scale = f['scale'];
      if (scale is num) {
        f['scale'] = {'x': scale, 'y': scale, 'z': 1.0};
      } else if (scale is Map) {
        f['scale'] = {
          'x': scale['dx'] ?? scale['x'] ?? 1.0,
          'y': scale['dy'] ?? scale['y'] ?? 1.0,
          'z': scale['dz'] ?? scale['z'] ?? 1.0,
        };
      }
      return c;
    },
    'VelocityComponent': (c) {
      final f = c['fields'] as Map<String, dynamic>;
      if (f.containsKey('velocity')) f['velocity'] = _dxdyToXy(f['velocity']);
      return c;
    },
    'RectangleComponent': _legacyColor,
    'CircleComponent': _legacyColor,
    'CapsuleComponent': _legacyColor,
  };

  /// Shapes once stored a bare `color`; it became `fillStyle.color`.
  static Map<String, dynamic> _legacyColor(Map<String, dynamic> c) {
    final f = c['fields'] as Map<String, dynamic>;
    final color = f.remove('color');
    if (color is int && f['fillStyle'] == null) {
      f['fillStyle'] = {'color': color, 'blendMode': 'modulate'};
    }
    return c;
  }

  static Object? _dxdyToXy(Object? v) {
    if (v is Map && v.containsKey('dx')) {
      return {'x': v['dx'] ?? 0.0, 'y': v['dy'] ?? 0.0};
    }
    return v;
  }

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    final entities = json['entities'];
    if (entities is List) {
      for (final entity in entities.whereType<Map<String, dynamic>>()) {
        final components = entity['components'];
        if (components is! List) continue;
        for (var i = 0; i < components.length; i++) {
          final c = components[i];
          if (c is Map<String, dynamic>) components[i] = migrateComponent(c);
        }
      }
    }
    return json;
  }

  /// One component, v0 → v1.
  static Map<String, dynamic> migrateComponent(Map<String, dynamic> c) {
    final type = c['type'];
    final Map<String, dynamic> out;
    if (c['fields'] is Map) {
      out = {
        'type': type,
        'fields': Map<String, dynamic>.from(c['fields'] as Map),
      };
    } else {
      out = {
        'type': type,
        'fields': {
          for (final e in c.entries)
            if (e.key != 'type' && e.key != 'customComponentId') e.key: e.value,
        },
      };
    }
    final rule = type is String ? perType[type] : null;
    return rule == null ? out : rule(out);
  }
}

/// Every migration, in order.
abstract final class SceneMigrations {
  static const List<SceneMigration> chain = [V0ToV1()];
}
