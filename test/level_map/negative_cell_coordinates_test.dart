// Cells at negative coordinates — left of or above a map's origin — land in
// the right chunk and are drawn, on every platform.
//
// On the web (dart2js) `>>` on a negative int gives an unsigned 32-bit
// number (`-1 >> 4` is 4294967295), so chunk arithmetic must not shift
// coordinates. The VM passes these either way; run this file with
// `flutter test --platform chrome` to check the web.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records every draw call instead of drawing.
class _Recorder implements Canvas {
  final List<Invocation> calls = [];

  List<Invocation> get atlases =>
      calls.where((c) => c.memberName == #drawRawAtlas).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return null;
  }
}

class _Images extends SpriteAssetLoader {
  _Images(this.image);
  final ui.Image image;

  @override
  Future<ui.Image> loadImage(String path) async => image;

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

/// How many tiles the atlas calls on [canvas] draw.
int _tiles(_Recorder canvas) => canvas.atlases.fold(
  0,
  (n, call) => n + (call.positionalArguments[1] as Float32List).length ~/ 4,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the chunk of a cell is its coordinate floor-divided by 16', () {
    const cases = {
      0: 0,
      15: 0,
      16: 1,
      -1: -1,
      -15: -1,
      -16: -1,
      -17: -2,
      -32: -2,
      -33: -3,
      -300: -19,
      -524288: -32768,
      524287: 32767,
    };
    for (final MapEntry(key: v, value: chunk) in cases.entries) {
      expect(TileChunkStore.chunkIndexOf(v), chunk, reason: 'cell $v');
    }
  });

  test('a cell left of and above the origin is stored in its own chunk, '
      'read back, bounded and saved under that chunk', () {
    final store = TileChunkStore()
      ..setCell(-1, -17, TileCell.make(0, 3))
      ..setCell(-16, -1, TileCell.make(0, 4))
      ..setCell(5, 2, TileCell.make(0, 5));
    expect(store.cellAt(-1, -17), TileCell.make(0, 3));
    expect(store.cellAt(-16, -1), TileCell.make(0, 4));
    expect(store.cellAt(5, 2), TileCell.make(0, 5));
    expect(store.cellAt(-2, -17), TileCell.empty);

    final chunks = {for (final c in store.chunks) (c.cx, c.cy)};
    expect(chunks, {(-1, -2), (-1, -1), (0, 0)});
    expect(store.chunk(-1, -2), isNotNull);
    expect(store.chunkBounds, (cx0: -1, cy0: -2, cx1: 1, cy1: 1));
    expect(store.cells.toSet(), {
      (-1, -17, TileCell.make(0, 3)),
      (-16, -1, TileCell.make(0, 4)),
      (5, 2, TileCell.make(0, 5)),
    });
    expect(store.usedBounds, const Rect.fromLTRB(-16, -17, 6, 3));

    final json = store.toJson();
    expect(json.keys, ['-1,-2', '-1,-1', '0,0']);
    final again = TileChunkStore.fromJson(json);
    expect(again.cellAt(-1, -17), TileCell.make(0, 3));
    expect(again.cellAt(-16, -1), TileCell.make(0, 4));
    expect(again.chunkBounds, store.chunkBounds);
  });

  test('an overlay copies the negative chunk it writes to', () {
    final base = TileChunkStore()..setCell(-20, -20, TileCell.make(0, 1));
    final over = TileChunkStore.over(base)..setCell(-21, -20, 7);
    expect(over.cellAt(-20, -20), TileCell.make(0, 1));
    expect(over.cellAt(-21, -20), 7);
    expect(base.cellAt(-21, -20), TileCell.empty);
    expect(over.chunkBounds, (cx0: -2, cy0: -2, cx1: -1, cy1: -1));
  });

  group('a layer around the origin', () {
    late World world;
    late ui.Image image;

    setUpAll(() async => image = await createTestImage(width: 32, height: 32));

    setUp(() {
      world = World()..initialize();
      world.context.tiles.putTileset(
        'assets/t.tileset.json',
        TilesetData(
          name: 't',
          image: 'assets/t.png',
          imageWidth: 32,
          imageHeight: 32,
          tileWidth: 16,
          tileHeight: 16,
          columns: 2,
          tileCount: 4,
        ),
      );
      world.context.sprites = _Images(image);
      registerLevelMapSystems(world, collision: false);
    });

    tearDown(() => world.dispose());

    for (final orientation in LevelMapOrientation.values) {
      test('is drawn by a camera whose view crosses 0 '
          '(${orientation.name})', () async {
        final m = LevelMapData(
          orientation: orientation,
          tileWidth: 16,
          tileHeight: 16,
          hexSideLength: 8,
        )..addTileset('assets/t.tileset.json');
        final layer = m.addLayer();
        const at = [
          TileCoord(0, 0),
          TileCoord(1, 1),
          TileCoord(-1, -1),
          TileCoord(-2, 1),
          TileCoord(1, -2),
        ];
        for (final c in at) {
          layer.cells.setCell(c.x, c.y, TileCell.make(0, 0));
        }
        final e = world.createEntityWithComponents([
          TransformComponent(),
          LevelMapComponent(inline: m),
        ]);
        world.update(0);
        final rt = e.getComponent<LevelMapComponent>()!.runtime!;
        await rt.syncAssets();

        // Looking at the origin: the view starts left of and above cell 0.
        expect(_tiles(_paint(world, e, layer.id, Offset.zero)), at.length);
      });
    }

    test('is drawn when the view starts less than a tile left of and above '
        'its first cell', () async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      final layer = m.addLayer();
      for (var x = 0; x < 4; x++) {
        layer.cells.setCell(x, 0, TileCell.make(0, 0));
      }
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: m),
      ]);
      world.update(0);
      await e.getComponent<LevelMapComponent>()!.runtime!.syncAssets();
      // The view's top-left is (10, 10); widened by a tile, (-6, -6): cell
      // range from -1.
      expect(_tiles(_paint(world, e, layer.id, const Offset(210, 160))), 4);
    });
  });
}

/// Draws layer [layerId] of the map on [e] as a 400 × 300 camera at
/// [position] sees it.
_Recorder _paint(World world, Entity e, int layerId, Offset position) {
  final canvas = _Recorder();
  e.getComponent<LevelMapComponent>()!.runtime!.painter.paint(
    canvas,
    RenderContext(
      world: world,
      size: const Size(400, 300),
      camera: OutputCamera(
        position: position,
        viewportSize: const Size(400, 300),
      ),
    ),
    e,
    layerId,
  );
  return canvas;
}
