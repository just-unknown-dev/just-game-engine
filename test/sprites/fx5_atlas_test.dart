// Sprite atlases: a trimmed region's anchor, frames without an untrimmed
// size, and page images that outlive the image asset they came from.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Bundle extends CachingAssetBundle {
  final Map<String, ByteData> data = {};

  @override
  Future<ByteData> load(String key) async =>
      data[key] ?? (throw FlutterError('No asset $key'));
}

Future<ByteData> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF00FF00),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!;
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImageSync(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R16: a trimmed region anchors inside its frame', () {
    const region = SpriteRegion(
      name: 'a',
      pageIndex: 0,
      frame: Rect.fromLTWH(0, 0, 60, 70),
      trimmed: true,
      spriteSourceOffset: Offset(20, 10),
      sourceSize: Size(100, 100),
    );
    // The box's centre is 50 in; the frame starts 20 (10) in: 30 (40) into
    // the frame. It used to add the offset: 70 (60).
    expect(region.anchorX, 30);
    expect(region.anchorY, 40);
    const pivoted = SpriteRegion(
      name: 'b',
      pageIndex: 0,
      frame: Rect.fromLTWH(0, 0, 60, 70),
      trimmed: true,
      spriteSourceOffset: Offset(20, 10),
      sourceSize: Size(100, 100),
      pivot: Offset(0, 1),
    );
    expect(pivoted.anchorX, -20);
    expect(pivoted.anchorY, 90);
  });

  group('R17: a frame without a sourceSize', () {
    Future<SpriteAtlas> load(Map<String, dynamic> json) =>
        SpriteAtlas.fromJson(json, loadImage: (_) async => _image(16, 16));

    test('is as big as its frame (TexturePacker)', () async {
      final atlas = await load({
        'frames': {
          'a.png': {
            'frame': {'x': 0, 'y': 0, 'w': 6, 'h': 4},
          },
          'b.png': {
            'frame': {'x': 6, 'y': 0, 'w': 6, 'h': 4},
            'sourceSize': {'w': 8},
          },
        },
        'meta': {
          'image': 'sheet.png',
          'size': {'w': 16, 'h': 16},
        },
      });
      expect(atlas.requireRegion('a').sourceSize, const Size(6, 4));
      expect(atlas.requireRegion('b').sourceSize, const Size(8, 4));
      final sprite = atlas.createSprite('a');
      expect(sprite.getBounds()!.size, const Size(6, 4));
    });

    test('is as big as its frame (Aseprite)', () async {
      final atlas = await load({
        'frames': {
          'run 0': {
            'frame': {'x': 0, 'y': 0, 'w': 5, 'h': 7},
            'duration': 100,
          },
        },
        'meta': {
          'app': 'https://www.aseprite.org/',
          'image': 'sheet.png',
          'size': {'w': 16, 'h': 16},
          'frameTags': <dynamic>[],
        },
      });
      expect(atlas.requireRegion('run 0').sourceSize, const Size(5, 7));
    });
  });

  test('R18: an atlas page keeps its own image handle', () async {
    final bundle = _Bundle()
      ..data['assets/fx5/sheet.png'] = await _png(8, 8)
      ..data['assets/fx5/sheet.json'] = ByteData.sublistView(
        utf8.encode(
          jsonEncode({
            'frames': {
              'a.png': {
                'frame': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
                'sourceSize': {'w': 8, 'h': 8},
              },
            },
            'meta': {
              'image': 'sheet.png',
              'size': {'w': 8, 'h': 8},
            },
          }),
        ),
      );
    final assets = AssetManager(bundle: bundle);
    final atlas = await SpriteAtlas.fromAsset(
      'assets/fx5/sheet.json',
      assets: assets,
    );
    final page = atlas.pages.single;
    final cached = assets.get<ImageAsset>('assets/fx5/sheet.png')!.image!;
    final held = page.image!;
    expect(identical(held, cached), isFalse);
    expect(held.isCloneOf(cached), isTrue);

    // The image asset goes; the atlas, still cached, draws on.
    assets.unload('assets/fx5/sheet.png');
    expect(cached.debugDisposed, isTrue);
    expect(held.debugDisposed, isFalse);
    final sprite = atlas.createSprite('a');
    sprite.render(Canvas(ui.PictureRecorder()), Size.zero);

    // The atlas goes: its handle is released.
    assets.unload('assets/fx5/sheet.json');
    expect(held.debugDisposed, isTrue);
    expect(page.image, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('R18: a page given its image leaves it alone', () {
    final image = _image(4, 4);
    final page = SpriteAtlasPage(
      index: 0,
      imagePath: 'x.png',
      size: const Size(4, 4),
      image: image,
    );
    page.dispose();
    expect(image.debugDisposed, isFalse);
    expect(page.image, same(image));
  });
}
