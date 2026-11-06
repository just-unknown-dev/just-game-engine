// What the atlas parsers read: frame names with dots in them, pivots, and
// Aseprite's ping-pong-reverse direction and repeat counts.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImageSync(width, height);
}

Future<SpriteAtlas> _load(Map<String, dynamic> json) =>
    SpriteAtlas.fromJson(json, loadImage: (_) async => _image(64, 64));

Map<String, dynamic> _frame(double x, {Map<String, double>? pivot}) => {
  'frame': {'x': x, 'y': 0, 'w': 8, 'h': 16},
  'sourceSize': {'w': 8, 'h': 16},
  'pivot': ?pivot,
};

/// Records what a sprite draws: each image rect's destination, in canvas
/// space after the translation and scale.
class _Draws implements Canvas {
  final List<Rect> dests = [];
  Offset _at = Offset.zero;
  double _sx = 1, _sy = 1;

  @override
  void translate(double dx, double dy) =>
      _at = Offset(_at.dx + dx * _sx, _at.dy + dy * _sy);

  @override
  void scale(double sx, [double? sy]) {
    _sx *= sx;
    _sy *= sy ?? sx;
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    final a = Offset(_at.dx + dst.left * _sx, _at.dy + dst.top * _sy);
    final b = Offset(_at.dx + dst.right * _sx, _at.dy + dst.bottom * _sy);
    dests.add(Rect.fromPoints(a, b));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each parser reads its JSON at once, loading no image', () {
    final aseprite = {
      'frames': [
        {
          'filename': 'f0',
          'frame': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
          'duration': 100,
        },
      ],
      'meta': {
        'app': 'https://www.aseprite.org/',
        'image': 'hero.png',
        'size': {'w': 8, 'h': 8},
        'frameTags': [
          {'name': 'idle', 'from': 0, 'to': 0, 'direction': 'forward'},
        ],
      },
    };
    final grid = {
      'meta': {
        'image': 'grid.png',
        'frameWidth': 16,
        'frameHeight': 16,
        'columns': 2,
        'rows': 1,
      },
      'clips': {
        'run': {
          'frames': [0, 1],
        },
      },
    };
    final packed = {
      'frames': {'coin.png': _frame(0)},
      'meta': {'image': 'coins.png'},
    };
    for (final (json, clips) in [
      (aseprite, ['idle']),
      (grid, ['run']),
      (packed, <String>[]),
    ]) {
      // Typed, not awaited: a parse is synchronous.
      final SpriteAtlas atlas = AtlasParser.detect(
        json,
        jsonPath: 'assets/sprites/sheet.json',
      ).parse(json, 'assets/sprites/');
      expect(atlas.clipNames, clips);
      expect(atlas.pages.every((p) => p.image == null), isTrue);
    }
  });

  group('TexturePacker frame names', () {
    test('keep their dots, losing only an image extension', () async {
      final atlas = await _load({
        'frames': {
          'coin.1': _frame(0),
          'coin.2': _frame(8),
          'ui.v2/button': _frame(16),
          'hero.png': _frame(24),
          'Tree.PNG': _frame(32),
          'notes.txt': _frame(40),
        },
        'meta': {
          'image': 'sheet.v2.png',
          'size': {'w': 64, 'h': 64},
        },
      });
      expect(atlas.regionNames.toSet(), {
        'coin.1',
        'coin.2',
        'ui.v2/button',
        'hero',
        'Tree',
        'notes.txt',
      });
      expect(atlas.name, 'sheet.v2');
    });

    test('stripImageExtension looks after the last slash only', () {
      expect(AtlasParser.stripImageExtension('a.b/c'), 'a.b/c');
      expect(AtlasParser.stripImageExtension('a.b/c.jpeg'), 'a.b/c');
      expect(AtlasParser.stripImageExtension('.png'), '.png');
      expect(AtlasParser.stripImageExtension('dir/.png'), 'dir/.png');
    });
  });

  group('a pivot', () {
    late SpriteAtlas atlas;
    setUp(() async {
      atlas = await _load({
        'frames': {
          'feet.png': _frame(0, pivot: {'x': 0.5, 'y': 1.0}),
          'centre.png': _frame(8),
        },
        'meta': {
          'image': 'sheet.png',
          'size': {'w': 64, 'h': 64},
        },
      });
    });

    test('is the point placed on the position', () {
      final sprite = atlas.createSprite('feet', position: Vector3(100, 200, 0));
      expect(sprite.pivot, const Offset(0.5, 1));
      expect(sprite.bounds, const Rect.fromLTRB(96, 184, 104, 200));
      final draws = _Draws();
      sprite.render(draws, Size.zero);
      expect(draws.dests.single, const Rect.fromLTRB(96, 184, 104, 200));
      // A batch puts the frame's bottom middle on the position.
      expect((sprite.batchAnchorX, sprite.batchAnchorY), (4.0, 16.0));
    });

    test('mirrors and scales about the pivot', () {
      final sprite = atlas.createSprite(
        'feet',
        position: Vector3(100, 200, 0),
        scale: 2,
      )..flipY = true;
      expect(sprite.bounds, const Rect.fromLTRB(92, 200, 108, 232));
      final draws = _Draws();
      sprite.render(draws, Size.zero);
      expect(draws.dests.single, const Rect.fromLTRB(92, 200, 108, 232));
    });

    test('by default is the centre, as before', () {
      final sprite = atlas.createSprite(
        'centre',
        position: Vector3(100, 200, 0),
      );
      expect(sprite.bounds, const Rect.fromLTRB(96, 192, 104, 208));
    });
  });

  group('Aseprite tags', () {
    Future<SpriteAtlas> tagged(List<Map<String, Object>> tags) => _load({
      'frames': [
        for (var i = 0; i < 4; i++)
          {
            'filename': 'f$i',
            'frame': {'x': i * 8, 'y': 0, 'w': 8, 'h': 8},
            'duration': 100,
          },
      ],
      'meta': {
        'app': 'https://www.aseprite.org/',
        'image': 'sheet.png',
        'size': {'w': 32, 'h': 8},
        'frameTags': tags,
      },
    });

    List<String> frames(SpriteAtlas atlas, String clip) => [
      for (final f in atlas.requireClip(clip).frames) f.regionName,
    ];

    test('ping-pong reverse goes back first, then there', () async {
      final atlas = await tagged([
        {'name': 'pr', 'from': 0, 'to': 3, 'direction': 'pingpong_reverse'},
      ]);
      expect(frames(atlas, 'pr'), ['f3', 'f2', 'f1', 'f0', 'f1', 'f2']);
      expect(atlas.requireClip('pr').loop, isTrue);
    });

    test('a repeat count plays that many passes, then stops', () async {
      final atlas = await tagged([
        {
          'name': 'fw',
          'from': 0,
          'to': 1,
          'direction': 'forward',
          'repeat': '3',
        },
        {'name': 'rv', 'from': 2, 'to': 3, 'direction': 'reverse', 'repeat': 2},
        {
          'name': 'pp',
          'from': 0,
          'to': 2,
          'direction': 'pingpong',
          'repeat': '3',
        },
        {
          'name': 'pr',
          'from': 0,
          'to': 2,
          'direction': 'pingpong_reverse',
          'repeat': '2',
        },
        {'name': 'forever', 'from': 0, 'to': 1, 'repeat': '0'},
      ]);
      expect(frames(atlas, 'fw'), ['f0', 'f1', 'f0', 'f1', 'f0', 'f1']);
      expect(frames(atlas, 'rv'), ['f3', 'f2', 'f3', 'f2']);
      expect(frames(atlas, 'pp'), ['f0', 'f1', 'f2', 'f1', 'f0', 'f1', 'f2']);
      expect(frames(atlas, 'pr'), ['f2', 'f1', 'f0', 'f1', 'f2']);
      for (final clip in ['fw', 'rv', 'pp', 'pr']) {
        expect(atlas.requireClip(clip).loop, isFalse, reason: clip);
      }
      expect(atlas.requireClip('forever').loop, isTrue);
    });
  });
}
