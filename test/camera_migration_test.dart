// Scene format v1 → v2: the camera component and the follow flag on the
// target become a virtual camera that names what it follows.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Map<String, dynamic> _transform(double x, double y) => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': x, 'y': y},
    'rotation': 0.0,
    'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
  },
};

Map<String, dynamic> _follow({int priority = 0, bool enabled = true}) => {
  'type': 'CameraFollowComponent',
  'fields': {
    'enabled': enabled,
    'lookaheadDistance': 140.0,
    'deadZoneWidth': 128.0,
    'deadZoneHeight': 72.0,
    'priority': priority,
  },
};

Map<String, dynamic> _scene(List<Map<String, dynamic>> entities) => {
  'version': 1,
  'name': 's',
  'entities': entities,
};

Map<String, dynamic>? _fields(Map<String, dynamic> entity, String type) {
  for (final c in (entity['components'] as List).cast<Map<String, dynamic>>()) {
    if (c['type'] == type) return (c['fields'] as Map).cast<String, dynamic>();
  }
  return null;
}

Map<String, dynamic> _named(Map<String, dynamic> scene, String name) =>
    (scene['entities'] as List).cast<Map<String, dynamic>>().firstWhere(
      (e) => e['name'] == name,
    );

void main() {
  setUp(() {
    ComponentCodecRegistry.instance.clear();
    registerCoreCodecs();
  });

  test('a camera entity becomes a virtual camera following the old target', () {
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Hero',
          'components': [_transform(10, 20), _follow()],
        },
        {
          'name': 'MainCamera',
          'components': [
            _transform(0, 0),
            {
              'type': 'CameraComponent',
              'fields': {
                'zoom': 2.0,
                'boundsLeft': 0.0,
                'boundsTop': 0.0,
                'boundsWidth': 4000.0,
                'boundsHeight': 800.0,
              },
            },
          ],
        },
      ]),
    );
    expect(SceneFormat.versionOf(out), 2);

    final camera = _named(out, 'MainCamera');
    expect(_fields(camera, 'CameraComponent'), isNull);
    final vcam = _fields(camera, 'VirtualCameraComponent')!;
    expect(vcam['followName'], 'Hero');
    expect(vcam['zoom'], 2.0);

    // 128 world units of a 1280-wide view at 2× zoom is a fifth of it.
    final framing = _fields(camera, 'CameraFramingComponent')!;
    expect(framing['deadZoneWidth'], closeTo(0.2, 1e-9));
    expect(framing['deadZoneHeight'], closeTo(0.2, 1e-9));
    expect(framing['lookaheadTime'], 0.25);

    expect(_fields(_named(out, 'Hero'), 'CameraFollowComponent'), isNull);

    // Those bounds are the old default, which was saved with every scene
    // and never applied: no confiner appears out of nowhere.
    expect(_fields(camera, 'CameraConfinerComponent'), isNull);
    expect((out['entities'] as List), hasLength(2));
  });

  test('bounds an author set become a bounds entity and a confiner', () {
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Cam',
          'components': [
            _transform(0, 0),
            {
              'type': 'CameraComponent',
              'fields': {
                'zoom': 1.0,
                'boundsLeft': -100.0,
                'boundsTop': 50.0,
                'boundsWidth': 1200.0,
                'boundsHeight': 600.0,
              },
            },
          ],
        },
      ]),
    );
    expect(
      _fields(_named(out, 'Cam'), 'CameraConfinerComponent')!['boundsName'],
      'CamBounds',
    );
    final level = _named(out, 'CamBounds');
    expect(_fields(level, 'TransformComponent')!['position'], {
      'x': 500.0,
      'y': 350.0,
    });
    expect(_fields(level, 'CameraBoundsComponent'), {
      'width': 1200.0,
      'height': 600.0,
    });

    final world = World();
    addTearDown(world.dispose);
    final loaded = SceneLoader.load(world, out);
    expect(
      loaded
          .firstWhere((e) => e.name == 'CamBounds')
          .getComponent<CameraBoundsComponent>()!
          .cameraBoundsAt(const Offset(500, 350)),
      const Rect.fromLTWH(-100, 50, 1200, 600),
    );
  });

  test('every migrated component decodes through its definition', () {
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Hero',
          'components': [_transform(0, 0), _follow()],
        },
      ]),
    );
    final world = World();
    addTearDown(world.dispose);
    final loaded = SceneLoader.load(world, out);
    final camera = loaded.firstWhere((e) => e.name == 'MainCamera');
    expect(camera.getComponent<VirtualCameraComponent>()!.followName, 'Hero');
    expect(camera.hasComponent<CameraFramingComponent>(), isTrue);
  });

  test('a follow with no camera entity gets a MainCamera on the target', () {
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Hero',
          'components': [_transform(640, 360), _follow()],
        },
        {
          'name': 'MainCamera',
          'components': [_transform(0, 0)],
        },
      ]),
    );
    final added = _named(out, 'MainCamera2');
    expect(_fields(added, 'TransformComponent')!['position'], {
      'x': 640.0,
      'y': 360.0,
    });
    expect(_fields(added, 'VirtualCameraComponent')!['followName'], 'Hero');
  });

  test('the lowest-priority enabled follow is the one that was followed', () {
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Off',
          'components': [
            _transform(0, 0),
            _follow(priority: -5, enabled: false),
          ],
        },
        {
          'name': 'Second',
          'components': [_transform(0, 0), _follow(priority: 3)],
        },
        {
          'name': 'First',
          'components': [_transform(0, 0), _follow(priority: 1)],
        },
      ]),
    );
    expect(
      _fields(
        _named(out, 'MainCamera'),
        'VirtualCameraComponent',
      )!['followName'],
      'First',
    );
  });

  test('a scene with no camera parts only changes its version', () {
    final input = _scene([
      {
        'name': 'Block',
        'components': [_transform(1, 2)],
      },
    ]);
    final out = SceneFormat.migrate(input);
    expect(out['entities'], input['entities']);
    expect(out['version'], 2);
  });

  test("a package's entity rule runs, and can rewrite one into several", () {
    void rule(Map<String, dynamic> entity, Map<String, dynamic> scene) {
      final components = entity['components'] as List;
      final had = components.any((c) => c is Map && c['type'] == 'KitZone');
      if (!had) return;
      components
        ..removeWhere((c) => c is Map && c['type'] == 'KitZone')
        ..add({'type': 'A', 'fields': <String, dynamic>{}})
        ..add({'type': 'B', 'fields': <String, dynamic>{}});
    }

    V1ToV2.perEntity.add(rule);
    addTearDown(() => V1ToV2.perEntity.remove(rule));
    final out = SceneFormat.migrate(
      _scene([
        {
          'name': 'Zone',
          'components': [
            {'type': 'KitZone', 'fields': <String, dynamic>{}},
          ],
        },
      ]),
    );
    expect(
      [for (final c in _named(out, 'Zone')['components'] as List) c['type']],
      ['A', 'B'],
    );
  });

  test('a v0 file goes all the way to v2', () {
    final out = SceneFormat.migrate({
      'name': 's',
      'entities': [
        {
          'name': 'MainCamera',
          'components': [
            {
              'type': 'TransformComponent',
              'position': {'dx': 5.0, 'dy': 6.0},
            },
            {'type': 'CameraComponent', 'zoom': 1.5},
          ],
        },
      ],
    });
    expect(out['version'], 2);
    expect(
      _fields(_named(out, 'MainCamera'), 'VirtualCameraComponent')!['zoom'],
      1.5,
    );
  });
}
