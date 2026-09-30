import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A version-5 scene shaped like level_01: a Level Map at the origin with a
/// child whose saved offset is stale, a spinning coin with an inline
/// timeline, a tilted thing and a moving thing.
Map<String, dynamic> _v5() => jsonDecode('''
{
  "version": 5,
  "name": "level",
  "root": {"name": "root", "localPosition": {"dx": 0.0, "dy": 0.0},
           "localRotation": 0.0, "localScale": 1.0, "isActive": true,
           "children": []},
  "entities": [
    {"name": "Level Map", "parentName": null, "components": [
      {"type": "TransformComponent", "fields": {
        "position": {"x": 0.0, "y": 0.0}, "rotation": 0.0,
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
        "rotationX": 0.0, "rotationY": 0.0}}]},
    {"name": "Tiles_0", "parentName": "Level Map", "components": [
      {"type": "TransformComponent", "fields": {
        "position": {"x": 96.0, "y": -416.0}, "rotation": 0.5,
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
        "rotationX": 0.25, "rotationY": -0.5}},
      {"type": "ParentComponent", "fields": {
        "parentId": 0, "localOffset": {"dx": 128.0, "dy": -256.0},
        "localRotation": 0.0}}]},
    {"name": "Coin", "parentName": null, "components": [
      {"type": "TransformComponent", "fields": {
        "position": {"x": 5.0, "y": 6.0}, "rotation": 0.0,
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0}}},
      {"type": "VelocityComponent", "fields": {
        "velocity": {"x": 3.0, "y": 4.0}, "maxSpeed": 10.0}},
      {"type": "TimelinePlayerComponent", "fields": {
        "timelinePath": "",
        "inline": {"formatVersion": 1, "duration": 1.0, "fps": 30,
          "wrap": "loop", "tracks": [
            {"kind": "property", "component": "TransformComponent",
             "field": "rotation", "keys": [{"t": 0.0, "v": 0.0}]},
            {"kind": "property", "component": "TransformComponent",
             "field": "position", "channel": "y", "keys": []}
          ]},
        "playOnStart": true, "speed": 1.0, "wrap": "fromTimeline",
        "listenSignal": ""}}]}
  ],
  "editor": {"guides": []}
}
''') as Map<String, dynamic>;

Map<String, dynamic> _fields(Map<String, dynamic> scene, String name, String type) {
  final e = (scene['entities'] as List).cast<Map>().firstWhere(
    (e) => e['name'] == name,
  );
  return ((e['components'] as List).cast<Map>().firstWhere(
            (c) => c['type'] == type,
          )['fields']
          as Map)
      .cast<String, dynamic>();
}

void main() {
  group('V5ToV6', () {
    test('transforms get z and a three-angle rotation', () {
      final out = const V5ToV6().apply(_v5());
      final t = _fields(out, 'Tiles_0', 'TransformComponent');
      expect(t['position'], {'x': 96.0, 'y': -416.0, 'z': 0.0});
      expect(t['rotation'], {'x': 0.25, 'y': -0.5, 'z': 0.5});
      expect(t.containsKey('rotationX'), isFalse);
      expect(t.containsKey('rotationY'), isFalse);
      final flat = _fields(out, 'Coin', 'TransformComponent');
      expect(flat['rotation'], {'x': 0.0, 'y': 0.0, 'z': 0.0});
      expect(
        _fields(out, 'Coin', 'VelocityComponent')['velocity'],
        {'x': 3.0, 'y': 4.0, 'z': 0.0},
      );
    });

    test('parent offsets go, the stale one is reported, root goes', () {
      final out = const V5ToV6().apply(_v5());
      final link = _fields(out, 'Tiles_0', 'ParentComponent');
      expect(link.keys, ['parentId']);
      expect(V5ToV6.report, hasLength(1));
      expect(V5ToV6.report.single, contains('Tiles_0'));
      expect(out.containsKey('root'), isFalse);
      expect(out['mode'], '2d');
      expect(out['editor'], {'guides': []}, reason: 'left alone');
    });

    test('inline timelines move to format 2', () {
      final out = const V5ToV6().apply(_v5());
      final inline = _fields(out, 'Coin', 'TimelinePlayerComponent')['inline']
          as Map;
      expect(inline['formatVersion'], 2);
      final tracks = (inline['tracks'] as List).cast<Map>();
      expect(tracks[0]['field'], 'rotation');
      expect(tracks[0]['channel'], 'z');
      expect(tracks[1]['channel'], 'y', reason: 'position tracks unchanged');
    });

    test('a kit can add its own rules', () {
      V5ToV6.perType['TransformComponent'] = (f) => f['seen'] = true;
      addTearDown(() => V5ToV6.perType.remove('TransformComponent'));
      final out = const V5ToV6().apply(_v5());
      expect(_fields(out, 'Coin', 'TransformComponent')['seen'], isTrue);
    });
  });

  group('TimelineFormat', () {
    test('v1 rotation tracks key the right channels; offsets are dropped', () {
      final v1 = <String, dynamic>{
        'tracks': [
          {
            'kind': 'property',
            'component': 'TransformComponent',
            'field': 'rotationX',
          },
          {
            'kind': 'property',
            'component': 'TransformComponent',
            'field': 'rotationY',
          },
          {
            'kind': 'property',
            'component': 'ParentComponent',
            'field': 'localOffset',
            'channel': 'dx',
          },
          {'kind': 'event', 'events': []},
        ],
      };
      final copy = jsonDecode(jsonEncode(v1));
      final out = TimelineFormat.migrate(v1);
      expect(v1, copy, reason: 'the input is never changed');
      expect(out['formatVersion'], 2);
      final tracks = (out['tracks'] as List).cast<Map>();
      expect(tracks, hasLength(3));
      expect([tracks[0]['field'], tracks[0]['channel']], ['rotation', 'x']);
      expect([tracks[1]['field'], tracks[1]['channel']], ['rotation', 'y']);
      expect(tracks[2]['kind'], 'event');
    });

    test('a current file is returned as it is', () {
      final v2 = {'formatVersion': 2, 'tracks': []};
      expect(identical(TimelineFormat.migrate(v2), v2), isTrue);
    });
  });

  group('format 6 round trips', () {
    setUp(registerCoreCodecs);

    test('3-D transform and velocity values survive encode → decode', () {
      final codec = ComponentCodecRegistry.instance;
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
      expect([back.position.z, back.eulerX, back.eulerY, back.angle], [
        7,
        0.3,
        -1.1,
        2.9,
      ]);
      expect(back.scale.z, -3);
      // Saved as the one rotation field, three angles.
      expect(codec.encode(t)!['fields']['rotation'], {
        'x': 0.3,
        'y': -1.1,
        'z': 2.9,
      });
    });

    test('a scene of format 6 loads unchanged, parents and all', () {
      final scene = const V5ToV6().apply(_v5())..['version'] = 6;
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entities = SceneLoader.load(world, scene);
      final tiles = entities.firstWhere((e) => e.name == 'Tiles_0');
      final t = tiles.getComponent<TransformComponent>()!;
      expect([t.position.x, t.position.y, t.eulerX, t.angle], [
        96,
        -416,
        0.25,
        0.5,
      ]);
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
      expect(json['formatVersion'], 2);
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
      final world = World()..initialize();
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
    final v = euler.decode({'x': 1, 'y': 2, 'z': 3}, FieldConstraints.none)
        as Vector3;
    expect([v.x, v.y, v.z], [1, 2, 3]);
    final z = euler.decode(0.5, FieldConstraints.none) as Vector3;
    expect([z.x, z.y, z.z], [0, 0, 0.5]);
    expect(euler.encode(Vector3(1, 2, 3)), {'x': 1.0, 'y': 2.0, 'z': 3.0});
    expect(euler.channels2D, {'z'});
  });
}
