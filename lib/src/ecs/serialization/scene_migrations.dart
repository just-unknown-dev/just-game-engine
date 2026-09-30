library;

import '../../subsystems/timeline/timeline_format.dart';

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

/// v2 → v3: sprites play from an atlas.
///
/// - `AnimatedSpriteComponent` becomes `SpriteAnimationComponent`. Its
///   `jsonPath` becomes `atlasPath` and `activeClip` becomes `clip`. The old
///   grid description (frame size, columns, inline clips, fps) has no place
///   in the new component — an atlas file holds all of that — so an entity
///   that relied on it is listed in [needsAtlas] for a tool to export one.
/// - `AnimationStateComponent` is removed: it named a clip and counted
///   frames, which the sprite animation now does by itself.
/// - `SpriteComponent.frame` is dropped; a frame of a sheet is an atlas
///   region now.
class V2ToV3 extends SceneMigration {
  const V2ToV3();

  @override
  int get from => 2;

  /// Entity-level rules a package adds for its own components.
  static final List<EntityMigration> perEntity = [];

  /// Names of entities whose old animated sprite had no atlas JSON to point
  /// at, from the most recent [apply]. Their sheet needs exporting as an
  /// atlas before they animate again.
  static final List<String> needsAtlas = [];

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    needsAtlas.clear();
    final list = json['entities'];
    if (list is! List) return json;
    for (final entity in list.whereType<Map<String, dynamic>>()) {
      final components = entity['components'];
      if (components is List) {
        components.removeWhere(
          (c) => c is Map && c['type'] == 'AnimationStateComponent',
        );
        for (var i = 0; i < components.length; i++) {
          final c = components[i];
          if (c is! Map) continue;
          final fields = c['fields'];
          if (c['type'] == 'SpriteComponent' && fields is Map) {
            fields.remove('frame');
          }
          if (c['type'] != 'AnimatedSpriteComponent') continue;
          final old = fields is Map ? fields : const {};
          final atlasPath = _atlasPathOf(old);
          if ((old['jsonPath'] as String? ?? '').trim().isEmpty) {
            needsAtlas.add('${entity['name'] ?? '(unnamed)'}');
          }
          components[i] = <String, dynamic>{
            'type': 'SpriteAnimationComponent',
            'fields': <String, dynamic>{
              'atlasPath': atlasPath,
              'clip': old['activeClip'] ?? '',
              'playOnStart': old['playOnStart'] ?? true,
              'speed': 1.0,
              'flipX': false,
              'flipY': false,
              'tint': null,
              // The old component smoothed; keep what the scene looked like.
              'pixelArt': false,
            },
          };
        }
      }
      for (final migrate in perEntity) {
        migrate(entity, json);
      }
    }
    return json;
  }

  /// The old `jsonPath` if there was one; failing that the sheet's own path
  /// with `.json`, which is where a tool exporting an atlas for it will put
  /// the file.
  static String _atlasPathOf(Map old) {
    final json = (old['jsonPath'] as String? ?? '').trim();
    if (json.isNotEmpty) return json;
    final sheet = (old['spritePath'] as String? ?? '').trim();
    final dot = sheet.lastIndexOf('.');
    if (sheet.isEmpty || dot <= sheet.lastIndexOf('/')) return '';
    return '${sheet.substring(0, dot)}.json';
  }
}

/// v3 → v4: timelines.
///
/// `AnimationControllerComponent` — one flat list of transform keyframes —
/// becomes a `TimelinePlayerComponent` holding the same motion as an
/// **inline** timeline: a property track for each transform channel the old
/// keyframes set (absolute, as they were), and an event track. A migration
/// cannot write files, so nothing becomes a `.timeline.json` by itself; an
/// editor offers to extract one.
///
/// The old easings were quadratic, which a cubic bezier draws exactly (ease
/// in, ease out) or as near as makes no difference (ease in-out).
class V3ToV4 extends SceneMigration {
  const V3ToV4();

  @override
  int get from => 3;

  /// Entity-level rules a package adds for its own components.
  static final List<EntityMigration> perEntity = [];

  // Old keyframe property → (transform field, channel).
  static const Map<String, (String, String)> _channels = {
    'posX': ('position', 'x'),
    'posY': ('position', 'y'),
    'rotation': ('rotation', ''),
    'scaleX': ('scale', 'x'),
    'scaleY': ('scale', 'y'),
  };

  // Easing → the bezier's two control points, as fractions of the segment.
  static const Map<String, (double, double, double, double)> _beziers = {
    'easeIn': (1 / 3, 0, 2 / 3, 1 / 3),
    'easeOut': (1 / 3, 2 / 3, 2 / 3, 1),
    'easeInOut': (0.455, 0.03, 0.515, 0.955),
  };

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    final list = json['entities'];
    if (list is! List) return json;
    for (final entity in list.whereType<Map<String, dynamic>>()) {
      final components = entity['components'];
      if (components is List) {
        for (var i = 0; i < components.length; i++) {
          final c = components[i];
          if (c is! Map || c['type'] != 'AnimationControllerComponent') {
            continue;
          }
          final fields = c['fields'];
          components[i] = _player(fields is Map ? fields : const {});
        }
      }
      for (final migrate in perEntity) {
        migrate(entity, json);
      }
    }
    return json;
  }

  static Map<String, dynamic> _player(Map old) {
    final keyframes = [
      for (final k in old['keyframes'] as List? ?? const [])
        if (k is Map && k['time'] is num) k,
    ]..sort((a, b) => (a['time'] as num).compareTo(b['time'] as num));

    final tracks = <Map<String, dynamic>>[];
    for (final entry in _channels.entries) {
      final keys = _keys(keyframes, entry.key);
      if (keys.isEmpty) continue;
      final (field, channel) = entry.value;
      tracks.add({
        'kind': 'property',
        'component': 'TransformComponent',
        'field': field,
        if (channel.isNotEmpty) 'channel': channel,
        'keys': keys,
      });
    }
    final events = [
      for (final e in old['events'] as List? ?? const [])
        if (e is Map)
          <String, dynamic>{'time': e['time'] ?? 0, 'name': e['name'] ?? ''},
    ];
    if (events.isNotEmpty) tracks.add({'kind': 'event', 'events': events});

    return <String, dynamic>{
      'type': 'TimelinePlayerComponent',
      'fields': <String, dynamic>{
        'timelinePath': '',
        'inline': <String, dynamic>{
          'formatVersion': 1,
          'duration': old['duration'] ?? 1.0,
          'fps': 30,
          'wrap': old['loop'] == true ? 'loop' : 'once',
          'tracks': tracks,
        },
        'playOnStart': old['playOnStart'] ?? false,
        'speed': 1.0,
        'wrap': 'fromTimeline',
        'listenSignal': '',
      },
    };
  }

  /// The keys of one channel: a key wherever a keyframe set [property],
  /// eased to the next the way that keyframe said.
  static List<Map<String, dynamic>> _keys(
    List<Map> keyframes,
    String property,
  ) {
    final set = [
      for (final k in keyframes)
        if (k[property] is num) k,
    ];
    final keys = <Map<String, dynamic>>[
      for (final k in set)
        {
          't': (k['time'] as num).toDouble(),
          'v': (k[property] as num).toDouble(),
          // Handles are as authored here: nothing may smooth them.
          'm': 'broken',
        },
    ];
    for (var i = 0; i < set.length; i++) {
      final bezier = _beziers[set[i]['easing']];
      if (bezier == null || i == set.length - 1) {
        keys[i]['i'] = 'linear';
        continue;
      }
      final (x1, y1, x2, y2) = bezier;
      final span = (keys[i + 1]['t'] as double) - (keys[i]['t'] as double);
      final rise = (keys[i + 1]['v'] as double) - (keys[i]['v'] as double);
      keys[i]['out'] = [x1 * span, y1 * rise];
      keys[i + 1]['in'] = [(x2 - 1) * span, (y2 - 1) * rise];
    }
    return keys;
  }
}

/// v4 → v5: UI that keeps its look.
///
/// The old `TextComponent` saved its words and its box and nothing else —
/// colour, size and alignment lived in a Flutter `TextStyle` that was never
/// written to the file, so every save quietly reset them. The new one holds
/// a `UiTextStyle` instead, and old scenes come across with the text they
/// had, at the size the old default drew it.
class V4ToV5 extends SceneMigration {
  const V4ToV5();

  @override
  int get from => 4;

  /// Entity-level rules a package adds for its own components.
  static final List<EntityMigration> perEntity = [];

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    final list = json['entities'];
    if (list is! List) return json;
    for (final entity in list.whereType<Map<String, dynamic>>()) {
      final components = entity['components'];
      if (components is List) {
        for (var i = 0; i < components.length; i++) {
          final c = components[i];
          if (c is! Map) continue;
          final fields = c['fields'];
          if (fields is! Map) continue;
          switch (c['type']) {
            case 'TextComponent':
              _text(fields);
            case 'ButtonComponent':
              _button(fields);
          }
        }
      }
      for (final migrate in perEntity) {
        migrate(entity, json);
      }
    }
    return json;
  }

  /// The old component's look, as the old painter drew it: white, 16pt,
  /// centred. That is what these scenes have been showing, so that is what
  /// they keep.
  static void _text(Map fields) {
    fields['textValue'] = fields.remove('textValue') ?? 'Text';
    fields['style'] = <String, dynamic>{'size': 16.0, 'color': 0xFFFFFFFF};
    fields['styleRole'] = 'body';
    fields['align'] = 'center';
    fields['overflow'] = 'visible';
    fields['wrap'] = false;
    fields['revealSpeed'] = 0.0;
  }

  /// A button's label carried its own style in the same way.
  static void _button(Map fields) {
    fields['label'] = fields.remove('label') ?? 'Button';
    fields['labelStyle'] = <String, dynamic>{
      'size': 13.0,
      'weight': 700,
      'color': 0xFFFFFFFF,
    };
  }
}

/// v5 → v6: every entity is 3-D.
///
/// * A transform's `position` gains `z` (0), and its rotation — one angle
///   `rotation` plus the hidden tilts `rotationX` / `rotationY` — becomes
///   one field, `rotation: {x, y, z}` in radians.
/// * A velocity gains `z` (0).
/// * A parent link no longer saves an offset (`localOffset`,
///   `localRotation`): it follows from the world transforms, which are what
///   the scene has always shown — the saved offsets were often stale. Where
///   an offset disagreed with the transforms, [report] says so.
/// * The legacy `root` node tree — a 2-D copy of the transforms — goes.
/// * The scene says how it is authored: `mode` is `'2d'` unless it said.
/// * Inline timelines move to timeline format 2 ([TimelineFormat]).
///
/// A package with its own fields to move registers [perType] rules (by
/// component type, given the fields map) or [perEntity] ones.
class V5ToV6 extends SceneMigration {
  const V5ToV6();

  @override
  int get from => 5;

  /// Per-type rewrites of a component's `fields`, applied after the
  /// built-in ones. Open so a kit can add its own.
  static final Map<String, void Function(Map<String, dynamic> fields)>
  perType = {};

  /// Entity-level rules a package adds for its own components.
  static final List<EntityMigration> perEntity = [];

  /// What the last run noticed that a person may want to know — parent
  /// offsets that disagreed with where their entities actually were.
  static final List<String> report = [];

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    report.clear();
    json.remove('root');
    json['mode'] ??= '2d';
    final list = json['entities'];
    if (list is! List) return json;
    final entities = list.whereType<Map<String, dynamic>>().toList();

    // Where each entity was, before anything is rewritten — for noticing
    // stale offsets.
    final positions = <String, (double, double)>{};
    for (final e in entities) {
      final name = e['name'];
      final t = _fieldsOf(e, 'TransformComponent');
      final p = t?['position'];
      if (name is String && p is Map) {
        positions[name] = (_d(p['x']), _d(p['y']));
      }
    }

    for (final entity in entities) {
      final components = entity['components'];
      if (components is List) {
        for (final c in components) {
          if (c is! Map) continue;
          final fields = c['fields'];
          if (fields is! Map<String, dynamic>) continue;
          switch (c['type']) {
            case 'TransformComponent':
              _transform(fields);
            case 'VelocityComponent':
              _addZ(fields, 'velocity');
            case 'ParentComponent':
              _parent(fields, entity, positions);
            case 'TimelinePlayerComponent':
              final inline = fields['inline'];
              if (inline is Map<String, dynamic>) {
                fields['inline'] = TimelineFormat.migrate(inline);
              }
          }
          perType[c['type']]?.call(fields);
        }
      }
      for (final migrate in perEntity) {
        migrate(entity, json);
      }
    }
    // In the order the editor writes a scene: version, name, mode, the rest.
    return <String, dynamic>{
      for (final k in const ['version', 'name', 'mode'])
        if (json.containsKey(k)) k: json[k],
      for (final e in json.entries)
        if (!const ['version', 'name', 'mode'].contains(e.key)) e.key: e.value,
    };
  }

  static void _transform(Map<String, dynamic> fields) {
    _addZ(fields, 'position');
    final rotation = fields['rotation'];
    final tiltX = fields.remove('rotationX');
    final tiltY = fields.remove('rotationY');
    if (rotation is! Map) {
      fields['rotation'] = <String, dynamic>{
        'x': _d(tiltX),
        'y': _d(tiltY),
        'z': _d(rotation),
      };
    }
  }

  static void _addZ(Map<String, dynamic> fields, String key) {
    final v = fields[key];
    if (v is Map) v['z'] ??= 0.0;
  }

  static void _parent(
    Map<String, dynamic> fields,
    Map<String, dynamic> entity,
    Map<String, (double, double)> positions,
  ) {
    final offset = fields.remove('localOffset');
    fields.remove('localRotation');
    final name = entity['name'];
    final parentName = entity['parentName'];
    final here = positions[name];
    final there = positions[parentName];
    if (offset is Map && here != null && there != null) {
      final dx = here.$1 - there.$1, dy = here.$2 - there.$2;
      if ((dx - _d(offset['dx'])).abs() > 1e-6 ||
          (dy - _d(offset['dy'])).abs() > 1e-6) {
        report.add(
          '$name: its saved offset from $parentName '
          '(${_d(offset['dx'])}, ${_d(offset['dy'])}) disagreed with where '
          'it is ($dx, $dy); where it is was kept.',
        );
      }
    }
  }

  static Map<String, dynamic>? _fieldsOf(
    Map<String, dynamic> entity,
    String type,
  ) {
    final components = entity['components'];
    if (components is! List) return null;
    for (final c in components) {
      if (c is Map && c['type'] == type) {
        final f = c['fields'];
        if (f is Map<String, dynamic>) return f;
      }
    }
    return null;
  }

  static double _d(Object? v) => v is num ? v.toDouble() : 0.0;
}

/// Every migration, in order.
abstract final class SceneMigrations {
  static const List<SceneMigration> chain = [
    V0ToV1(),
    V1ToV2(),
    V2ToV3(),
    V3ToV4(),
    V4ToV5(),
    V5ToV6(),
  ];
}
