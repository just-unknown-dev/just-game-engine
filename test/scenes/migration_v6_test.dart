import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The engine's own definitions, fresh for this file.
final _coreDefinitions = BuiltInComponents.registry();

/// A version-6 scene shaped like level_01: a Level Map at the origin with a
/// tilted child, as format 6 saves them — positions with `z`, one
/// three-angle `rotation`, and a parent link without an offset.
Map<String, dynamic> _v6() =>
    jsonDecode('''
{
  "version": 6,
  "name": "level",
  "mode": "2d",
  "entities": [
    {"name": "Level Map", "parentName": null, "components": [
      {"type": "TransformComponent", "fields": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0},
        "rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0}}}]},
    {"name": "Tiles_0", "parentName": "Level Map", "components": [
      {"type": "TransformComponent", "fields": {
        "position": {"x": 96.0, "y": -416.0, "z": 0.0},
        "rotation": {"x": 0.25, "y": -0.5, "z": 0.5},
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0}}},
      {"type": "ParentComponent", "fields": {"parentId": 0}}]}
  ],
  "editor": {"guides": []}
}
''')
        as Map<String, dynamic>;

void main() {
  group('format 6 round trips', () {
    test('3-D transform and velocity values survive encode → decode', () {
      final codec = _coreDefinitions;
      final t = TransformComponent(
        position: Vector3(1.5, -2.25, 7),
        euler: Vector3(0.3, -1.1, 2.9),
        scale: Vector3(2, 0.5, -3),
      );
      final v = VelocityComponent(velocity: Vector3(4, 5, -6));
      for (final component in <Component>[t, v]) {
        final json = codec.encode(component)!;
        final again = codec.encode(codec.decode(json)!)!;
        expect(jsonEncode(again), jsonEncode(json));
      }
      final back = codec.decode(codec.encode(t)!)! as TransformComponent;
      expect(
        [back.position.z, back.eulerX, back.eulerY, back.angle],
        [7, 0.3, -1.1, 2.9],
      );
      expect(back.scale.z, -3);
      // Saved as the one rotation field, three angles.
      expect(codec.encode(t)!['fields']['rotation'], {
        'x': 0.3,
        'y': -1.1,
        'z': 2.9,
      });
    });

    test('a scene of format 6 loads unchanged, parents and all', () {
      final scene = _v6();
      final world = World(extensions: [BuiltInComponents.extension])
        ..initialize();
      addTearDown(world.dispose);
      final entities = SceneLoader.load(world, scene);
      final tiles = entities.firstWhere((e) => e.name == 'Tiles_0');
      final t = tiles.getComponent<TransformComponent>()!;
      expect(
        [t.position.x, t.position.y, t.eulerX, t.angle],
        [96, -416, 0.25, 0.5],
      );
      world.update(0);
      expect([t.position.x, t.position.y], [96, -416], reason: 'kept');
      final link = tiles.getComponent<ParentComponent>()!;
      expect(link.localPosition.x, closeTo(96, 1e-9));
      expect(link.localPosition.y, closeTo(-416, 1e-9));
    });

    test('a timeline with three rotation channels round-trips', () {
      final asset = TimelineAsset.fromJson({
        'formatVersion': 2,
        'name': 'spin',
        'duration': 1.0,
        'tracks': [
          for (final ch in ['x', 'y', 'z'])
            {
              'kind': 'property',
              'component': 'TransformComponent',
              'field': 'rotation',
              'channel': ch,
              'keys': [
                {'t': 0.0, 'v': 0.0},
                {'t': 1.0, 'v': 1.0},
              ],
            },
        ],
      });
      expect(asset.propertyTracks.map((t) => t.path), [
        'TransformComponent.rotation.x',
        'TransformComponent.rotation.y',
        'TransformComponent.rotation.z',
      ]);
      final json = asset.toJson();
      expect(json['formatVersion'], TimelineFormat.current);
      expect(
        jsonEncode(TimelineAsset.fromJson(json).toJson()),
        jsonEncode(json),
      );
    });

    test('a timeline turns an entity about all three axes', () {
      final asset = TimelineAsset.fromJson({
        'formatVersion': 2,
        'duration': 1.0,
        'tracks': [
          {
            'kind': 'property',
            'component': 'TransformComponent',
            'field': 'rotation',
            'channel': 'x',
            'keys': [
              {'t': 0.0, 'v': 0.0},
              {'t': 1.0, 'v': 0.8},
            ],
          },
        ],
      });
      final world = World(extensions: [BuiltInComponents.extension])
        ..initialize();
      addTearDown(world.dispose);
      world.addSystem(TimelineSystem());
      final e = world.createEntityWithComponents([
        TransformComponent(angle: 0.4),
        TimelinePlayerComponent(inline: asset, playOnStart: true),
      ]);
      world
        ..update(0)
        ..update(1.0);
      final t = e.getComponent<TransformComponent>()!;
      expect(t.eulerX, closeTo(0.8, 1e-6));
      expect(t.angle, closeTo(0.4, 1e-9), reason: 'z left alone');
    });
  });

  test('an Euler field reads a map, or a plain angle as a turn about Z', () {
    const euler = FieldTypes.euler;
    final v =
        euler.decode({'x': 1, 'y': 2, 'z': 3}, FieldConstraints.none)
            as Vector3;
    expect([v.x, v.y, v.z], [1, 2, 3]);
    final z = euler.decode(0.5, FieldConstraints.none) as Vector3;
    expect([z.x, z.y, z.z], [0, 0, 0.5]);
    expect(euler.encode(Vector3(1, 2, 3)), {'x': 1.0, 'y': 2.0, 'z': 3.0});
    expect(euler.channels2D, {'z'});
  });
}
