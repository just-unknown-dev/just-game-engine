// Sprites from assets, parallax tiles and component painters.

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
        Paint()..color = Color.fromARGB(255, 50 * x % 256, 70 * y % 256, 120),
      );
    }
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

Future<List<int>> _pixels(void Function(Canvas) draw, int w, int h) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

class Blob extends Component {
  int layer = 0;
}

class _BlobPainter extends ComponentPainter<Blob> {
  final List<String> names = [];
  @override
  int layerOf(Blob c) => c.layer;
  @override
  void paint(Canvas canvas, Entity e, Blob c, RenderContext ctx) =>
      names.add(e.name!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an image from the asset manager outlives the asset being unloaded',
    () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      final png = await (await _patterned(
        4,
        4,
      )).toByteData(format: ui.ImageByteFormat.png);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (_) async => png);
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );

      final assets = engine.assets;
      final image = await Sprite.loadImageFromAsset(
        'assets/hero.png',
        assets: assets,
      );
      final sprite = await Sprite.fromAsset('assets/hero.png', assets: assets);
      final sheet = await SpriteSheet.fromAsset(
        'assets/hero.png',
        assets: assets,
        spriteWidth: 2,
        spriteHeight: 2,
      );
      engine.assets.unload('assets/hero.png');
      expect(image.debugDisposed, isFalse, reason: "it was the manager's");
      expect(sprite.image!.debugDisposed, isFalse);
      expect(sheet.image.debugDisposed, isFalse);

      final held = sprite.image!;
      sprite.dispose();
      expect(held.debugDisposed, isTrue);
      expect(sprite.image, isNull);
      sheet.dispose();
      expect(sheet.image.debugDisposed, isTrue);
      image.dispose();
    },
    // The engine's start-up is slow on a busy machine.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a sprite given its image leaves it alone', () async {
    final image = await _patterned(2, 2);
    Sprite(image: image).dispose();
    expect(image.debugDisposed, isFalse);
  });

  group('a repeating parallax layer', () {
    late ui.Image image;
    setUpAll(() async => image = await _patterned(8, 8));

    ParallaxBackground background({Color? tint}) => ParallaxBackground(
      layers: [
        ParallaxLayer(
          image: image,
          scrollFactorX: 1,
          scrollFactorY: 1,
          tint: tint,
        ),
      ],
    )..cameraPosition = const Offset(13, 5);

    test('is one rectangle, not one draw per tile', () {
      final canvas = TestRecordingCanvas();
      background().render(canvas, const Size(100, 60));
      final calls = [for (final i in canvas.invocations) i.invocation];
      expect(calls, hasLength(1));
      expect(calls.single.memberName, #drawRect);
      final paint = calls.single.positionalArguments[1] as Paint;
      expect(paint.shader, isA<ImageShader>());
    });

    test('looks as the tiles did', () async {
      final bg = background(tint: const Color(0xFFFFCC88));
      final now = await _pixels(
        (c) => bg.render(c, const Size(40, 24)),
        40,
        24,
      );
      final before = await _pixels(
        (canvas) {
          final paint = Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Colors.white
            ..colorFilter = const ColorFilter.mode(
              Color(0xFFFFCC88),
              BlendMode.modulate,
            );
          // Scrolled by (13, 5): the old loop's tiles.
          for (double y = -5; y < 24; y += 8) {
            for (double x = -5; x < 40; x += 8) {
              canvas.drawImageRect(
                image,
                const Rect.fromLTWH(0, 0, 8, 8),
                Rect.fromLTWH(x, y, 8, 8),
                paint,
              );
            }
          }
        },
        40,
        24,
      );
      expect(now.any((b) => b != 0), isTrue);
      var most = 0;
      for (var i = 0; i < now.length; i++) {
        final d = (now[i] - before[i]).abs();
        if (d > most) most = d;
      }
      expect(most, lessThanOrEqualTo(1));
    });
  });

  group('ComponentPainterPass', () {
    late World world;
    late _BlobPainter painter;
    late ComponentDefinitionRegistry registry;

    setUp(() {
      painter = _BlobPainter();
      registry = ComponentDefinitionRegistry()
        ..register(
          ComponentDefinition<Blob>(
            type: 'Blob',
            create: Blob.new,
            fields: const [],
            painter: painter,
          ),
        );
      world = World()..initialize();
      world.addSystem(
        RenderSystem(passes: [ComponentPainterPass(definitions: registry)]),
      );
    });
    tearDown(() => world.dispose());

    List<String> frame() {
      painter.names.clear();
      world.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
      return List.of(painter.names);
    }

    Entity blob(String name, int layer) => world.createEntityWithComponents([
      TransformComponent(),
      Blob()..layer = layer,
    ], name: name);

    test('keeps its order between frames, and follows changes', () {
      final a = blob('a', 1);
      blob('b', 2);
      expect(frame(), ['a', 'b']);
      a.getComponent<Blob>()!.layer = 3;
      expect(frame(), ['b', 'a']);
      final c = blob('c', 0);
      expect(frame(), ['c', 'b', 'a']);
      c.isActive = false;
      expect(frame(), ['b', 'a']);
    });

    test('equal layers paint in the order found, every frame', () {
      for (var i = 0; i < 40; i++) {
        blob('e$i', i % 2);
      }
      final first = frame();
      expect(first.take(20), [for (var i = 0; i < 40; i += 2) 'e$i']);
      expect(frame(), first);
    });

    test('an unturned, unscaled entity gets only a translation', () {
      blob('a', 0);
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(100, 100));
      expect(
        [for (final i in canvas.invocations) i.invocation.memberName],
        [#save, #translate, #restore],
      );
    });
  });
}
