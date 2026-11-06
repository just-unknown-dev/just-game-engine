// Batched sprites that are mirrored, trimmed, turned or pivoted draw what
// they draw by themselves, pixel for pixel — so they batch, where each used
// to draw alone and split the batch around it — and a sprite's bounds are
// never inside out.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/rendering/sprite_batching.dart';

/// Every pixel a different opaque colour.
Future<ui.Image> _patterned(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()..color = Color.fromARGB(255, 16 * x, 16 * y, (x * 7 + y) % 256),
      );
    }
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

const _size = 64;

Future<Uint8List> _pixels(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size, _size);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Counts the draw calls made on it.
class _Counting implements Canvas {
  int draws = 0;

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => draws++;

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) =>
      draws++;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      draws++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image atlas;
  setUpAll(() async => atlas = await _patterned(16, 16));

  Sprite plain({Offset at = const Offset(32, 32)}) => Sprite(
    image: atlas,
    sourceRect: const Rect.fromLTWH(2, 2, 8, 6),
    position: Vector3(at.dx, at.dy, 0),
  )..filterQuality = FilterQuality.none;

  // 6×8 of pixels cut from a 10×12 box, 2 in and 1 down.
  const trimmed = SpriteRegion(
    name: 't',
    pageIndex: 0,
    frame: Rect.fromLTWH(0, 0, 6, 8),
    trimmed: true,
    spriteSourceOffset: Offset(2, 1),
    sourceSize: Size(10, 12),
  );
  // The same, stored a quarter turn clockwise at (8, 0): 8 wide, 6 high.
  const turned = SpriteRegion(
    name: 'r',
    pageIndex: 0,
    frame: Rect.fromLTWH(8, 0, 6, 8),
    rotated: true,
    trimmed: true,
    spriteSourceOffset: Offset(2, 1),
    sourceSize: Size(10, 12),
  );

  AtlasRegionSprite frame(SpriteRegion region, {Offset? pivot}) {
    final sprite = AtlasRegionSprite(
      region: region,
      image: atlas,
      position: Vector3(32, 32, 0),
    )..filterQuality = FilterQuality.none;
    if (pivot != null) sprite.pivot = pivot;
    return sprite;
  }

  /// Draws [sprites] one by one, then in one batch, and compares.
  Future<void> drawsTheSame(List<Sprite> sprites) async {
    final alone = await _pixels((c) {
      for (final s in sprites) {
        s.render(c, const Size(64, 64));
      }
    });
    var draws = 0;
    final batched = await _pixels((c) {
      final plan = SpriteBatchPlan();
      final batch = SpriteBatch(atlas, filterQuality: FilterQuality.none);
      for (final s in sprites) {
        expect(plan.plan(s, mirrors: true), isTrue, reason: '$s batches');
        plan.addTo(batch);
      }
      batch.flush(c);
      draws++;
    });
    expect(alone.any((b) => b != 0), isTrue, reason: 'something is drawn');
    var differing = 0;
    for (var i = 0; i < alone.length; i++) {
      if (alone[i] != batched[i]) differing++;
    }
    expect(differing, 0, reason: 'bytes differing');
    expect(draws, 1);
  }

  group('a batch draws as the sprite does', () {
    test('unmirrored', () => drawsTheSame([plain()]));

    test('mirrored either way, or both', () async {
      await drawsTheSame([plain()..flipX = true]);
      await drawsTheSame([plain()..flipY = true]);
      await drawsTheSame([
        plain()
          ..flipX = true
          ..flipY = true,
      ]);
    });

    test('mirrored by a negative scale, turned and scaled', () async {
      await drawsTheSame([plain()..scale = Vector3(-1, 1, 1)]);
      await drawsTheSame([plain()..scale = Vector3(-2, -2, 1)]);
      await drawsTheSame([
        plain()
          ..flipX = true
          ..rotation = math.pi / 2,
      ]);
    });

    test('tinted and faded, mirrored', () async {
      await drawsTheSame([
        plain()
          ..flipX = true
          ..tint = const Color(0xFF80FF40)
          ..opacity = 0.5,
      ]);
    });

    test('a trimmed frame, mirrored or not', () async {
      await drawsTheSame([frame(trimmed)]);
      await drawsTheSame([frame(trimmed)..flipX = true]);
      await drawsTheSame([frame(trimmed)..flipY = true]);
    });

    test('a frame stored turned, mirrored or not', () async {
      await drawsTheSame([frame(turned)]);
      await drawsTheSame([frame(turned)..flipX = true]);
      await drawsTheSame([
        frame(turned)
          ..flipX = true
          ..flipY = true,
      ]);
    });

    test('pivoted on its feet', () async {
      await drawsTheSame([frame(trimmed, pivot: const Offset(0.5, 1))]);
      await drawsTheSame([
        frame(turned, pivot: const Offset(0.5, 1))..flipX = true,
      ]);
      await drawsTheSame([
        plain()
          ..pivot = const Offset(0, 1)
          ..flipX = true,
      ]);
    });

    test('mixed, overlapping, in the order queued', () async {
      await drawsTheSame([
        plain(at: const Offset(30, 30)),
        plain(at: const Offset(33, 31))..flipX = true,
        frame(trimmed)..tint = const Color(0xFFFF0000),
        plain(at: const Offset(35, 33))..flipY = true,
      ]);
    });
  });

  test('a batch that cannot mirror is not given a mirrored sprite', () {
    final plan = SpriteBatchPlan();
    expect(plan.plan(plain()..flipX = true), isFalse);
    expect(plan.plan(plain()..scale = Vector3(-1, 1, 1)), isFalse);
    expect(plan.plan(plain()), isTrue);
    expect(SpriteBatchCache().mirrors, isTrue);
    expect(SpriteBatchCache((image) => SpriteBatch(image)).mirrors, isFalse);
  });

  group('draw calls for 100 sprites of one image', () {
    /// Draws [sprites] as the render system does: batched where the plan
    /// allows, by itself otherwise, with what was batched before it first.
    int drawCalls(List<Sprite> sprites, {required bool mirrors}) {
      final canvas = _Counting();
      final plan = SpriteBatchPlan();
      final batch = SpriteBatch(atlas, filterQuality: FilterQuality.none);
      for (final s in sprites) {
        if (plan.plan(s, mirrors: mirrors)) {
          plan.addTo(batch);
        } else {
          batch.flush(canvas);
          s.render(canvas, Size.zero);
        }
      }
      batch.flush(canvas);
      return canvas.draws;
    }

    test('half facing left: one, where it was a hundred', () {
      final sprites = [
        for (var i = 0; i < 100; i++)
          plain(at: Offset(i.toDouble(), 0))..flipX = i.isOdd,
      ];
      expect(drawCalls(sprites, mirrors: false), 100);
      expect(drawCalls(sprites, mirrors: true), 1);
    });

    test('trimmed and turned frames: one', () {
      final sprites = [
        for (var i = 0; i < 100; i++) frame(i.isEven ? trimmed : turned),
      ];
      expect(drawCalls(sprites, mirrors: true), 1);
    });
  });

  group('bounds are never inside out', () {
    test('of a sprite scaled by a negative amount, or mirrored', () {
      final sprite = plain()..scale = Vector3(-2, 1, 1);
      expect(sprite.bounds, const Rect.fromLTRB(24, 29, 40, 35));
      sprite
        ..scale = Vector3(1, -1, 1)
        ..flipY = true;
      expect(sprite.bounds, const Rect.fromLTRB(28, 29, 36, 35));
    });

    test('of a nine-slice sprite', () {
      final nine = NineSliceSprite(
        image: atlas,
        size: const Size(20, 10),
        borderInsets: const EdgeInsets.all(2),
        position: Vector3(50, 50, 0),
        scale: Vector3(-1, -2, 1),
      );
      expect(nine.bounds, const Rect.fromLTRB(40, 40, 60, 60));
    });
  });
}
