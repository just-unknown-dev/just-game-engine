// Map files, tilesets and images that will not load: reported once with
// their path, not read again every frame, not failing a level's start; and
// loads that finish late not overwriting what replaced them.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Images extends SpriteAssetLoader {
  _Images(this.image, {this.missing = const {}});
  final ui.Image image;
  final Set<String> missing;
  final List<String> asked = [];

  @override
  Future<ui.Image> loadImage(String path) async {
    asked.add(path);
    if (missing.contains(path)) throw StateError('no image $path');
    return image;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

TilesetData _tileset({String name = 'grass', String image = 'assets/t.png'}) =>
    TilesetData(
      name: name,
      image: image,
      imageWidth: 32,
      imageHeight: 32,
      tileWidth: 16,
      tileHeight: 16,
      columns: 2,
      tileCount: 4,
    );

LevelMapData _map(String tileset) {
  final m = LevelMapData(tileWidth: 16, tileHeight: 16)..addTileset(tileset);
  m.addLayer(name: 'Ground').cells.setCell(0, 0, TileCell.make(0, 0));
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late ui.Image image;
  late List<String> logged;
  final files = <String, String>{};
  final reads = <String, int>{};

  setUpAll(() async => image = await createTestImage(width: 32, height: 32));

  setUp(() {
    world = World()..initialize();
    files.clear();
    reads.clear();
    logged = [];
    world.context.tiles.log = logged.add;
    world.context.tiles.readText = (path) async {
      reads[path] = (reads[path] ?? 0) + 1;
      return files[path] ?? (throw StateError('no file $path'));
    };
    world.context.sprites = _Images(image);
    files['assets/t.tileset.json'] = jsonEncode(_tileset().toJson());
    registerLevelMapSystems(world);
  });

  tearDown(() {
    world.dispose();
  });

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      world.update(1 / 60);
      await pumpEventQueue();
    }
  }

  group('a map file that will not load', () {
    const missing = 'assets/maps/missing.map.json';

    test('is read once and reported once, frame after frame, with no '
        'unhandled errors', () async {
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: missing),
      ]);
      await frames(60);
      expect(reads[missing], 1);
      expect(logged, hasLength(1));
      expect(logged.single, contains(missing));
      expect(e.getComponent<LevelMapComponent>()!.runtime, isNull);
      expect(world.context.tiles.failureOf(missing), isA<StateError>());
    });

    test('is read again once reloaded, and then shows', () async {
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: missing),
      ]);
      await frames(3);
      files[missing] = jsonEncode(_map('assets/t.tileset.json').toJson());
      world.getSystem<LevelMapSystem>()!.reload(missing);
      await frames(3);
      expect(reads[missing], 2);
      expect(e.getComponent<LevelMapComponent>()!.runtime, isNotNull);
      expect(world.context.tiles.failureOf(missing), isNull);
    });

    test('fails again at once when asked for again, until evicted', () async {
      await expectLater(world.context.tiles.map(missing), throwsStateError);
      await expectLater(world.context.tiles.map(missing), throwsStateError);
      expect(reads[missing], 1);
      world.context.tiles.evict(missing);
      await expectLater(world.context.tiles.map(missing), throwsStateError);
      expect(reads[missing], 2);
      expect(logged, hasLength(2), reason: 'reported again once evicted');
    });

    test('does not stop preload: the rest load, and it is returned', () async {
      files['assets/maps/good.map.json'] = jsonEncode(
        _map('assets/t.tileset.json').toJson(),
      );
      final good = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/good.map.json'),
      ]);
      final bad = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: missing),
      ]);
      final failures = await LevelMaps.preload(world);
      expect(failures, hasLength(1));
      expect(failures.single.entity, same(bad));
      expect(failures.single.path, missing);
      expect(failures.single.error, isA<StateError>());
      expect(LevelMaps.of(world, good), isNotNull);
      expect(await world.getSystem<LevelMapSystem>()!.preload(), hasLength(1));
    });
  });

  test('a tileset that will not load is reported once; the map still loads '
      'without its tiles', () async {
    files['assets/maps/a.map.json'] = jsonEncode(
      _map('assets/gone.tileset.json').toJson(),
    );
    final e = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(mapPath: 'assets/maps/a.map.json'),
    ]);
    expect(await LevelMaps.preload(world), isEmpty);
    final rt = e.getComponent<LevelMapComponent>()!.runtime!;
    expect(rt.tilesetsReady, isTrue);
    expect(rt.tilesetAt(0), isNull);
    // Something else changes in TileAssets: the runtime looks again.
    world.context.tiles.putTileset('assets/other.tileset.json', _tileset());
    await frames(5);
    expect(reads['assets/gone.tileset.json'], 1);
    expect(logged, hasLength(1));
    expect(logged.single, contains('assets/gone.tileset.json'));
  });

  test('a tileset image that will not load is reported once, with its '
      'path', () async {
    files['assets/t.tileset.json'] = jsonEncode(
      _tileset(image: 'assets/gone.png').toJson(),
    );
    world.context.sprites = _Images(image, missing: {'assets/gone.png'});
    final m = _map('assets/t.tileset.json');
    world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: m),
    ]);
    await frames(2);
    world.context.tiles.putTileset('assets/other.tileset.json', _tileset());
    await frames(2);
    expect(logged, hasLength(1));
    expect(logged.single, contains('assets/gone.png'));
  });

  group('a load that finishes late', () {
    late Map<String, Completer<String>> pending;

    setUp(() {
      pending = {};
      world.context.tiles.readText = (path) {
        final c = Completer<String>();
        pending[path] = c;
        return c.future;
      };
    });

    test('after its map was evicted and read again, does not replace the '
        'newer map', () async {
      const path = 'assets/maps/a.map.json';
      final first = world.context.tiles.map(path);
      final older = pending[path]!;
      world.context.tiles.evict(path);
      final second = world.context.tiles.map(path);
      final newer = LevelMapData(tileWidth: 8, tileHeight: 8);
      pending[path]!.complete(jsonEncode(newer.toJson()));
      await second;
      older.complete(jsonEncode(LevelMapData(tileWidth: 64).toJson()));
      await first;
      expect(world.context.tiles.loadedMap(path)!.tileWidth, 8);
    });

    test('after its tileset was put, does not replace the one put — in '
        'TileAssets or in the runtime', () async {
      const path = 'assets/t.tileset.json';
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)..addTileset(path);
      final rt = LevelMapRuntime(base: m, source: m, context: world.context);
      final firstSync = rt.syncAssets();
      final older = pending[path]!;
      final put = _tileset(name: 'put');
      world.context.tiles.putTileset(path, put);
      await rt.syncAssets();
      expect(rt.tilesetAt(0), same(put));
      older.complete(jsonEncode(_tileset(name: 'stale').toJson()));
      await firstSync;
      expect(rt.tilesetAt(0)!.name, 'put');
      expect(world.context.tiles.loadedTileset(path)!.name, 'put');
    });
  });

  group('letting go of what is not used', () {
    setUp(() {
      files
        ..['assets/a.tileset.json'] = jsonEncode(_tileset(name: 'a').toJson())
        ..['assets/b.tileset.json'] = jsonEncode(_tileset(name: 'b').toJson())
        ..['assets/maps/a.map.json'] = jsonEncode(
          _map('assets/a.tileset.json').toJson(),
        )
        ..['assets/maps/b.map.json'] = jsonEncode(
          _map('assets/b.tileset.json').toJson(),
        );
    });

    test(
      'evictUnused keeps what the world uses and forgets the rest',
      () async {
        await world.context.tiles.map('assets/maps/a.map.json');
        await world.context.tiles.map('assets/maps/b.map.json');
        await world.context.tiles.tileset('assets/a.tileset.json');
        await world.context.tiles.tileset('assets/b.tileset.json');
        await expectLater(
          world.context.tiles.map('assets/maps/gone.map.json'),
          throwsA(anything),
        );
        world.createEntityWithComponents([
          TransformComponent(),
          LevelMapComponent(mapPath: 'assets/maps/a.map.json'),
        ]);
        final before = world.context.tiles.revision;
        LevelMaps.evictUnused(world);
        expect(world.context.tiles.revision, isNot(before));
        expect(
          world.context.tiles.loadedMap('assets/maps/a.map.json'),
          isNotNull,
        );
        expect(
          world.context.tiles.loadedTileset('assets/a.tileset.json'),
          isNotNull,
        );
        expect(world.context.tiles.loadedMap('assets/maps/b.map.json'), isNull);
        expect(
          world.context.tiles.loadedTileset('assets/b.tileset.json'),
          isNull,
        );
        expect(
          world.context.tiles.failureOf('assets/maps/gone.map.json'),
          isNull,
        );

        final again = world.context.tiles.revision;
        LevelMaps.evictUnused(world);
        expect(
          world.context.tiles.revision,
          again,
          reason: 'nothing left to forget',
        );
      },
    );

    test("a Tiled map's own tilesets stay while the map does", () {
      world.context.tiles.putMap('assets/maps/t.tmx', LevelMapData());
      world.context.tiles.putTileset('assets/maps/t.tmx#0', _tileset());
      world.context.tiles.retainOnly({'assets/maps/t.tmx'});
      expect(
        world.context.tiles.loadedTileset('assets/maps/t.tmx#0'),
        isNotNull,
      );
      world.context.tiles.retainOnly({});
      expect(world.context.tiles.loadedMap('assets/maps/t.tmx'), isNull);
      expect(world.context.tiles.loadedTileset('assets/maps/t.tmx#0'), isNull);
    });
  });
}
