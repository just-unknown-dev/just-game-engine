// A repeating parallax layer's tiles.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final calls = [
        for (final i in canvas.invocations)
          if (i.invocation.memberName.toString().contains('draw')) i.invocation,
      ];
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
}
