// Assets come from the bundle, every time: never from a copy the cache kept
// across runs (which outlived the asset — an update shipping a new image went
// on drawing the old one), and only the bytes that are the asset's own.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// What the fake bundle holds, by asset key.
final Map<String, ByteData> _bundle = {};

ByteData _text(String s) => ByteData.sublistView(utf8.encode(s));

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 3, 2),
    Paint()..color = const Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(3, 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Engine> _boot() async {
  final engine = Engine();
  addTearDown(engine.dispose);
  await engine.initialize();
  return engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _bundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = Uri.decodeFull(
            utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            ),
          );
          return _bundle[key];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('bundle assets are not copied into the cache', () {
    test('a text asset changed in the bundle loads as it now is', () async {
      final engine = await _boot();
      const path = 'assets/fx/level.txt';
      _bundle[path] = _text('v1');
      expect((await engine.assets.loadText(path)).content, 'v1');
      engine.assets.unload(path);

      // An update ships a new file under the same name.
      _bundle[path] = _text('v2');
      expect((await engine.assets.loadText(path)).content, 'v2');
      expect(await engine.cache.getString(path), isNull);
    });

    test('so do JSON and binary assets', () async {
      final engine = await _boot();
      _bundle['assets/fx/a.json'] = _text('{"v": 1}');
      _bundle['assets/fx/a.bin'] = ByteData.sublistView(
        Uint8List.fromList([1]),
      );
      await engine.assets.loadJson('assets/fx/a.json');
      await engine.assets.loadBinary('assets/fx/a.bin');
      engine.assets
        ..unload('assets/fx/a.json')
        ..unload('assets/fx/a.bin');

      _bundle['assets/fx/a.json'] = _text('{"v": 2}');
      _bundle['assets/fx/a.bin'] = ByteData.sublistView(
        Uint8List.fromList([2]),
      );
      expect((await engine.assets.loadJson('assets/fx/a.json')).data, {'v': 2});
      expect((await engine.assets.loadBinary('assets/fx/a.bin')).data, [2]);
      expect(await engine.cache.getBinary('assets/fx/a.bin'), isNull);
      expect(await engine.cache.getString('assets/fx/a.json'), isNull);
    });

    test('an asset manager works without an engine behind it', () async {
      _bundle['assets/fx/solo.txt'] = _text('alone');
      final assets = AssetManager()..initialize();
      expect((await assets.loadText('assets/fx/solo.txt')).content, 'alone');
      assets.dispose();
    });
  });

  group('only the asset\'s own bytes', () {
    test('a binary asset handed over as a view of a larger buffer', () async {
      // Bytes 2..4 of an 8-byte buffer: what a bundle may return.
      final buffer = Uint8List.fromList([9, 9, 1, 2, 3, 9, 9, 9]).buffer;
      _bundle['assets/fx/view.bin'] = ByteData.view(buffer, 2, 3);
      final engine = await _boot();
      final asset = await engine.assets.loadBinary('assets/fx/view.bin');
      expect(asset.data, [1, 2, 3]);
    });

    test('an audio asset too', () async {
      final buffer = Uint8List.fromList([0, 7, 8, 0]).buffer;
      _bundle['assets/fx/view.wav'] = ByteData.view(buffer, 1, 2);
      final engine = await _boot();
      final asset = await engine.assets.loadAudio('assets/fx/view.wav');
      expect(asset.data, [7, 8]);
      expect(asset.format, AudioFormat.wav);
    });

    test('an image keeps its decoded pixels, not its encoded bytes', () async {
      final png = await _png();
      // Behind some unrelated bytes, as a view.
      final padded = Uint8List(png.length + 5)
        ..setRange(5, 5 + png.length, png);
      _bundle['assets/fx/red.png'] = ByteData.view(
        padded.buffer,
        5,
        png.length,
      );
      final engine = await _boot();
      final asset = await engine.assets.loadImage('assets/fx/red.png');
      expect(asset.image, isNotNull);
      expect((asset.width, asset.height), (3, 2));
      expect(asset.data, isNull, reason: 'the PNG was dropped once decoded');
    });
  });

  test('a failed load keeps where it failed', () async {
    final assets = (await _boot()).assets;
    Object? error;
    StackTrace? stack;
    try {
      await assets.loadText('assets/fx/missing.txt');
    } catch (e, s) {
      error = e;
      stack = s;
    }
    expect(error, isA<AssetLoadException>());
    expect((error! as AssetLoadException).cause, isA<FlutterError>());
    // The trace is the bundle's, where the asset was found missing — not
    // just the line that wrapped the error.
    expect(stack.toString(), contains('asset_bundle.dart'));
  });
}
