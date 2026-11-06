// Between levels: Engine.releaseUnused lets go of what only the level left
// behind used — its map files and tilesets, the images they drew from, its
// 2-D material files and the images those named — and keeps what the next
// level uses too. (Graphics3D's part is in render_upkeep_test.dart.)

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Hands out a clone of one image for any path, the caller's to dispose,
/// and remembers what it is told to forget.
class _Images extends SpriteAssetLoader {
  _Images(this.image);
  final ui.Image image;
  final List<String> evicted = [];

  @override
  bool get callerDisposesImages => true;

  @override
  Future<ui.Image> loadImage(String path) async => image.clone();

  @override
  void evict(String path) => evicted.add(path);

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

String _tileset(String name) => jsonEncode(
  TilesetData(
    name: name,
    image: 'assets/$name.png',
    imageWidth: 32,
    imageHeight: 32,
    tileWidth: 16,
    tileHeight: 16,
    columns: 2,
    tileCount: 4,
  ).toJson(),
);

/// A map drawn from the tileset [name], its one layer through [material].
String _map(String name, {String material = ''}) {
  final map = LevelMapData(tileWidth: 16, tileHeight: 16)
    ..addTileset('assets/$name.tileset.json');
  map.addLayer(name: 'Ground')
    ..material = material
    ..cells.setCell(0, 0, TileCell.make(0, 0));
  return jsonEncode(map.toJson());
}

String _material(String normals) => '{"normalMap": {"map": "$normals"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image image;
  setUpAll(() async => image = await createTestImage(width: 32, height: 32));

  test('after a level change, what only the old level used goes and what '
      'both use stays', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final world = engine.world;
    final context = engine.context;
    final files = {
      'assets/old.tileset.json': _tileset('old'),
      'assets/both.tileset.json': _tileset('both'),
      'assets/maps/old.map.json': _map(
        'old',
        material: 'water.material2d.json',
      ),
      'assets/maps/both.map.json': _map('both'),
      'old.material2d.json': _material('assets/old_n.png'),
      'both.material2d.json': _material('assets/both_n.png'),
      'water.material2d.json': _material('assets/water_n.png'),
    };
    Future<String> read(String path) async =>
        files[path] ?? (throw StateError('no $path'));
    context.tiles.readText = read;
    context.material2DText = read;
    final images = _Images(image);
    context.sprites = images;
    final library = context.material2DLibrary;

    /// A level of [maps] and of sprites drawn through [materials], loaded
    /// and drawn once: its materials read, with the images they name.
    Future<void> level(List<String> maps, List<String> materials) async {
      world.destroyAllEntities();
      for (final map in maps) {
        world.createEntityWithComponents([
          TransformComponent(),
          LevelMapComponent(mapPath: 'assets/maps/$map.map.json'),
        ]);
      }
      for (final material in materials) {
        world.createEntityWithComponents([
          TransformComponent(),
          Material2DComponent(material: material),
        ]);
      }
      expect(await LevelMaps.preload(world), isEmpty);
      final drawn = {...materials, ...LevelMaps.materialsIn(world)};
      drawn.forEach(library.fileOf);
      await pumpEventQueue();
      for (final path in drawn) {
        library.imageOf(library.fileOf(path)!.text('normalMap.map'));
      }
      await pumpEventQueue();
    }

    await level(
      ['old', 'both'],
      ['old.material2d.json', 'both.material2d.json'],
    );
    final oldNormals = library.imageOf('assets/old_n.png')!;
    final waterNormals = library.imageOf('assets/water_n.png')!;
    final bothNormals = library.imageOf('assets/both_n.png')!;

    await level(['both'], ['both.material2d.json']);
    engine.releaseUnused();

    final tiles = context.tiles;
    expect(tiles.loadedMap('assets/maps/old.map.json'), isNull);
    expect(tiles.loadedTileset('assets/old.tileset.json'), isNull);
    expect(tiles.loadedMap('assets/maps/both.map.json'), isNotNull);
    expect(tiles.loadedTileset('assets/both.tileset.json'), isNotNull);
    expect(images.evicted.toSet(), {
      'assets/old.png',
      'assets/old_n.png',
      'assets/water_n.png',
    }, reason: 'the old tileset image and the old materials\' normal maps');
    expect(oldNormals.debugDisposed, isTrue);
    expect(waterNormals.debugDisposed, isTrue, reason: "an old map layer's");
    expect(bothNormals.debugDisposed, isFalse);
    expect(library.imageOf('assets/both_n.png'), same(bothNormals));
    expect(library.fileOf('both.material2d.json'), isNotNull);
    expect(library.fileOf('old.material2d.json'), isNull, reason: 'forgotten');

    // A second call has nothing left to let go of.
    images.evicted.clear();
    engine.releaseUnused();
    expect(images.evicted, isEmpty);
    expect(tiles.loadedMap('assets/maps/both.map.json'), isNotNull);
  });

  test('before the engine is ready there is no world to look at', () {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.releaseUnused, throwsA(isA<EngineNotReadyError>()));
  });
}
