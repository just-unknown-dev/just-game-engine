// How a map layer is drawn: batches rebuilt only where something changed
// (a hidden cell, a tile), tiles drawn back to front where they overlap
// their neighbours — and only those in view — tileset offsets and the
// parallax origin taken into account, and a layer drawn through a 2-D
// material made once and drawn again with only the time moved on.

import 'dart:convert';
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

  List<ui.Vertices> get vertices => [
    for (final c in calls)
      if (c.memberName == #drawVertices)
        c.positionalArguments[0] as ui.Vertices,
  ];

  /// The shaders the vertices were drawn through.
  List<ui.Shader> get shaders => [
    for (final c in calls)
      if (c.memberName == #drawVertices)
        (c.positionalArguments[2] as Paint).shader!,
  ];

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

/// Each atlas call's transforms list.
List<Float32List> _transforms(_Recorder canvas) => [
  for (final call in canvas.atlases) call.positionalArguments[1] as Float32List,
];

/// Where each tile the atlas calls draw has its translation, in order.
List<Offset> _drawn(_Recorder canvas) => [
  for (final t in _transforms(canvas))
    for (var i = 0; i < t.length; i += 4) Offset(t[i + 2], t[i + 3]),
];

TilesetData _tileset({
  int tileWidth = 16,
  int tileHeight = 16,
  double offsetX = 0,
  double offsetY = 0,
}) => TilesetData(
  name: 't',
  image: 'assets/t.png',
  imageWidth: tileWidth * 2,
  imageHeight: tileHeight * 2,
  tileWidth: tileWidth,
  tileHeight: tileHeight,
  columns: 2,
  tileCount: 4,
  tileOffsetX: offsetX,
  tileOffsetY: offsetY,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late ui.Image image;

  setUpAll(() async => image = await createTestImage(width: 128, height: 128));

  setUp(() {
    world = World(extensions: [BuiltInComponents.extension])..initialize();
    world.context.sprites = _Images(image);
    registerLevelMapSystems(world, collision: false);
  });

  tearDown(() => world.dispose());

  /// A map entity for [m] whose runtime has loaded.
  Future<(Entity, LevelMapRuntime)> ready(LevelMapData m) async {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: m),
    ]);
    world.update(0);
    final rt = e.getComponent<LevelMapComponent>()!.runtime!;
    await rt.syncAssets();
    return (e, rt);
  }

  _Recorder paint(
    Entity e,
    LevelMapRuntime rt,
    MapLayerData layer, {
    OutputCamera? camera,
    double time = 0,
  }) {
    final canvas = _Recorder();
    rt.painter.paint(
      canvas,
      RenderContext(
        world: world,
        size: const Size(400, 300),
        camera: camera,
        time: time,
      ),
      e,
      layer.id,
    );
    return canvas;
  }

  test('hiding a cell builds its own chunk again, and no other', () async {
    world.context.tiles.putTileset('assets/t.tileset.json', _tileset());
    final m = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/t.tileset.json');
    final layer = m.addLayer();
    for (final x in [0, 1, 16, 17]) {
      layer.cells.setCell(x, 0, TileCell.make(0, 0));
    }
    final (e, rt) = await ready(m);
    final before = _transforms(paint(e, rt, layer));
    expect(before, hasLength(2));

    LevelMaps.of(
      world,
      e,
    )!.setCellsHidden(layer, [const TileCoord(1, 0)], true);
    final after = _transforms(paint(e, rt, layer));
    expect(after, hasLength(2));
    expect(after[0], isNot(same(before[0])), reason: 'built again');
    expect(after[0].length, 4, reason: 'one tile left');
    expect(after[1], same(before[1]), reason: 'not touched');

    LevelMaps.of(
      world,
      e,
    )!.setCellsHidden(layer, [const TileCoord(1, 0)], false);
    final back = _transforms(paint(e, rt, layer));
    expect(back[0].length, 8);
    expect(back[1], same(before[1]));
  });

  test('a layer whose own tiles stay in their cells is drawn a chunk at a '
      'time, whatever tall tiles another layer uses', () async {
    world.context.tiles
      ..putTileset('assets/t.tileset.json', _tileset())
      ..putTileset('assets/tall.tileset.json', _tileset(tileHeight: 48));
    final m = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/t.tileset.json')
      ..addTileset('assets/tall.tileset.json');
    final ground = m.addLayer(name: 'Ground');
    final trees = m.addLayer(name: 'Trees');
    for (final x in [0, 16]) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
      trees.cells.setCell(x, 4, TileCell.make(1, 0));
    }
    final (e, rt) = await ready(m);
    expect(paint(e, rt, ground).atlases, hasLength(2), reason: 'a chunk each');
    expect(
      paint(e, rt, trees).atlases,
      hasLength(1),
      reason: 'a row of chunks, back to front across them',
    );
  });

  test('a row of tall tiles is drawn row by row across its chunks, as '
      'Tiled draws it', () async {
    world.context.tiles.putTileset(
      'assets/tall.tileset.json',
      _tileset(tileHeight: 48),
    );
    final m = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/tall.tileset.json');
    final layer = m.addLayer();
    const cells = [
      TileCoord(20, 3),
      TileCoord(2, 3),
      TileCoord(17, 2),
      TileCoord(1, 2),
      TileCoord(0, 3),
    ];
    for (final c in cells) {
      layer.cells.setCell(c.x, c.y, TileCell.make(0, 0));
    }
    final (e, rt) = await ready(m);
    Offset at(TileCoord c) {
      final r = rt.geometry.tileImageRect(c.x, c.y, 16, 48);
      return Offset(r.left, r.top);
    }

    final order = [...cells]..sort(rt.geometry.compareDrawOrder);
    expect(_drawn(paint(e, rt, layer)), [for (final c in order) at(c)]);
  });

  test('of a staggered row, only the tiles in view are sent', () async {
    world.context.tiles.putTileset(
      'assets/t.tileset.json',
      _tileset(tileWidth: 32),
    );
    final m = LevelMapData(
      orientation: LevelMapOrientation.staggered,
      tileWidth: 32,
      tileHeight: 16,
    )..addTileset('assets/t.tileset.json');
    final layer = m.addLayer();
    for (var x = 0; x < 200; x++) {
      layer.cells.setCell(x, 0, TileCell.make(0, 0));
      layer.cells.setCell(x, 1, TileCell.make(0, 0));
    }
    final (e, rt) = await ready(m);
    final all = _drawn(paint(e, rt, layer));
    expect(all, hasLength(400));

    final camera = OutputCamera(
      position: rt.geometry.cellCenter(100, 0),
      viewportSize: const Size(200, 100),
    );
    final seen = _drawn(paint(e, rt, layer, camera: camera));
    expect(seen.length, inInclusiveRange(10, 60));
    // The same tiles, in the same order, as drawing all of them.
    var from = 0;
    for (final p in seen) {
      final i = all.indexOf(p, from);
      expect(i, greaterThanOrEqualTo(from), reason: 'in order: $p');
      from = i + 1;
    }
    final r = rt.geometry.tileImageRect(100, 0, 32, 16);
    expect(seen, contains(Offset(r.left, r.top)));
  });

  test('isometric tiles wider than a cell are drawn back to front across '
      'chunks', () async {
    world.context.tiles.putTileset(
      'assets/wide.tileset.json',
      _tileset(tileWidth: 64, tileHeight: 32),
    );
    final m = LevelMapData(
      orientation: LevelMapOrientation.isometric,
      tileWidth: 32,
      tileHeight: 16,
    )..addTileset('assets/wide.tileset.json');
    final layer = m.addLayer();
    // (15, 15) is in chunk (0, 0), in front of (16, 13) in chunk (1, 0).
    const cells = [
      TileCoord(15, 15),
      TileCoord(16, 13),
      TileCoord(3, 4),
      TileCoord(30, 1),
      TileCoord(-2, 18),
    ];
    for (final c in cells) {
      layer.cells.setCell(c.x, c.y, TileCell.make(0, 0));
    }
    final (e, rt) = await ready(m);
    Offset at(TileCoord c) {
      final r = rt.geometry.tileImageRect(c.x, c.y, 64, 32);
      return Offset(r.left, r.top);
    }

    final order = [...cells]..sort(rt.geometry.compareDrawOrder);
    expect(_drawn(paint(e, rt, layer)), [for (final c in order) at(c)]);
    final drawn = _drawn(
      paint(
        e,
        rt,
        layer,
        camera: OutputCamera(viewportSize: const Size(4000, 4000)),
      ),
    );
    expect(drawn, [for (final c in order) at(c)], reason: 'culled the same');
  });

  test('a tile moved up by its tileset is drawn while its image is in '
      'view, though its cell is not', () async {
    world.context.tiles.putTileset(
      'assets/t.tileset.json',
      _tileset(tileWidth: 32, tileHeight: 32, offsetY: -64),
    );
    final m = LevelMapData(tileWidth: 32, tileHeight: 32)
      ..addTileset('assets/t.tileset.json');
    final layer = m.addLayer();
    // Its cell is 512-544 down, its image 448-480: in a view to 472.
    layer.cells.setCell(5, 16, TileCell.make(0, 0));
    final (e, rt) = await ready(m);
    final camera = OutputCamera(
      position: const Offset(200, 322),
      viewportSize: const Size(400, 300),
    );
    expect(_drawn(paint(e, rt, layer, camera: camera)), hasLength(1));
  });

  test('parallax is measured from the map\'s parallax origin', () async {
    world.context.tiles.putTileset('assets/t.tileset.json', _tileset());
    final m = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/t.tileset.json')
      ..parallaxOriginX = 400
      ..parallaxOriginY = 300;
    final layer = m.addLayer()
      ..parallaxX = 0.5
      ..parallaxY = 0.5;
    layer.cells.setCell(0, 0, TileCell.make(0, 0));
    final (e, rt) = await ready(m);
    Offset shift(Offset cameraAt) {
      final canvas = paint(
        e,
        rt,
        layer,
        camera: OutputCamera(
          position: cameraAt,
          viewportSize: const Size(4000, 4000),
        ),
      );
      final t = canvas.calls.firstWhere((c) => c.memberName == #translate);
      return Offset(
        t.positionalArguments[0] as double,
        t.positionalArguments[1] as double,
      );
    }

    expect(shift(const Offset(400, 300)), Offset.zero, reason: 'as placed');
    expect(shift(const Offset(600, 300)), const Offset(100, 0));

    final again = LevelMapData.fromJson(m.toJson());
    expect([again.parallaxOriginX, again.parallaxOriginY], [400, 300]);
    expect(LevelMapData().toJson().containsKey('parallaxOrigin'), isFalse);
    expect(m.copy().parallaxOriginY, 300);
  });

  test('a tinted layer and its shadow keep their own colour arrays', () async {
    world.context.tiles.putTileset('assets/t.tileset.json', _tileset());
    final m = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/t.tileset.json');
    final layer = m.addLayer()
      ..tint = 0xFFFF8080
      ..castShadows = true;
    layer.cells.setCell(0, 0, TileCell.make(0, 0));
    final (e, rt) = await ready(m);
    Int32List colors(_Recorder canvas) =>
        canvas.atlases.single.positionalArguments[3] as Int32List;
    _Recorder shadow() {
      final canvas = _Recorder();
      rt.painter.paintSilhouette(
        canvas,
        RenderContext(world: world, size: const Size(400, 300)),
        e,
        layer.id,
      );
      return canvas;
    }

    final tinted = colors(paint(e, rt, layer));
    final dark = colors(shadow());
    expect(dark, isNot(same(tinted)));
    expect(colors(paint(e, rt, layer)), same(tinted));
    expect(colors(shadow()), same(dark));
  });

  group('through a 2-D material', () {
    const flash = 'assets/fx/flash.material2d.json';

    setUp(() async {
      world.context.material2DText = (path) async => path == flash
          ? jsonEncode({
              'flash': {'color': 0xFFFF0000, 'amount': 1},
            })
          : throw StateError('no $path');
      final library = world.context.material2DLibrary;
      library.fileOf(flash);
      library.program;
      for (var i = 0; i < 200; i++) {
        if (library.program != null && library.fileOf(flash) != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(library.program, isNotNull, reason: 'the shader loads in tests');
      world.context.tiles.putTileset(
        'assets/t.tileset.json',
        _tileset()
          ..tileOrNew(1).animation = [
            const TileFrame(1, 100),
            const TileFrame(2, 100),
          ],
      );
    });

    Future<(Entity, LevelMapRuntime, MapLayerData)> materialMap() async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      final layer = m.addLayer()..material = flash;
      for (var x = 0; x < 20; x++) {
        layer.cells.setCell(x, 0, TileCell.make(0, 0));
      }
      m.addLayer(name: 'Other').cells.setCell(0, 0, TileCell.make(0, 0));
      final (e, rt) = await ready(m);
      return (e, rt, layer);
    }

    test('what its tiles were made into is drawn again as time goes on, '
        'and made again once a tile changes', () async {
      final (e, rt, layer) = await materialMap();
      final first = paint(e, rt, layer, time: 0).vertices;
      expect(first, hasLength(1));
      expect(paint(e, rt, layer, time: 0.5).vertices.single, same(first[0]));
      expect(paint(e, rt, layer, time: 1).vertices.single, same(first[0]));

      LevelMaps.of(
        world,
        e,
      )!.setTile(layer, const TileCoord(3, 0), TileCell.empty);
      final changed = paint(e, rt, layer, time: 1.5).vertices.single;
      expect(changed, isNot(same(first[0])));
      expect(first[0].debugDisposed, isTrue, reason: 'let go of');
      expect(paint(e, rt, layer, time: 2).vertices.single, same(changed));
    });

    test('an animated tile moving on makes it again', () async {
      final (e, rt, layer) = await materialMap();
      layer.cells.setCell(5, 0, TileCell.make(0, 1));
      final first = paint(e, rt, layer).vertices.single;
      expect(paint(e, rt, layer).vertices.single, same(first));
      rt.animationMs = 150;
      expect(paint(e, rt, layer).vertices.single, isNot(same(first)));
    });

    test(
      'its drawing is let go of with the runtime, and with the layer',
      () async {
        final (e, rt, layer) = await materialMap();
        final drawn = paint(e, rt, layer);
        final made = drawn.vertices.single;
        final shader = drawn.shaders.single;
        final other = rt.base.layers.last;
        rt.base.layers.remove(layer);
        rt.base.touch();
        paint(e, rt, other);
        expect(made.debugDisposed, isTrue, reason: 'its layer is gone');
        expect(shader.debugDisposed, isTrue);

        final (e2, rt2, layer2) = await materialMap();
        final last = paint(e2, rt2, layer2);
        rt2.dispose();
        expect(last.vertices.single.debugDisposed, isTrue);
        expect(last.shaders.single.debugDisposed, isTrue);
      },
    );

    test('drawn again, it looks the same', () async {
      // An opaque tileset image: the flash keeps the tile's own alpha.
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      final solid = await picture.toImage(32, 32);
      picture.dispose();
      addTearDown(solid.dispose);
      world.context.sprites = _Images(solid);
      final (e, _, _) = await materialMap();
      world.addSystem(RenderSystem(passes: const [], clock: () => 0));
      Future<Color> pixel(int x, int y) async {
        final recorder = ui.PictureRecorder();
        world.render(Canvas(recorder), const Size(48, 32));
        final picture = recorder.endRecording();
        final shot = await picture.toImage(48, 32);
        final data = (await shot.toByteData())!;
        picture.dispose();
        shot.dispose();
        final i = (y * 48 + x) * 4;
        return Color.fromARGB(
          data.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
      }

      expect(e.getComponent<LevelMapComponent>()!.runtime, isNotNull);
      for (var frame = 0; frame < 3; frame++) {
        world.update(1 / 60);
        expect(await pixel(24, 8), const Color(0xFFFF0000), reason: '$frame');
        expect((await pixel(24, 24)).a, 0, reason: 'no tile there');
      }
    });
  });
}
