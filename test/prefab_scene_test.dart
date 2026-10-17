// Prefab files in a running engine: a 2-D scene placing a prefab — its
// changes applied, an entity of the scene under one inside the instance,
// every entity made marked where it came from; a spawner placing one at a
// spawn point; one not read standing empty; the loader seam an editor
// points at its files; and an older prefab's components brought up to date.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Serves [files] by key.
final class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('No asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

Map<String, dynamic> _transform(double x, double y) => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': x, 'y': y, 'z': 0.0},
  },
};

Map<String, dynamic> _tags(List<String> tags) => {
  'type': 'TagComponent',
  'fields': {'tags': tags},
};

const _crate = 'assets/prefabs/crate.prefab.json';

/// A crate: a box with a lid 10 px above it.
final _crateFile = PrefabFile(
  name: 'Crate',
  entities: [
    PrefabEntity(id: 'box', name: 'Box', components: [_transform(0, 0), _tags(['crate'])]),
    PrefabEntity(id: 'lid', name: 'Lid', parent: 'box', components: [_transform(0, -10)]),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;

  World worldWith(Map<String, String> files) {
    final w = World(context: EngineContext(bundle: _Bundle(files)))..initialize();
    addTearDown(w.dispose);
    return w;
  }

  Vector3 at(Entity e) => e.getComponent<TransformComponent>()!.position;
  Entity named(String name) => world.entities.firstWhere((e) => e.name == name);

  test('a 2-D scene places a prefab, its changes and its marks kept', () async {
    world = worldWith({
      _crate: _crateFile.encode(),
      'assets/scenes/yard.scene.json': jsonEncode({
        'version': SceneFormat.current,
        'name': 'yard',
        'mode': '2d',
        'entities': [
          {'name': 'Yard', 'parentName': null, 'components': [_transform(0, 0)]},
          {
            'name': 'Crate 1',
            'parentName': 'Yard',
            'prefab': {
              'path': _crate,
              'overrides': [
                {'target': 'box', 'component': 'TagComponent', 'field': 'tags', 'value': ['crate', 'heavy']},
              ],
              'names': {'lid': 'Open lid'},
            },
          },
          {
            'name': 'Coin',
            'parentName': 'Crate 1',
            'parentTarget': 'lid',
            'components': [_transform(0, -20)],
          },
        ],
      }),
    });
    final made = await SceneLoader.loadAsset(world, 'assets/scenes/yard.scene.json');
    expect(made.map((e) => e.name), ['Yard', 'Crate 1', 'Open lid', 'Coin']);

    final crate = named('Crate 1'), lid = named('Open lid'), coin = named('Coin');
    expect(crate.getComponent<ParentComponent>()!.parentId, named('Yard').id);
    expect(lid.getComponent<ParentComponent>()!.parentId, crate.id);
    expect(coin.getComponent<ParentComponent>()!.parentId, lid.id, reason: 'under the lid inside the instance');
    expect(crate.getComponent<TagComponent>()!.tags, containsAll(['crate', 'heavy']));

    final instance = crate.getComponent<PrefabInstanceComponent>()!;
    expect(instance.path, _crate);
    expect(instance.block.names, {'lid': 'Open lid'});
    expect(lid.getComponent<PrefabLink>()!.instance, crate.id);
    expect(lid.getComponent<PrefabLink>()!.path, 'lid');
    expect(coin.getComponent<PrefabLink>(), isNull, reason: 'the scene\'s own');
  });

  test('an instance moved in the scene carries what is inside it', () {
    world = worldWith({});
    world.context.overrideLoaders(prefabs: (_) async => _crateFile);
    return PrefabLibrary.of(world.context).load(_crate).then((_) {
      SceneLoader.load(world, {
        'version': SceneFormat.current,
        'entities': [
          {
            'name': 'Moved',
            'prefab': {
              'path': _crate,
              'overrides': [
                {'target': 'box', 'component': 'TransformComponent', 'field': 'position', 'value': {'x': 100.0, 'y': 50.0, 'z': 0.0}},
                {'target': 'lid', 'component': 'TransformComponent', 'field': 'position', 'value': {'x': 5.0, 'y': -10.0, 'z': 0.0}},
              ],
            },
          },
        ],
      });
      expect([at(named('Moved')).x, at(named('Moved')).y], [100, 50]);
      expect([at(named('Lid')).x, at(named('Lid')).y], [105, 40], reason: 'its own change is against the top, in the prefab');
    });
  });

  test('a spawner places a prefab at the spawn point, the rest along with it', () async {
    world = worldWith({_crate: _crateFile.encode()});
    await PrefabLibrary.of(world.context).load(_crate);
    final point = world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 50, 0)),
      SpawnComponent(spawner: 'crate'),
    ], name: 'CrateSpawn');
    SpawnPoints.spawnAll(world, [Spawner.prefab(id: 'crate', path: _crate)]);
    final box = world.entities.firstWhere((e) => e.name == 'Crate');
    expect([at(box).x, at(box).y], [100, 50]);
    final lid = world.entities.firstWhere((e) => e.name == 'Lid');
    expect([at(lid).x, at(lid).y], [100, 40], reason: 'still 10 px above it');
    expect(point.isAlive, isTrue);
  });

  test('a prefab not read stands empty, keeping its instance', () {
    world = worldWith({});
    final made = SceneLoader.load(world, {
      'version': SceneFormat.current,
      'entities': [
        {'name': 'Ghost', 'prefab': {'path': 'assets/prefabs/ghost.prefab.json', 'removed': ['x']}},
      ],
    });
    final ghost = made.single;
    final instance = ghost.getComponent<PrefabInstanceComponent>()!;
    expect(instance.missing, isTrue);
    expect(instance.block.removed, ['x'], reason: 'kept, to save as it was');
    expect(() => PrefabLibrary.of(world.context).instantiate(world, 'assets/prefabs/ghost.prefab.json'), throwsStateError);
  });

  test('an editor points the prefab seam at its own files, and back', () async {
    world = worldWith({});
    final read = <String>[];
    final override = world.context.overrideLoaders(
      prefabs: (path) async {
        read.add(path);
        return _crateFile;
      },
    );
    final file = await PrefabLibrary.of(world.context).load(_crate);
    expect(file.name, 'Crate');
    expect(read, [_crate]);
    override.restore();
    PrefabLibrary.of(world.context).reload(_crate);
    expect(() => PrefabLibrary.of(world.context).load(_crate), throwsA(anything), reason: 'the bundle has none');
  });

  test('a prefab written in an older scene format is brought up to date', () async {
    final old = PrefabFile(
      name: 'Old',
      sceneFormat: 8,
      entities: [
        PrefabEntity(
          id: 'r',
          name: 'Body',
          components: [
            _transform(0, 0),
            {'type': 'PhysicsBodyComponent', 'fields': {'shape': 'rectangle', 'width': 10, 'height': 10}},
          ],
        ),
      ],
    );
    world = worldWith({'assets/prefabs/old.prefab.json': old.encode()});
    final file = await PrefabLibrary.of(world.context).load('assets/prefabs/old.prefab.json');
    final types = file.root.components.map((c) => c['type']);
    expect(types, containsAll(['RigidBody2D', 'Collider2D']));
    expect(types, isNot(contains('PhysicsBodyComponent')));
  });
}
