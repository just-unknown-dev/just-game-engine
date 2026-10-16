// Chunks the engine cannot read survive a save; a layer's tiles are drawn
// chunk by chunk in the same order as before, culled to the view, with the
// running game's changes in place of the chunks they changed.

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

/// Where each tile an atlas call draws has its top-left, call by call.
List<List<Offset>> _drawn(_Recorder canvas) => [
  for (final call in canvas.atlases)
    [
      for (
        var i = 0;
        i < (call.positionalArguments[1] as Float32List).length;
        i += 4
      )
        Offset(
          (call.positionalArguments[1] as Float32List)[i + 2],
          (call.positionalArguments[1] as Float32List)[i + 3],
        ),
    ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an unreadable chunk', () {
    const bad = 'not a chunk';
    final good = (TileChunkStore()..setCell(0, 0, TileCell.make(0, 1)))
        .toJson()
        .values
        .single;

    test('is kept and saved back as it was', () {
      final store = TileChunkStore.fromJson({'0,0': good, '1,0': bad});
      expect(store.cellAt(0, 0), TileCell.make(0, 1));
      expect(store.unreadableChunks, ['1,0']);
      expect(store.toJson(), {'0,0': good, '1,0': bad});
      expect(store.copy().toJson(), {'0,0': good, '1,0': bad});
    });

    test('... through a whole map, too', () {
      final json = {
        'format': 1,
        'layers': [
          {
            'id': 1,
            'name': 'A',
            'cells': {'0,0': good, '2,2': bad, 'x,y': 'odd key'},
          },
        ],
      };
      final again = LevelMapData.fromJson(json).toJson();
      expect((again['layers'] as List).single['cells'], {
        '0,0': good,
        '2,2': bad,
        'x,y': 'odd key',
      });
    });

    test('is replaced by a chunk painted in its place, and gone once the '
        'layer is cleared', () {
      final store = TileChunkStore.fromJson({'1,0': bad, '3,3': bad});
      store.setCell(17, 0, TileCell.make(0, 2));
      expect(store.unreadableChunks, ['3,3']);
      expect(store.toJson().keys, ['1,0', '3,3']);
      expect(store.toJson()['1,0'], isNot(bad));
      store.clear();
      expect(store.toJson(), isEmpty);
    });

    test("an overlay saves its base's, less those it painted over", () {
      final base = TileChunkStore.fromJson({'1,0': bad, '3,3': bad});
      final over = TileChunkStore.over(base)..setCell(17, 0, 1);
      expect(over.toJson().keys, containsAll(['1,0', '3,3']));
      expect(over.toJson()['1,0'], isNot(bad));
      expect(over.copy().unreadableChunks, ['3,3']);
    });
  });

  group('chunk bounds', () {
    test('span own chunks and those read through to', () {
      final base = TileChunkStore()
        ..setCell(0, 0, 1)
        ..setCell(40, -20, 1);
      expect(base.chunkBounds, (cx0: 0, cy0: -2, cx1: 3, cy1: 1));
      final over = TileChunkStore.over(base)..setCell(-1, 33, 1);
      expect(over.chunkBounds, (cx0: -1, cy0: -2, cx1: 3, cy1: 3));
      expect(TileChunkStore().chunkBounds, isNull);
      expect(TileChunkStore.over(TileChunkStore()).chunkBounds, isNull);
    });
  });

  group('drawing order', () {
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

    tearDown(() {
      world.dispose();
    });

    /// Chunks (-1, -1), (2, -1), (0, 0), (1, 0), (0, 1), one tile each.
    const cells = [
      TileCoord(-16, -16),
      TileCoord(32, -16),
      TileCoord(0, 0),
      TileCoord(16, 0),
      TileCoord(0, 16),
    ];

    Future<(Entity, LevelMapRuntime)> ready(
      MapOrientation orientation, {
      List<TileCoord> at = cells,
    }) async {
      final m = LevelMapData(
        orientation: orientation,
        tileWidth: 16,
        tileHeight: 16,
        hexSideLength: 8,
      )..addTileset('assets/t.tileset.json');
      final layer = m.addLayer();
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
      return (e, rt);
    }

    /// Draws [e]'s one layer, with [camera] or with no view at all.
    _Recorder paint(Entity e, LevelMapRuntime rt, {Camera? camera}) {
      final canvas = _Recorder();
      rt.painter.paint(
        canvas,
        RenderContext(world: world, size: const Size(400, 300), camera: camera),
        e,
        rt.base.layers.single.id,
      );
      return canvas;
    }

    Offset topLeft(LevelMapRuntime rt, TileCoord c) =>
        rt.geometry.tileImageRect(c.x, c.y, 16, 16).topLeft;

    test('orthogonal: a call per chunk, row by row, left to right', () async {
      final (e, rt) = await ready(MapOrientation.orthogonal);
      final expected = [
        for (final c in cells) [topLeft(rt, c)],
      ];
      expect(_drawn(paint(e, rt)), expected);
      final wide = Camera(viewportSize: const Size(4000, 4000));
      expect(_drawn(paint(e, rt, camera: wide)), expected);
    });

    test('isometric: diagonal by diagonal, each left to right', () async {
      final (e, rt) = await ready(MapOrientation.isometric);
      // By cx + cy, then cx: (-1, -1), (0, 0), then (0, 1), (1, 0), (2, -1).
      final order = [
        const TileCoord(-16, -16),
        const TileCoord(0, 0),
        const TileCoord(0, 16),
        const TileCoord(16, 0),
        const TileCoord(32, -16),
      ];
      expect(_drawn(paint(e, rt)), [
        for (final c in order) [topLeft(rt, c)],
      ]);
    });

    for (final orientation in [
      MapOrientation.staggered,
      MapOrientation.hexagonal,
    ]) {
      test(
        '${orientation.name}: a call per row of chunks, back to front',
        () async {
          final (e, rt) = await ready(orientation);
          final bands = <int, List<TileCoord>>{};
          for (final c in cells) {
            bands.putIfAbsent(c.y >> 4, () => []).add(c);
          }
          final expected = [
            for (final cy in bands.keys.toList()..sort())
              [
                for (final c in bands[cy]!..sort(rt.geometry.compareDrawOrder))
                  topLeft(rt, c),
              ],
          ];
          expect(_drawn(paint(e, rt)), expected);
        },
      );
    }

    test('only chunks in view are drawn; far apart, they still are in '
        'order', () async {
      final far = [
        const TileCoord(0, 0),
        const TileCoord(4000, 0),
        const TileCoord(0, 4000),
      ];
      final (e, rt) = await ready(MapOrientation.orthogonal, at: far);
      expect(_drawn(paint(e, rt)), [
        for (final c in far..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x))
          [topLeft(rt, c)],
      ]);
      final near = Camera(viewportSize: const Size(400, 300));
      expect(_drawn(paint(e, rt, camera: near)), [
        [topLeft(rt, const TileCoord(0, 0))],
      ]);
    });

    test(
      "the game's changes are drawn in place of the chunk they changed",
      () async {
        final (e, rt) = await ready(MapOrientation.orthogonal);
        final h = LevelMaps.of(world, e)!;
        h.setTile(
          h.map.layers.single,
          const TileCoord(1, 0),
          TileCell.make(0, 1),
        );
        final drawn = _drawn(paint(e, rt));
        expect(drawn, hasLength(cells.length));
        expect(drawn[2], [
          topLeft(rt, const TileCoord(0, 0)),
          const Offset(16, 0),
        ]);
      },
    );

    test('an empty layer draws nothing and builds nothing', () async {
      final (e, rt) = await ready(MapOrientation.orthogonal, at: const []);
      final canvas = paint(e, rt);
      expect(canvas.calls, isEmpty);
    });

    test('layers look their ids up in an index that follows the list', () {
      final m = LevelMapData();
      final a = m.addLayer();
      final b = m.addLayer();
      expect(m.indexOfLayer(b.id), 1);
      // Reordered without a touch: still right.
      m.layers
        ..clear()
        ..addAll([b, a]);
      expect(m.indexOfLayer(b.id), 0);
      expect(m.layerById(a.id), same(a));
      expect(m.indexOfLayer(99), -1);
    });
  });

  test(
    'a mirrored-image picture keeps drawing after its picture is let go',
    () async {
      final image = await createTestImage(width: 32, height: 32);
      final ts = TilesetData(
        name: 't',
        image: 'assets/t.png',
        imageWidth: 32,
        imageHeight: 32,
        tileWidth: 16,
        tileHeight: 16,
        columns: 2,
        tileCount: 4,
      );
      final context = EngineContext();
      addTearDown(context.dispose);
      context.tiles.putTileset('assets/t.tileset.json', ts);
      context.sprites = _Images(image);
      final m = LevelMapData()..addTileset('assets/t.tileset.json');
      final rt = LevelMapRuntime(base: m, source: m, context: context);
      await rt.syncAssets();
      final mirrored = rt.mirroredAt(0)!;
      expect(mirrored.width, 32);
      expect(await mirrored.toByteData(), isNotNull);
      final builtIn = context.tiles.builtInImage(
        BuiltInTilesets.basicShapesImage,
      )!;
      expect(await builtIn.toByteData(), isNotNull);
      rt.dispose();
      expect(mirrored.debugDisposed, isTrue);
    },
  );
}
