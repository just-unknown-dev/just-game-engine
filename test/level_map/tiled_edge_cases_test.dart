// Level maps: tiles that reach out of their cells drawn back to front on
// orthogonal maps, turned collision shapes from Tiled, the box around a
// staggered range, and old tilesets without columns.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

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

  group('M36: an orthogonal layer whose tiles reach out of their cells', () {
    late World world;
    late ui.Image image;

    setUpAll(() async => image = await createTestImage(width: 32, height: 32));

    setUp(() {
      world = World()..initialize();
      // Slot 0: tiles twice as tall as the grid. Slot 1: grid-sized.
      world.context.tiles
        ..putTileset(
          'assets/tall.tileset.json',
          TilesetData(
            name: 'tall',
            image: 'assets/tall.png',
            imageWidth: 32,
            imageHeight: 32,
            tileWidth: 16,
            tileHeight: 32,
            columns: 2,
            tileCount: 2,
          ),
        )
        ..putTileset(
          'assets/flat.tileset.json',
          TilesetData(
            name: 'flat',
            image: 'assets/flat.png',
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

    Future<(Entity, LevelMapRuntime)> ready(
      List<(TileCoord, int)> cells, {
      bool flatOnly = false,
    }) async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16);
      if (!flatOnly) m.addTileset('assets/tall.tileset.json');
      m.addTileset('assets/flat.tileset.json');
      final layer = m.addLayer();
      for (final (c, slot) in cells) {
        layer.cells.setCell(c.x, c.y, TileCell.make(slot, 0));
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

    Offset tall(LevelMapRuntime rt, int x, int y) =>
        rt.geometry.tileImageRect(x, y, 16, 32).topLeft;
    Offset flat(LevelMapRuntime rt, int x, int y) =>
        rt.geometry.tileImageRect(x, y, 16, 16).topLeft;

    test('draws row 0 before the tall tile of row 1 rising over it', () async {
      final (e, rt) = await ready([
        (const TileCoord(0, 0), 0),
        (const TileCoord(1, 0), 1),
        (const TileCoord(1, 1), 0),
      ]);
      // One run per tileset drew the tall tile with the first, under the
      // flat tile in row 0.
      expect(_drawn(paint(e, rt)), [
        [tall(rt, 0, 0)],
        [flat(rt, 1, 0)],
        [tall(rt, 1, 1)],
      ]);
    });

    test('draws the next chunk\'s row 0 before a tall tile at a chunk\'s '
        'last column', () async {
      final (e, rt) = await ready([
        (const TileCoord(15, 1), 0),
        (const TileCoord(16, 0), 1),
      ]);
      expect(_drawn(paint(e, rt)), [
        [flat(rt, 16, 0)],
        [tall(rt, 15, 1)],
      ]);
      // Culled to the view, still in order.
      final camera = Camera(
        viewportSize: const Size(200, 100),
        position: const Offset(256, 16),
      );
      expect(_drawn(paint(e, rt, camera: camera)), [
        [flat(rt, 16, 0)],
        [tall(rt, 15, 1)],
      ]);
    });

    test('R1: a rolled camera draws the chunk at its screen corner', () async {
      // The unturned view's left edge, less a tile, is on a chunk edge
      // (x = 0); the turned screen's corner is in the chunk to its left.
      final camera = Camera(
        viewportSize: const Size(1600, 900),
        rotation: math.pi / 4,
        position: const Offset(816, 0),
      );
      final corner = camera.screenToWorld(const Offset(10, 10));
      final m = LevelMapData(tileWidth: 16, tileHeight: 16);
      final cell = MapGeometry.of(m).cellAt(corner);
      expect(cell.x >> 4, -1);
      final (e, rt) = await ready([(cell, 0)], flatOnly: true);
      expect(_drawn(paint(e, rt, camera: camera)), [
        [flat(rt, cell.x, cell.y)],
      ]);
    });

    test('grid-sized tiles still draw a call per chunk', () async {
      final (e, rt) = await ready([
        (const TileCoord(1, 1), 0),
        (const TileCoord(0, 0), 0),
        (const TileCoord(16, 0), 0),
      ], flatOnly: true);
      expect(_drawn(paint(e, rt)), [
        [flat(rt, 0, 0), flat(rt, 1, 1)],
        [flat(rt, 16, 0)],
      ]);
    });
  });

  group('M37: a turned collision object from Tiled', () {
    TilesetData import(String objects) {
      final ts = tiled.TileMapParser.parseTileset('''
<tileset version="1.10" name="t" tilewidth="16" tileheight="16" tilecount="1" columns="1">
 <image source="t.png" width="16" height="16"/>
 <tile id="0">
  <objectgroup draworder="index">
$objects
  </objectgroup>
 </tile>
</tileset>''');
      return TiledInterop.importTileset(ts, image: 'assets/t.png')!;
    }

    List<TileShape> shapes(String objects) =>
        import(objects).tile(0)!.collision!.shapes;

    void expectPoints(List<Offset> actual, List<Offset> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i].dx, closeTo(expected[i].dx, 1e-9));
        expect(actual[i].dy, closeTo(expected[i].dy, 1e-9));
      }
    }

    test('a box becomes the turned polygon', () {
      final shape =
          shapes(
                '<object id="1" x="4" y="2" width="16" height="4" '
                'rotation="90"/>',
              ).single
              as TilePolygonShape;
      // Clockwise about (4, 2): +x points down, +y points left.
      expectPoints(shape.points, const [
        Offset(4, 2),
        Offset(4, 18),
        Offset(0, 18),
        Offset(0, 2),
      ]);
    });

    test('a polygon turns about its origin', () {
      final shape =
          shapes(
                '<object id="1" x="0" y="0" rotation="180">'
                '<polygon points="0,0 8,0 8,4"/></object>',
              ).single
              as TilePolygonShape;
      expectPoints(shape.points, const [
        Offset(0, 0),
        Offset(-8, 0),
        Offset(-8, -4),
      ]);
    });

    test('a circle moves; an ellipse becomes a polygon', () {
      final circle =
          shapes(
                '<object id="1" x="0" y="0" width="8" height="8" '
                'rotation="90"><ellipse/></object>',
              ).single
              as TileEllipseShape;
      expect(circle.bounds.center.dx, closeTo(-4, 1e-9));
      expect(circle.bounds.center.dy, closeTo(4, 1e-9));
      expect(circle.bounds.width, closeTo(8, 1e-9));

      final ellipse =
          shapes(
                '<object id="1" x="0" y="0" width="8" height="4" '
                'rotation="90"><ellipse/></object>',
              ).single
              as TilePolygonShape;
      final xs = ellipse.points.map((p) => p.dx);
      final ys = ellipse.points.map((p) => p.dy);
      expect(xs.reduce(math.min), closeTo(-4, 1e-9));
      expect(xs.reduce(math.max), closeTo(0, 1e-9));
      expect(ys.reduce(math.min), closeTo(0, 1e-9));
      expect(ys.reduce(math.max), closeTo(8, 1e-9));
    });

    test('an unturned box stays a box', () {
      final shape =
          shapes('<object id="1" x="1" y="2" width="3" height="4"/>').single
              as TileRectShape;
      expect(shape.rect, const Rect.fromLTWH(1, 2, 3, 4));
    });
  });

  group('M38: the box around a staggered or hexagonal range', () {
    for (final orientation in [
      MapOrientation.staggered,
      MapOrientation.hexagonal,
    ]) {
      for (final axis in TileStaggerAxis.values) {
        for (final index in TileStaggerIndex.values) {
          test('${orientation.name}, ${axis.name}, ${index.name}: holds every '
              'cell', () {
            final g = MapGeometry(
              orientation: orientation,
              tileWidth: 32,
              tileHeight: 16,
              staggerAxis: axis,
              staggerIndex: index,
              hexSideLength: 8,
            );
            for (final range in const [
              TileRange(0, 0, 2, 3),
              TileRange(1, 1, 4, 2),
              TileRange(-3, -2, 1, 1),
              TileRange(0, 0, 1, 1),
              TileRange(2, 5, 3, 9),
            ]) {
              Rect? all;
              for (final c in range.coords) {
                final cell = g.cellBounds(c.x, c.y);
                all = all == null ? cell : all.expandToInclude(cell);
              }
              expect(g.boundsOf(range), all, reason: '$range');
            }
          });
        }
      }
    }
  });

  group('M39: a tileset without columns or a tile count', () {
    test('works them out from its image', () {
      final ts = tiled.TileMapParser.parseTileset('''
<tileset name="old" tilewidth="16" tileheight="16" spacing="2" margin="1">
 <image source="old.png" width="70" height="35"/>
</tileset>''');
      expect(ts.columns, 0);
      final warnings = <String>[];
      final data = TiledInterop.importTileset(
        ts,
        image: 'assets/old.png',
        warn: warnings.add,
      )!;
      // (70 - 1 + 2) ~/ 18 = 3 across, (35 - 1 + 2) ~/ 18 = 2 down.
      expect(data.columns, 3);
      expect(data.tileCount, 6);
      expect(data.sourceRect(4), const Rect.fromLTWH(19, 19, 16, 16));
      expect(warnings, isEmpty);
    });

    test('says so when there is nothing to work them out from', () {
      final ts = tiled.TileMapParser.parseTileset('''
<tileset name="old" tilewidth="16" tileheight="16">
 <image source="old.png"/>
</tileset>''');
      final warnings = <String>[];
      TiledInterop.importTileset(
        ts,
        image: 'assets/old.png',
        warn: warnings.add,
      );
      expect(warnings.single, contains('"old"'));
    });
  });
}
