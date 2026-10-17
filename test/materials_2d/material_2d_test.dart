// 2-D materials: files read (variants, unsaved edits, saved again), and
// sprites drawn through them by the render system — every sprite sharing a
// material in one draw, in the order the layers say, each with its own
// overridden values — checked pixel by pixel through the real shader.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _flash = 'assets/fx/flash.material2d.json';
const _outline = 'assets/fx/outline.material2d.json';
const _flashBlue = 'assets/fx/flash_blue.material2d.json';

final _files = <String, String>{
  _flash: jsonEncode({
    'flash': {'colour': 0xFFFF0000, 'amount': 1},
  }),
  _outline: jsonEncode({
    'outline': {'colour': 0xFF0000FF, 'width': 2},
  }),
  _flashBlue: jsonEncode({
    'parent': _flash,
    'flash': {'colour': 0xFF0000FF},
  }),
};

/// [width] × [height] of [left], or [left] then [right] halves.
Future<ui.Image> _image(int width, int height, Color left, [Color? right]) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = left,
  );
  if (right != null) {
    canvas.drawRect(
      Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
      Paint()..color = right,
    );
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

class _Images extends SpriteAssetLoader {
  _Images(this.image);
  final ui.Image image;

  @override
  Future<ui.Image> loadImage(String path) async => image;

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('half floats come back as the shader reads them', () {
    for (final v in [
      0.0,
      1.0,
      0.5,
      -3.25,
      1000.0,
      0.001,
      65504.0,
      6e-6,
      0.3,
      37.7,
    ]) {
      final back = Material2DShader.fromHalf(Material2DShader.halfOf(v));
      expect(back, closeTo(v, v.abs() * 0.001 + 1e-7), reason: '$v');
    }
    expect(Material2DShader.fromHalf(Material2DShader.halfOf(1e9)), 65504);
    expect(Material2DShader.halfOf(double.nan), 0);
  });

  test('the uniforms fill what the shader declares', () {
    expect(
      Material2DShader.dynamicKeys,
      hasLength(29),
      reason: 'uDyn holds 32',
    );
    for (final key in Material2DShader.dynamicKeys) {
      expect(
        Material2DEffects.param(Material2DShader.paramOf(key)),
        isNotNull,
        reason: key,
      );
    }
  });

  group('Material2DLibrary', () {
    late Map<String, String> files;
    late Material2DLibrary library;
    setUp(() {
      files = {..._files};
      library = Material2DLibrary(
        (path) async => files[path] ?? (throw StateError('no $path')),
      );
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('a variant over its parent; problems said', () async {
      expect(library.fileOf(_flashBlue), isNull, reason: 'being read');
      await settle();
      await settle();
      final file = library.fileOf(_flashBlue)!;
      expect(file.isVariant, isFalse);
      expect(file.colour('flash.colour'), 0xFF0000FF);
      expect(file.number('flash.amount'), 1, reason: "the parent's");
      expect(library.sourceOf(_flashBlue)!.isVariant, isTrue);

      files['orphan.material2d.json'] =
          '{"parent": "gone.material2d.json", "glow": {}}';
      library.fileOf('orphan.material2d.json');
      await settle();
      await settle();
      expect(
        library.problemsOf('orphan.material2d.json').single,
        contains('gone.material2d.json'),
      );
      expect(library.fileOf('orphan.material2d.json')!.isOn('glow'), isTrue);
    });

    test('an unsaved edit, and a file saved again', () async {
      library.fileOf(_flashBlue);
      await settle();
      await settle();
      final revision = library.revision;
      library.preview(
        _flash,
        Material2DFile.parse('{"flash": {"amount": 0.25}}'),
      );
      expect(library.revision, greaterThan(revision));
      expect(
        library.fileOf(_flashBlue)!.number('flash.amount'),
        0.25,
        reason: 'its variant follows',
      );
      library.endPreview(_flash);
      expect(library.fileOf(_flashBlue)!.number('flash.amount'), 1);

      files[_flash] = '{"flash": {"amount": 0.5}}';
      library.reload(_flash);
      expect(
        library.fileOf(_flash)!.number('flash.amount'),
        1,
        reason: 'as it was, until read',
      );
      await settle();
      expect(library.fileOf(_flash)!.number('flash.amount'), 0.5);
    });
  });

  group('drawn through its material', () {
    late World world;
    late RenderSystem render;
    late ui.Image green;

    setUpAll(() async {
      green = await _image(8, 8, const Color(0xFF00FF00));
    });

    setUp(() async {
      world = World()..initialize();
      world.context.material2DText = (path) async =>
          _files[path] ?? (throw StateError('no $path'));
      render = RenderSystem(passes: const [], clock: () => 0);
      world.addSystem(render);
      final library = Material2DLibrary.of(world.context);
      for (final path in _files.keys) {
        library.fileOf(path);
      }
      library.program;
      for (var i = 0; i < 200; i++) {
        if (library.program != null &&
            _files.keys.every((p) => library.fileOf(p) != null))
          break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(library.program, isNotNull, reason: 'the shader loads in tests');
    });
    tearDown(() => world.dispose());

    Entity sprite(
      ui.Image image,
      Offset at, {
      String? material,
      Map<String, Object>? overrides,
      int z = 0,
      bool flipX = false,
    }) => world.createEntityWithComponents([
      TransformComponent(position: Vector3(at.dx, at.dy, 0)),
      RenderableComponent(
        renderable: Sprite(image: image, flipX: flipX),
      ),
      LayerComponent(zOrder: z),
      if (material != null)
        Material2D(material: material, overrides: overrides),
    ]);

    Future<ByteData> frame() async {
      final recorder = ui.PictureRecorder();
      world.render(Canvas(recorder), const Size(48, 32));
      final picture = recorder.endRecording();
      final image = await picture.toImage(48, 32);
      final data = (await image.toByteData())!;
      picture.dispose();
      image.dispose();
      return data;
    }

    Color at(ByteData d, int x, int y) {
      final i = (y * 48 + x) * 4;
      return Color.fromARGB(
        d.getUint8(i + 3),
        d.getUint8(i),
        d.getUint8(i + 1),
        d.getUint8(i + 2),
      );
    }

    test('flashed red where the sprite is, clear around it', () async {
      sprite(green, const Offset(16, 16), material: _flash);
      final d = await frame();
      expect(at(d, 16, 16), const Color(0xFFFF0000));
      expect(at(d, 2, 2).a, 0);
      expect(render.stats['drawCalls'], 1);
    });

    test('an outline just outside its frame', () async {
      sprite(green, const Offset(16, 16), material: _outline);
      final d = await frame();
      expect(
        at(d, 16, 16),
        const Color(0xFF00FF00),
        reason: 'the sprite itself',
      );
      expect(
        at(d, 21, 16),
        const Color(0xFF0000FF),
        reason: 'its frame is 12-20: the line past it',
      );
      expect(at(d, 26, 16).a, 0, reason: 'only two pixels wide');
    });

    test("each sprite's own values, all in one draw", () async {
      sprite(green, const Offset(8, 16), material: _flash);
      sprite(
        green,
        const Offset(24, 16),
        material: _flash,
        overrides: {'flash.amount': 0.0},
      );
      sprite(
        green,
        const Offset(40, 16),
        material: _flash,
        overrides: {'flash.colour': 0xFF0000FF},
      );
      final d = await frame();
      expect(at(d, 8, 16), const Color(0xFFFF0000));
      expect(at(d, 24, 16), const Color(0xFF00FF00));
      expect(at(d, 40, 16), const Color(0xFF0000FF));
      expect(render.stats['drawCalls'], 1);
    });

    test(
      'a plain sprite between two drawn with a material keeps its place',
      () async {
        final white = await _image(8, 8, const Color(0xFFFFFFFF));
        sprite(green, const Offset(16, 16), material: _flash, z: 0);
        sprite(white, const Offset(18, 16), z: 1);
        sprite(green, const Offset(20, 16), material: _flash, z: 2);
        final d = await frame();
        expect(
          at(d, 13, 16),
          const Color(0xFFFF0000),
          reason: 'the first, alone there',
        );
        expect(
          at(d, 15, 16),
          const Color(0xFFFFFFFF),
          reason: 'the plain one over the first',
        );
        expect(
          at(d, 17, 16),
          const Color(0xFFFF0000),
          reason: 'the last over the plain one',
        );
        expect(render.stats['drawCalls'], 3);
      },
    );

    test('mirrored as the sprite is', () async {
      final halves = await _image(
        8,
        8,
        const Color(0xFF00FF00),
        const Color(0xFF0000FF),
      );
      sprite(halves, const Offset(16, 16), material: _outline, flipX: true);
      final d = await frame();
      expect(
        at(d, 13, 16),
        const Color(0xFF0000FF),
        reason: 'the right half, on the left',
      );
      expect(at(d, 18, 16), const Color(0xFF00FF00));
    });

    test('drawn as it is until its material is read', () async {
      sprite(
        green,
        const Offset(16, 16),
        material: 'assets/fx/not_yet.material2d.json',
      );
      final d = await frame();
      expect(at(d, 16, 16), const Color(0xFF00FF00));
    });

    test('a variant draws as its parent with its own on top', () async {
      sprite(green, const Offset(16, 16), material: _flashBlue);
      final d = await frame();
      expect(at(d, 16, 16), const Color(0xFF0000FF));
    });

    test('a shape is drawn into an image, then through its material', () async {
      final rect = world.createEntityWithComponents([
        TransformComponent(position: Vector3(16, 16, 0)),
        RectangleComponent(width: 8, height: 8),
        Material2D(material: _flash),
      ]);
      var d = await frame();
      expect(at(d, 16, 16), const Color(0xFFFF0000));
      expect(at(d, 2, 2).a, 0);
      rect.getComponent<Material2D>()!.material = _outline;
      d = await frame();
      expect(
        at(d, 21, 16),
        const Color(0xFF0000FF),
        reason: 'an outline round the rectangle',
      );
    });

    test('a tile layer drawn through its material', () async {
      final tiles = await _image(32, 32, const Color(0xFF00FF00));
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
      world.context.sprites = _Images(tiles);
      registerLevelMapSystems(world, collision: false);
      final map = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      final layer = map.addLayer()..material = _flash;
      layer.cells.setCell(0, 0, TileCell.make(0, 0));
      layer.cells.setCell(1, 0, TileCell.make(0, 0));
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: map),
      ]);
      world.update(0);
      await e.getComponent<LevelMapComponent>()!.runtime!.syncAssets();
      final d = await frame();
      expect(at(d, 8, 8), const Color(0xFFFF0000));
      expect(at(d, 24, 8), const Color(0xFFFF0000));
      expect(at(d, 8, 24).a, 0, reason: 'no tile there');
      expect(
        MapLayerData.fromJson(layer.toJson()).material,
        _flash,
        reason: 'saved with the map',
      );
    });
  });

  group('the Timeline', () {
    test("keys an entity's overridden numbers, not its colours", () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        Material2D(material: _flash),
      ]);
      final field = world.context.definitions
          .definitionByType('Material2D')!
          .fields
          .firstWhere((f) => f.name == 'overrides');
      expect(PropertyAccess.canAnimate(field), isTrue);
      final channels = PropertyAccess.channelsOf(field);
      expect(
        channels,
        containsAll([
          'flash.amount',
          'dissolve.amount',
          'scroll.speed#0',
          'vignette.amount',
        ]),
      );
      expect(channels, isNot(contains('flash.colour')));

      final m = e.getComponent<Material2D>()!;
      final revision = m.revision;
      PropertyAccess.of(
        e,
        'Material2D',
        'overrides',
        'flash.amount',
      )!.write(0.25);
      PropertyAccess.of(
        e,
        'Material2D',
        'overrides',
        'scroll.speed#1',
      )!.write(-8);
      expect(m.overrides, {'flash.amount': 0.25, 'scroll.speed#1': -8});
      expect(m.revision, greaterThan(revision));
      expect(
        PropertyAccess.of(e, 'Material2D', 'overrides', 'flash.amount')!.read(),
        0.25,
      );
    });

    test('one number of a pair counts on its own', () {
      final file = Material2DFile.parse('{"scroll": {"speed": [16, 4]}}');
      expect(
        Material2DShader.number(file, {
          'scroll.speed#1': -8.0,
        }, 'scroll.speed#1'),
        -8,
      );
      expect(
        Material2DShader.number(file, {
          'scroll.speed#1': -8.0,
        }, 'scroll.speed#0'),
        16,
      );
      expect(Material2DShader.overrides('scroll.speed#1', -8), isTrue);
      expect(Material2DShader.overrides('scroll.speed#2', -8), isFalse);
      expect(
        Material2DShader.overrides('flash.amount#0', 1),
        isFalse,
        reason: 'not a pair',
      );
    });
  });

  test('a Material2D is saved with its entity', () {
    final definitions = EngineContext().definitions;
    final component = Material2D(
      material: _flash,
      overrides: {'flash.amount': 0.5},
    );
    final back =
        definitions.decode(
              jsonDecode(jsonEncode(definitions.encode(component)))
                  as Map<String, dynamic>,
            )!
            as Material2D;
    expect(back.material, _flash);
    expect(back.overrides, {'flash.amount': 0.5});
    final revision = back.revision;
    back.set('flash.amount', 1.0);
    expect(back.revision, revision + 1);
  });
}
