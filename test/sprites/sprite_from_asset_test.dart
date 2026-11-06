// Sprites from assets: an image outlives its asset being unloaded, and a
// sprite given its image leaves it alone.

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
      engine.assets.unload('assets/hero.png');
      expect(image.debugDisposed, isFalse, reason: "it was the manager's");
      expect(sprite.image!.debugDisposed, isFalse);

      final held = sprite.image!;
      sprite.dispose();
      expect(held.debugDisposed, isTrue);
      expect(sprite.image, isNull);
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
}
