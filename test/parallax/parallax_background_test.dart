// How a ParallaxBackground draws its layers: which axes repeat, the camera
// zoom, the repeating shader kept while the view scrolls, and what it
// releases.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// An image of [width] × [height] whose pixels all differ, so a shift by
/// one shows.
Future<ui.Image> _patterned(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()..color = Color.fromARGB(255, 30 * x + 10, 40 * y + 10, 200),
      );
    }
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

/// The RGBA bytes of what [draw] paints on a [width] × [height] canvas.
Future<Uint8List> _pixels(
  void Function(Canvas canvas) draw,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The alpha of pixel ([x], [y]) in [rgba], [width] pixels a row.
int _alpha(Uint8List rgba, int width, int x, int y) =>
    rgba[(y * width + x) * 4 + 3];

/// The shaders the paints drawn with carried, in order.
class _Shaders extends TestRecordingCanvas {
  final List<Shader?> shaders = [];

  @override
  void drawRect(Rect rect, Paint paint) {
    shaders.add(paint.shader);
    super.drawRect(rect, paint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image image;
  setUpAll(() async => image = await _patterned(8, 4));
  tearDownAll(() => image.dispose());

  ParallaxBackground background({
    bool repeatX = true,
    bool repeatY = true,
    Offset camera = Offset.zero,
  }) => ParallaxBackground(
    layers: [
      ParallaxLayer(
        image: image,
        scrollFactorX: 1,
        scrollFactorY: 1,
        repeatX: repeatX,
        repeatY: repeatY,
      ),
    ],
  )..cameraPosition = camera;

  group('repeating axes', () {
    test('repeating across only, the image is one row of tiles', () async {
      final bg = background(repeatY: false, camera: const Offset(3, -6));
      final rgba = await _pixels(
        (c) => bg.render(c, const Size(40, 24)),
        40,
        24,
      );
      // The row is 4 px tall, 6 px down: covered from left to right…
      for (var x = 0; x < 40; x++) {
        expect(_alpha(rgba, 40, x, 7), 255, reason: 'x $x in the row');
      }
      // …and nothing above or below it.
      for (final y in [0, 5, 10, 20]) {
        expect(_alpha(rgba, 40, 20, y), 0, reason: 'y $y off the row');
      }
    });

    test('repeating down only, the image is one column of tiles', () async {
      final bg = background(repeatX: false, camera: const Offset(-10, 2));
      final rgba = await _pixels(
        (c) => bg.render(c, const Size(40, 24)),
        40,
        24,
      );
      for (var y = 0; y < 24; y++) {
        expect(_alpha(rgba, 40, 12, y), 255, reason: 'y $y in the column');
      }
      for (final x in [0, 9, 18, 30]) {
        expect(_alpha(rgba, 40, x, 12), 0, reason: 'x $x off the column');
      }
    });

    test('repeating neither way, the image is drawn once', () async {
      final bg = background(repeatX: false, repeatY: false);
      final canvas = TestRecordingCanvas();
      bg.render(canvas, const Size(40, 24));
      final calls = [
        for (final i in canvas.invocations) i.invocation.memberName,
      ];
      expect(calls, [#drawImageRect]);
    });

    test('uniform layers take both', () {
      final layer = ParallaxLayer.uniform(image: image, repeatY: false);
      expect(layer.repeatX, isTrue);
      expect(layer.repeatY, isFalse);
    });
  });

  group('camera zoom', () {
    test('a layer scrolls by the zoomed camera move', () {
      final bg =
          ParallaxBackground(
              layers: [
                ParallaxLayer(
                  image: image,
                  scrollFactorX: 0.5,
                  scrollFactorY: 0.25,
                  repeatX: false,
                  repeatY: false,
                ),
              ],
            )
            ..cameraPosition = const Offset(40, 80)
            ..cameraZoom = 2;
      final canvas = TestRecordingCanvas();
      bg.render(canvas, const Size(320, 180));
      final dst =
          canvas.invocations.single.invocation.positionalArguments[2] as Rect;
      // At zoom 2 the world moves 2 px a unit: half of that, and a quarter.
      expect(dst.left, -40);
      expect(dst.top, -40);
    });
  });

  group('the repeating shader', () {
    test('is kept while the view scrolls', () {
      final bg = background(camera: const Offset(13, 5));
      final canvas = _Shaders();
      bg.render(canvas, const Size(40, 24));
      bg.cameraPosition = const Offset(21.5, 7.25);
      bg.render(canvas, const Size(40, 24));
      bg.layers.single.velocityX = 30;
      bg.update(0.1);
      bg.render(canvas, const Size(40, 24));
      expect(canvas.shaders, hasLength(3));
      expect(canvas.shaders.first, isA<ImageShader>());
      expect(canvas.shaders[1], same(canvas.shaders.first));
      expect(canvas.shaders[2], same(canvas.shaders.first));
    });

    test('is made again for a new image or scale', () async {
      final other = await _patterned(4, 4);
      addTearDown(other.dispose);
      final bg = background();
      final canvas = _Shaders();
      bg.render(canvas, const Size(40, 24));
      final first = canvas.shaders.single!;
      bg.layers.single.image = other;
      bg.render(canvas, const Size(40, 24));
      bg.layers.single.scale = 2;
      bg.render(canvas, const Size(40, 24));
      expect(canvas.shaders.toSet(), hasLength(3));
      expect(first.debugDisposed, isTrue);
      expect(canvas.shaders[1]!.debugDisposed, isTrue);
    });

    test('draws what a shader moved with the view drew', () async {
      for (final camera in const [
        Offset(13, 5),
        Offset(-7.5, 3.25),
        Offset(130.75, -41.5),
      ]) {
        final bg = background(camera: camera);
        final now = await _pixels(
          (c) => bg.render(c, const Size(40, 24)),
          40,
          24,
        );
        // How it used to be drawn: the scroll in the shader's matrix.
        final before = await _pixels(
          (canvas) {
            final ox = -(camera.dx % 8), oy = -(camera.dy % 4);
            final m = Float64List(16)
              ..[0] = 1
              ..[5] = 1
              ..[10] = 1
              ..[12] = ox > 0 ? ox - 8 : ox
              ..[13] = oy > 0 ? oy - 4 : oy
              ..[15] = 1;
            final shader = ImageShader(
              image,
              TileMode.repeated,
              TileMode.repeated,
              m,
              filterQuality: FilterQuality.medium,
            );
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 40, 24),
              Paint()
                ..filterQuality = FilterQuality.medium
                ..shader = shader,
            );
          },
          40,
          24,
        );
        var most = 0;
        for (var i = 0; i < now.length; i++) {
          final d = (now[i] - before[i]).abs();
          if (d > most) most = d;
        }
        expect(most, lessThanOrEqualTo(1), reason: 'camera $camera');
      }
    });
  });

  group('releasing', () {
    test('dispose releases every layer\'s shader', () {
      final bg = ParallaxBackground(
        layers: [
          ParallaxLayer(image: image),
          ParallaxLayer(image: image, scrollFactorX: 0.2),
        ],
      );
      final canvas = _Shaders();
      bg.render(canvas, const Size(40, 24));
      expect(canvas.shaders, hasLength(2));
      bg.dispose();
      for (final shader in canvas.shaders) {
        expect(shader!.debugDisposed, isTrue);
      }
      // Drawn again, it makes new ones.
      final again = _Shaders();
      bg.render(again, const Size(40, 24));
      expect(again.shaders.first!.debugDisposed, isFalse);
    });

    test('a removed layer releases its shader', () {
      final kept = ParallaxLayer(image: image);
      final dropped = ParallaxLayer(image: image, scrollFactorX: 0.2);
      final bg = ParallaxBackground(layers: [kept, dropped]);
      final canvas = _Shaders();
      bg.render(canvas, const Size(40, 24));
      expect(bg.removeLayer(dropped), isTrue);
      expect(canvas.shaders.last!.debugDisposed, isTrue);
      expect(canvas.shaders.first!.debugDisposed, isFalse);
    });
  });
}
