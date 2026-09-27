// The engine's own tileset of basic shapes: always there, drawn in code, and
// colliding exactly as it looks.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _NoFiles extends SpriteAssetLoader {
  @override
  Future<ui.Image> loadImage(String path) =>
      throw StateError('looked for a file: $path');

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ts = BuiltInTilesets.tileset(BuiltInTilesets.basicShapes)!;

  test('24 tiles of 32 pixels, 8 to a row, each with its collision', () {
    expect(ts.name, 'Basic shapes');
    expect((ts.tileCount, ts.columns, ts.tileWidth), (24, 8, 32));
    expect((ts.imageWidth, ts.imageHeight), (256, 96));
    for (var id = 0; id < ts.tileCount; id++) {
      expect(ts.tile(id)?.collision?.shapes, hasLength(1), reason: '$id');
    }
    // Ids are fixed: a map painted with them keeps its tiles.
    expect(ts.tile(0)!.collision!.isFullCell(32, 32), isTrue, reason: 'block');
    expect(ts.tile(5)!.collision!.kind, 'oneWay', reason: 'the plank');
    expect(ts.tile(8)!.collision!.shapes.single, isA<TilePolygonShape>());
    expect(ts.tile(20)!.collision!.shapes.single, isA<TileEllipseShape>());
  });

  test(
    'always there: nothing to load, nothing forgotten, nothing replaced',
    () {
      TileAssets.clear();
      expect(TileAssets.loadedTileset(BuiltInTilesets.basicShapes), same(ts));
      TileAssets.putTileset(BuiltInTilesets.basicShapes, TilesetData());
      expect(TileAssets.loadedTileset(BuiltInTilesets.basicShapes), same(ts));
      expect(TileAssets.isVirtual(BuiltInTilesets.basicShapes), isTrue);
      expect(TileAssets.isVirtual(BuiltInTilesets.basicShapesImage), isTrue);
      expect(TileAssets.isVirtual('assets/a.tileset.json'), isFalse);
    },
  );

  test('painted, it collides as it looks', () {
    final map = LevelMapData(tileWidth: 32, tileHeight: 32)
      ..addTileset(BuiltInTilesets.basicShapes);
    final cells = TileChunkStore();
    for (var x = 0; x < 3; x++) {
      cells.setCell(x, 0, TileCell.make(0, 0));
    }
    cells
      ..setCell(5, 0, TileCell.make(0, 5))
      ..setCell(8, 0, TileCell.make(0, 8))
      ..setCell(10, 0, TileCell.make(0, 20));
    final specs = TileCollisionBuilder.build(
      cells: cells,
      geometry: MapGeometry.of(map),
      tilesetAt: (slot) => slot == 0 ? ts : null,
    );
    final blocks = specs.where((s) => s.kind == 'solid' && s.isBox).toList();
    expect(blocks, hasLength(1), reason: 'a row of blocks is one body');
    expect(blocks.single.size, const ui.Size(96, 32));
    final plank = specs.singleWhere((s) => s.kind == 'oneWay');
    expect(plank.size, const ui.Size(32, 8));
    expect(
      specs.where((s) => s.polygon != null),
      isNotEmpty,
      reason: 'the slope and the circle',
    );
  });

  test('a map draws it from the picture the engine makes', () async {
    SpriteAssets.loader = _NoFiles();
    addTearDown(() => SpriteAssets.loader = BundleSpriteAssetLoader());
    final data = LevelMapData()..addTileset(BuiltInTilesets.basicShapes);
    final rt = LevelMapRuntime(base: data, source: data);
    await rt.syncAssets();
    final image = rt.imageAt(0)!;
    expect((image.width, image.height), (256, 96));
    expect(
      BuiltInTilesets.image(BuiltInTilesets.basicShapesImage),
      same(image),
      reason: 'drawn once',
    );
  });
}
