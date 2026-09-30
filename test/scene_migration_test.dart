// v0 → v1: flat legacy components are hoisted under `fields`, the two vector
// shapes are reshaped, and nothing else changes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  Map<String, dynamic> scene(List<Map<String, dynamic>> components) => {
    'name': 's',
    'entities': [
      {'name': 'E', 'parentName': null, 'components': components},
    ],
  };
  List<Map<String, dynamic>> componentsOf(Map<String, dynamic> s) =>
      ((s['entities'] as List).first['components'] as List)
          .cast<Map<String, dynamic>>();

  test('a file without a version is v0 and migrates to current', () {
    final out = SceneFormat.migrate(scene([]));
    expect(SceneFormat.versionOf(out), SceneFormat.current);
  });

  test('a current file is returned as is', () {
    final now = {'version': SceneFormat.current, 'name': 's', 'entities': []};
    expect(identical(SceneFormat.migrate(now), now), isTrue);
  });

  test('migration never mutates its input', () {
    final input = scene([
      {'type': 'RectangleComponent', 'width': 10.0, 'height': 5.0},
    ]);
    SceneFormat.migrate(input);
    expect(componentsOf(input).single.containsKey('fields'), isFalse);
  });

  test('flat legacy components are hoisted under fields', () {
    final out = SceneFormat.migrate(
      scene([
        {
          'type': 'RectangleComponent',
          'width': 10.0,
          'height': 5.0,
          'filled': true,
        },
      ]),
    );
    expect(componentsOf(out).single, {
      'type': 'RectangleComponent',
      'fields': {'width': 10.0, 'height': 5.0, 'filled': true},
    });
  });

  test('descriptor-shaped components lose only customComponentId', () {
    final out = SceneFormat.migrate(
      scene([
        {
          'type': 'LayerComponent',
          'customComponentId': 'layer_3ab67e05',
          'fields': {'layerId': 'main', 'layer': 0, 'zOrder': 3},
        },
      ]),
    );
    expect(componentsOf(out).single, {
      'type': 'LayerComponent',
      'fields': {'layerId': 'main', 'layer': 0, 'zOrder': 3},
    });
  });

  test(
    'transform position becomes {x, y} and scalar scale becomes a vector',
    () {
      final out = SceneFormat.migrate(
        scene([
          {
            'type': 'TransformComponent',
            'position': {'dx': 1.0, 'dy': 2.0},
            'rotation': 0.5,
            'scale': 2.0,
          },
        ]),
      );
      // Through to format 6: z, and the angle as a three-angle rotation.
      expect(componentsOf(out).single['fields'], {
        'position': {'x': 1.0, 'y': 2.0, 'z': 0.0},
        'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.5},
        'scale': {'x': 2.0, 'y': 2.0, 'z': 1.0},
      });
    },
  );

  test(
    'velocity is reshaped, and a bare shape colour becomes a fill style',
    () {
      final out = SceneFormat.migrate(
        scene([
          {
            'type': 'VelocityComponent',
            'velocity': {'dx': 3.0, 'dy': 4.0},
            'maxSpeed': 9.0,
          },
          {'type': 'CircleComponent', 'radius': 4.0, 'color': 0xFF112233},
        ]),
      );
      final c = componentsOf(out);
      expect(c[0]['fields'], {
        'velocity': {'x': 3.0, 'y': 4.0, 'z': 0.0},
        'maxSpeed': 9.0,
      });
      expect(c[1]['fields'], {
        'radius': 4.0,
        'fillStyle': {'color': 0xFF112233, 'blendMode': 'modulate'},
      });
    },
  );

  test('a kit can add a rule for its own v0 shape', () {
    V0ToV1.perType['KitThing'] = (c) {
      (c['fields'] as Map)['renamed'] = (c['fields'] as Map).remove('old');
      return c;
    };
    addTearDown(() => V0ToV1.perType.remove('KitThing'));
    final out = SceneFormat.migrate(
      scene([
        {'type': 'KitThing', 'old': 1},
      ]),
    );
    expect(componentsOf(out).single['fields'], {'renamed': 1});
  });
}
