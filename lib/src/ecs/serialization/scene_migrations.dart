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

/// Rewrites one entity in place. [scene] is the whole file, for a migration
/// that has to look at — or add — other entities.
typedef EntityMigration =
    void Function(Map<String, dynamic> entity, Map<String, dynamic> scene);

/// v1 → v2: the camera becomes virtual cameras.
///
/// - An entity with `CameraComponent` becomes a `VirtualCameraComponent`
///   with the same zoom. Bounds an author set become a bounds entity and a
///   `CameraConfinerComponent` naming it.
/// - `CameraFollowComponent` used to sit on the *target*. It is removed, and
///   the scene's camera is told to follow that entity by name, framed by a
///   `CameraFramingComponent` built from the old dead zone and lookahead.
/// - A scene that had a follow target but no camera entity gets a
///   `MainCamera` — that is what the old follow system did implicitly.
///
/// The old dead zone was in world units and framing is in screen fractions,
/// so the conversion assumes a [nominalView]; it is a starting point to tune,
/// not an exact translation.
class V1ToV2 extends SceneMigration {
  const V1ToV2();

  @override
  int get from => 1;

  /// The view the old world-unit dead zones are read against.
  static const double nominalViewWidth = 1280;
  static const double nominalViewHeight = 720;

  /// Entity-level rules a package adds for its own components: one component
  /// becoming several, or moving to another entity. Run after the core ones.
  static final List<EntityMigration> perEntity = [];

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    final list = json['entities'];
    if (list is! List) return json;
    final entities = list.whereType<Map<String, dynamic>>().toList();

    // Who the camera followed: the enabled follow with the lowest priority.
    Map<String, dynamic>? followed;
    Map<String, dynamic>? follow;
    for (final entity in entities) {
      final f = _fieldsOf(entity, 'CameraFollowComponent');
      if (f == null || f['enabled'] == false) continue;
      final priority = (f['priority'] as num?) ?? 0;
      if (follow == null || priority < ((follow['priority'] as num?) ?? 0)) {
        followed = entity;
        follow = f;
      }
    }
    final followName = followed?['name'] as String? ?? '';

    var cameras = 0;
    for (final entity in entities) {
      final camera = _fieldsOf(entity, 'CameraComponent');
      if (camera == null) continue;
      cameras++;
      final zoom = (camera['zoom'] as num?)?.toDouble() ?? 1.0;
      final components = entity['components'] as List;
      components
        ..removeWhere((c) => c is Map && c['type'] == 'CameraComponent')
        ..add(_virtualCamera(followName, zoom));
      if (follow != null) components.add(_framing(follow, zoom));
      final bounds = _authoredBounds(camera);
      if (bounds != null) {
        final name = _uniqueName(
          list.whereType<Map<String, dynamic>>().toList(),
          '${entity['name'] ?? 'Camera'}Bounds',
        );
        list.add({
          'name': name,
          'components': [
            {
              'type': 'TransformComponent',
              'fields': {
                'position': {'x': bounds.$1, 'y': bounds.$2},
                'rotation': 0.0,
                'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
              },
            },
            {
              'type': 'CameraBoundsComponent',
              'fields': {'width': bounds.$3, 'height': bounds.$4},
            },
          ],
        });
        components.add({
          'type': 'CameraConfinerComponent',
          'fields': {'boundsName': name, 'damping': 0.0},
        });
      }
    }

    if (cameras == 0 && followed != null && follow != null) {
      final at = _fieldsOf(followed, 'TransformComponent')?['position'];
      list.add({
        'name': _uniqueName(entities, 'MainCamera'),
        'components': [
          {
            'type': 'TransformComponent',
            'fields': {
              'position': at is Map ? Map<String, dynamic>.from(at) : _origin,
              'rotation': 0.0,
              'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
            },
          },
          _virtualCamera(followName, 1.0),
          _framing(follow, 1.0),
        ],
      });
    }

    for (final entity in entities) {
      final components = entity['components'];
      if (components is List) {
        components.removeWhere(
          (c) => c is Map && c['type'] == 'CameraFollowComponent',
        );
      }
      for (final migrate in perEntity) {
        migrate(entity, json);
      }
    }
    return json;
  }

  static const Map<String, dynamic> _origin = {'x': 0.0, 'y': 0.0};

  /// Centre and size of bounds somebody set, or null for the old default.
  ///
  /// `CameraComponent.bounds` was saved but never applied, so every scene
  /// carries the default 4000×800 whether or not its level fits. Turning
  /// that into a live confiner would clamp cameras that were never clamped;
  /// only bounds an author changed are carried over.
  static (double, double, double, double)? _authoredBounds(
    Map<String, dynamic> camera,
  ) {
    double? n(String key) => (camera[key] as num?)?.toDouble();
    final left = n('boundsLeft'), top = n('boundsTop');
    final width = n('boundsWidth'), height = n('boundsHeight');
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    if (width <= 0 || height <= 0) return null;
    if (left == 0 && top == 0 && width == 4000 && height == 800) return null;
    return (left + width / 2, top + height / 2, width, height);
  }

  static Map<String, dynamic>? _fieldsOf(
    Map<String, dynamic> entity,
    String type,
  ) {
    final components = entity['components'];
    if (components is! List) return null;
    for (final c in components) {
      if (c is Map && c['type'] == type && c['fields'] is Map) {
        return (c['fields'] as Map).cast<String, dynamic>();
      }
    }
    return null;
  }

  static String _uniqueName(List<Map<String, dynamic>> entities, String base) {
    final taken = {for (final e in entities) e['name']};
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  static Map<String, dynamic> _virtualCamera(String followName, double zoom) =>
      {
        'type': 'VirtualCameraComponent',
        'fields': {
          'priority': 10,
          'enabled': true,
          'standbyUpdate': 'never',
          'followName': followName,
          'followTag': '',
          'zoom': zoom,
          'dutch': 0.0,
        },
      };

  static Map<String, dynamic> _framing(
    Map<String, dynamic> follow,
    double zoom,
  ) {
    double fraction(Object? worldUnits, double view) {
      final units = (worldUnits as num?)?.toDouble() ?? 0;
      return (units / (view / (zoom <= 0 ? 1 : zoom))).clamp(0.0, 1.0);
    }

    final lookahead = (follow['lookaheadDistance'] as num?)?.toDouble() ?? 0;
    return {
      'type': 'CameraFramingComponent',
      'fields': {
        'screenX': 0.0,
        'screenY': 0.0,
        'deadZoneWidth': fraction(follow['deadZoneWidth'], nominalViewWidth),
        'deadZoneHeight': fraction(follow['deadZoneHeight'], nominalViewHeight),
        'softZoneWidth': 0.8,
        'softZoneHeight': 0.8,
        'dampingX': 0.5,
        'dampingY': 0.5,
        // The old lookahead was a distance at full speed; a quarter second
        // of velocity is the nearest honest equivalent.
        'lookaheadTime': lookahead > 0 ? 0.25 : 0.0,
        'lookaheadSmoothing': 0.3,
        'followX': true,
        'followY': true,
      },
    };
  }
}

/// Every migration, in order.
abstract final class SceneMigrations {
  static const List<SceneMigration> chain = [V0ToV1(), V1ToV2()];
}
