// What a map's runtime made is let go of when the runtime is dropped — its
// mirrored images disposed, its loads ignored — and a map with no runtime
// has no bodies left colliding.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Images extends SpriteAssetLoader {
  _Images(this.image);
  final ui.Image image;

  @override
  Future<ui.Image> loadImage(String path) async => image;

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

const _tilesetPath = 'assets/t.tileset.json';

TilesetData _tileset() =>
    TilesetData(
        name: 't',
        image: 'assets/t.png',
        imageWidth: 32,
        imageHeight: 32,
        tileWidth: 16,
        tileHeight: 16,
        columns: 2,
        tileCount: 4,
      )
      ..tileOrNew(0).collision = TileCollision.full(16, 16)
      ..tileOrNew(1).collision = TileCollision.full(16, 16);

/// A map whose `Ground` layer collides, with a solid tile and a mirrored
/// one.
LevelMapData _map() {
  final m = LevelMapData(tileWidth: 16, tileHeight: 16)
    ..addTileset(_tilesetPath);
  m.addLayer(name: 'Ground')
    ..collides = true
    ..cells.setCell(0, 0, TileCell.make(0, 0))
    ..cells.setCell(1, 0, TileCell.make(0, 1, TileCell.flipH));
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late ui.Image image;
  final files = <String, String>{};

  setUpAll(() async => image = await createTestImage(width: 32, height: 32));

  setUp(() {
    world = World()..initialize();
    world.context.tiles.log = (_) {};
    files
      ..clear()
      ..[_tilesetPath] = jsonEncode(_tileset().toJson());
    world.context.tiles.readText = (path) async =>
        files[path] ?? (throw StateError('no file $path'));
    world.context.sprites = _Images(image);
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

  Future<(LevelMapComponent, LevelMapRuntime, ui.Image)> loaded(
    LevelMapComponent c,
  ) async {
    await frames(2);
    final rt = c.runtime!;
    await rt.syncAssets();
    return (c, rt, rt.mirroredAt(0)!);
  }

  int bodies() => world.query([MapBodyComponent]).length;

  group('disposing', () {
    test('new images for a runtime dispose the mirrored ones made from the '
        'old', () async {
      final c = LevelMapComponent(inline: _map());
      world.createEntityWithComponents([TransformComponent(), c]);
      final (_, rt, mirrored) = await loaded(c);
      world.context.tiles.evict(_tilesetPath);
      await frames(1);
      await rt.syncAssets();
      expect(mirrored.debugDisposed, isTrue);
      expect(rt.isDisposed, isFalse);
    });

    test(
      'the system disposes the runtime of a map replaced in the scene',
      () async {
        final c = LevelMapComponent(inline: _map());
        world.createEntityWithComponents([TransformComponent(), c]);
        final (_, rt, mirrored) = await loaded(c);
        c.inline = _map();
        await frames(1);
        expect(rt.isDisposed, isTrue);
        expect(mirrored.debugDisposed, isTrue);
        expect(c.runtime, isNot(same(rt)));
        expect(rt.mirroredAt(0), isNull, reason: 'makes no new images');
      },
    );

    test('... of a map whose source is cleared', () async {
      final c = LevelMapComponent(inline: _map());
      world.createEntityWithComponents([TransformComponent(), c]);
      final (_, rt, _) = await loaded(c);
      c.inline = null;
      await frames(1);
      expect(rt.isDisposed, isTrue);
      expect(c.runtime, isNull);
    });

    test('... of a map whose entity is destroyed, or loses the map', () async {
      final a = LevelMapComponent(inline: _map());
      final b = LevelMapComponent(inline: _map());
      final ea = world.createEntityWithComponents([TransformComponent(), a]);
      final eb = world.createEntityWithComponents([TransformComponent(), b]);
      await frames(2);
      final ra = a.runtime!;
      final rb = b.runtime!;
      world.destroyEntity(ea);
      eb.removeComponent<LevelMapComponent>();
      await frames(1);
      expect(ra.isDisposed, isTrue);
      expect(rb.isDisposed, isTrue);
    });

    test('... but not of a map switched off, whose changes it keeps', () async {
      final c = LevelMapComponent(inline: _map());
      final e = world.createEntityWithComponents([TransformComponent(), c]);
      await frames(2);
      final rt = c.runtime!;
      e.isActive = false;
      await frames(1);
      expect(rt.isDisposed, isFalse);
      e.isActive = true;
      await frames(1);
      expect(c.runtime, same(rt));
    });

    test(
      '... and of every map, with its drawing, when the system goes',
      () async {
        final c = LevelMapComponent(inline: _map());
        final e = world.createEntityWithComponents([TransformComponent(), c]);
        final (_, rt, mirrored) = await loaded(c);
        expect(e.getComponent<RenderItemsComponent>()!.items, isNotEmpty);
        world.removeSystem(world.getSystem<LevelMapSystem>()!);
        expect(rt.isDisposed, isTrue);
        expect(mirrored.debugDisposed, isTrue);
        expect(c.runtime, isNull);
        expect(e.getComponent<RenderItemsComponent>()!.items, isEmpty);
      },
    );

    test('... and of a map file that arrives after its entity went', () async {
      final read = Completer<String>();
      world.context.tiles.readText = (path) => path == 'assets/maps/a.map.json'
          ? read.future
          : Future.value(files[path]);
      final c = LevelMapComponent(mapPath: 'assets/maps/a.map.json');
      final e = world.createEntityWithComponents([TransformComponent(), c]);
      await frames(1);
      world.destroyEntity(e);
      await frames(1);
      read.complete(jsonEncode(_map().toJson()));
      await pumpEventQueue();
      expect(c.runtime, isNull);
    });

    test('runtimeFor disposes the runtime it replaces', () async {
      files['assets/maps/a.map.json'] = jsonEncode(_map().toJson());
      final c = LevelMapComponent(inline: _map());
      final old = (await LevelMaps.runtimeFor(world, c))!;
      c.mapPath = 'assets/maps/a.map.json';
      final rt = await LevelMaps.runtimeFor(world, c);
      expect(rt, isNot(same(old)));
      expect(old.isDisposed, isTrue);
      LevelMaps.release(c);
      expect(rt!.isDisposed, isTrue);
      expect(c.runtime, isNull);
    });

    test('a load that finishes after the runtime is disposed changes '
        'nothing', () async {
      final read = Completer<String>();
      world.context.tiles.readText = (_) => read.future;
      final m = _map();
      final rt = LevelMapRuntime(base: m, source: m, context: world.context);
      final sync = rt.syncAssets();
      rt.dispose();
      read.complete(jsonEncode(_tileset().toJson()));
      await sync;
      expect(rt.tilesetsReady, isFalse);
      expect(rt.tilesetAt(0), isNull);
    });
  });

  group('bodies', () {
    test('go when the map is cleared from the scene', () async {
      final c = LevelMapComponent(inline: _map());
      world.createEntityWithComponents([TransformComponent(), c]);
      await frames(2);
      expect(bodies(), greaterThan(0));
      c.inline = null;
      await frames(2);
      expect(bodies(), 0);
    });

    test('go when a map file is reloaded and is no longer there', () async {
      files['assets/maps/a.map.json'] = jsonEncode(_map().toJson());
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/a.map.json'),
      ]);
      await LevelMaps.preload(world);
      await frames(2);
      expect(bodies(), greaterThan(0));
      files.remove('assets/maps/a.map.json');
      world.getSystem<LevelMapSystem>()!.reload('assets/maps/a.map.json');
      await frames(5);
      expect(bodies(), 0);
    });

    test('go when the map is pointed at a file that is not there', () async {
      final c = LevelMapComponent(inline: _map());
      world.createEntityWithComponents([TransformComponent(), c]);
      await frames(2);
      expect(bodies(), greaterThan(0));
      c.mapPath = 'assets/maps/nowhere.map.json';
      await frames(5);
      expect(c.runtime, isNull);
      expect(bodies(), 0);
    });
  });
}
