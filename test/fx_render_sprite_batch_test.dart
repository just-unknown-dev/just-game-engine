// Batched sprites: which batch, at what size, and for how long.
//
// A batch draws each sprite with one uniform scale, and used to be handed
// the average of X and Y — a (3, 1) sprite drew at 2, a (-1, 1) one at 0.
// Pixel art never batched at all, a sprite's render size was ignored when
// it did, and the batches were keyed by `identityHashCode(image)` and kept
// forever — images and all.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// An image with something in it: [createTestImage]'s are transparent.
Future<ui.Image> _patterned(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()
          ..color = Color.fromARGB(
            255 - 20 * ((x + y) % 4),
            40 * x % 256,
            60 * y % 256,
            (x * y * 30) % 256,
          ),
      );
    }
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

/// What a batch was given, per sprite.
class _Queued {
  _Queued(this.source, this.position, this.scale, this.color);
  final Rect source;
  final Offset position;
  final double scale;
  final Color color;
}

class _FakeBatch implements SpriteBatchRenderer {
  _FakeBatch(this.image, this.log);
  final ui.Image image;
  final List<(ui.Image, _Queued)> log;
  final List<_Queued> _queued = [];

  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  }) => _queued.add(_Queued(sourceRect, position, scale, color));

  @override
  void flush(Canvas canvas) {
    for (final q in _queued) {
      log.add((image, q));
    }
    _queued.clear();
  }
}

class _Plain extends Renderable {
  _Plain(this.log);
  final List<String> log;
  @override
  void render(Canvas canvas, Size size) => log.add('plain');
  @override
  Rect? getBounds() => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image image, other;
  setUpAll(() async {
    image = await createTestImage(width: 8, height: 4);
    other = await createTestImage(width: 8, height: 4);
  });

  group('RenderSystem', () {
    late World world;
    late List<(ui.Image, _Queued)> batched;
    late List<ui.Image> made;
    late RenderSystem render;

    setUp(() {
      batched = [];
      made = [];
      world = World()..initialize();
      render = RenderSystem(
        passes: const [],
        spriteBatchFactory: (atlas) {
          made.add(atlas);
          return _FakeBatch(atlas, batched);
        },
      );
      world.addSystem(render);
    });
    tearDown(() => world.dispose());

    void frame() => world.render(Canvas(ui.PictureRecorder()), Size.zero);

    Entity sprite(Sprite s, {Vector3? scale}) =>
        world.createEntityWithComponents([
          TransformComponent(scale: scale),
          RenderableComponent(renderable: s),
        ]);

    test('only a uniform, positive scale is batched', () {
      sprite(Sprite(image: image), scale: Vector3(2, 2, 1));
      sprite(Sprite(image: image), scale: Vector3(3, 1, 1));
      sprite(Sprite(image: image), scale: Vector3(-1, 1, 1));
      sprite(Sprite(image: image), scale: Vector3(-2, -2, 1));
      frame();
      expect(batched.map((b) => b.$2.scale), [2.0]);
    });

    test('pixel art batches, apart from smoothed sprites', () {
      sprite(Sprite(image: image)..filterQuality = FilterQuality.none);
      sprite(Sprite(image: image));
      frame();
      expect(batched, hasLength(2));
      expect(made, [image, image], reason: 'one batch per filter quality');
    });

    test('the batch samples the way its sprites asked', () {
      final world2 = World()..initialize();
      addTearDown(world2.dispose);
      final system = RenderSystem(passes: const []);
      world2.addSystem(system);
      world2.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(
          renderable: Sprite(image: image)..filterQuality = FilterQuality.none,
        ),
      ]);
      final canvas = TestRecordingCanvas();
      world2.render(canvas, Size.zero);
      final atlas = canvas.invocations.singleWhere(
        (i) => i.invocation.memberName == #drawRawAtlas,
      );
      final paint = atlas.invocation.positionalArguments.last as Paint;
      expect(paint.filterQuality, FilterQuality.none);
    });

    test('a render size is honoured when it keeps the proportions', () {
      sprite(Sprite(image: image, renderSize: const Size(16, 8)));
      sprite(
        Sprite(image: image, renderSize: const Size(16, 8)),
        scale: Vector3(0.5, 0.5, 1),
      );
      // Stretched: drawn by itself.
      sprite(Sprite(image: image, renderSize: const Size(16, 16)));
      frame();
      expect(batched.map((b) => b.$2.scale), [2.0, 1.0]);
    });

    test('batches are keyed by the image, not its hash', () {
      sprite(Sprite(image: image));
      sprite(Sprite(image: other));
      frame();
      expect(made, [image, other]);
      expect(batched.map((b) => b.$1), [image, other]);
    });

    test('a batch not used in a frame is dropped, image and all', () {
      final a = sprite(Sprite(image: image));
      sprite(Sprite(image: other));
      frame();
      expect(render.debugSpriteBatchCount, 2);
      world.destroyEntity(a);
      frame();
      expect(render.debugSpriteBatchCount, 1);
      render.dispose();
      expect(render.debugSpriteBatchCount, 0);
    });

    test('a batch colour is the tint at the opacity times its own alpha', () {
      sprite(Sprite(image: image, opacity: 0.5));
      sprite(
        Sprite(image: image, tint: const Color(0x80336699), opacity: 0.25),
      );
      frame();
      // The tint's alpha fades the sprite as a shape's does (it used to be
      // dropped): 0x80 at a quarter is 0x20.
      expect(batched.map((b) => b.$2.color), [
        Color(const Color.fromRGBO(255, 255, 255, 0.5).toARGB32()),
        const Color(0x20336699),
      ]);
    });
  });

  group('RenderingEngine', () {
    late RenderingEngine rendering;
    late List<(ui.Image, _Queued)> batched;

    setUp(() {
      batched = [];
      rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(800, 600))
        ..spriteBatchFactory = ((atlas) => _FakeBatch(atlas, batched));
      rendering.initialize();
    });

    void frame() =>
        rendering.render(Canvas(ui.PictureRecorder()), const Size(800, 600));

    test('only a uniform, positive scale is batched', () {
      rendering
        ..addRenderable(Sprite(image: image, scale: Vector3(3, 1, 1)))
        ..addRenderable(Sprite(image: image, scale: Vector3(-1, 1, 1)))
        ..addRenderable(Sprite(image: image, scale: Vector3(2, 2, 1)));
      frame();
      expect(batched.map((b) => b.$2.scale), [2.0]);
      expect(rendering.stats['batchedSprites'], 1);
    });

    test('a batch is drawn in its place among what is not batched', () {
      final tracked = <String>[];
      rendering
        ..spriteBatchFactory = ((atlas) => _LoggingBatch(tracked))
        ..addRenderable(Sprite(image: image)..zOrder = 0)
        ..addRenderable(_Plain(tracked)..zOrder = 1)
        ..addRenderable(Sprite(image: image)..zOrder = 2);
      frame();
      expect(tracked, ['batch×1', 'plain', 'batch×1']);
    });

    test('batches are dropped with clear()', () {
      rendering.addRenderable(Sprite(image: image));
      frame();
      expect(rendering.debugSpriteBatchCount, 1);
      rendering.clear();
      expect(rendering.debugSpriteBatchCount, 0);
    });
  });

  group('SpriteBatch', () {
    Future<Uint8List> pixels(void Function(Canvas) draw) async {
      final recorder = ui.PictureRecorder();
      draw(Canvas(recorder));
      final picture = recorder.endRecording();
      final out = await picture.toImage(32, 32);
      final data = await out.toByteData();
      picture.dispose();
      out.dispose();
      return data!.buffer.asUint8List();
    }

    test('draws what drawAtlas drew, sprite for sprite', () async {
      final image = await _patterned(8, 4);
      final sprites = [
        (
          const Rect.fromLTWH(0, 0, 4, 4),
          const Offset(8, 8),
          0.0,
          1.0,
          const Color(0xFFFFFFFF),
        ),
        (
          const Rect.fromLTWH(4, 0, 4, 4),
          const Offset(20, 10),
          0.7,
          2.0,
          const Color(0x8033CC99),
        ),
        (
          const Rect.fromLTWH(0, 0, 8, 4),
          const Offset(12, 24),
          -1.2,
          1.5,
          const Color(0xFFFF0000),
        ),
      ];
      final expected = await pixels((canvas) {
        canvas.drawAtlas(
          image,
          [
            for (final s in sprites)
              RSTransform.fromComponents(
                rotation: s.$3,
                scale: s.$4,
                anchorX: s.$1.width / 2,
                anchorY: s.$1.height / 2,
                translateX: s.$2.dx,
                translateY: s.$2.dy,
              ),
          ],
          [for (final s in sprites) s.$1],
          [for (final s in sprites) s.$5],
          BlendMode.modulate,
          null,
          Paint(),
        );
      });
      final actual = await pixels((canvas) {
        final batch = SpriteBatch(image);
        for (final s in sprites) {
          batch.add(
            sourceRect: s.$1,
            position: s.$2,
            rotation: s.$3,
            scale: s.$4,
            color: s.$5,
          );
        }
        batch.flush(canvas);
      });
      expect(actual.any((b) => b != 0), isTrue);
      expect(actual, expected);
    });

    test('grows past its first buffers, and sends no colours when all are '
        'white', () {
      final batch = SpriteBatch(image);
      for (var i = 0; i < 200; i++) {
        batch.addRaw(left: 0, top: 0, right: 4, bottom: 4, x: i * 1.0, y: 0);
      }
      expect(batch.length, 200);
      final canvas = TestRecordingCanvas();
      batch.flush(canvas);
      final call = canvas.invocations.single.invocation;
      expect(call.memberName, #drawRawAtlas);
      expect((call.positionalArguments[1] as Float32List).length, 800);
      expect(call.positionalArguments[3], isNull);
      expect(batch.length, 0);
    });
  });
}

class _LoggingBatch implements SpriteBatchRenderer {
  _LoggingBatch(this.log);
  final List<String> log;
  int _n = 0;

  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  }) => _n++;

  @override
  void flush(Canvas canvas) {
    if (_n == 0) return;
    log.add('batch×$_n');
    _n = 0;
  }
}
