// Material2DBatch, drawn through the real shader and checked pixel by
// pixel: a shape's sheet drawn at any resolution has its effects the same
// size in the world, a shape too big for an image at 1 still takes its
// material, and an entity's overridden values are worked out once yet
// follow every change.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/graphics/graphics_2d/materials/material_2d_batch.dart'
    show Material2DBatch;
import 'package:just_game_engine/src/graphics/graphics_2d/materials/material_2d_shapes.dart'
    show ShapeSheets;

const _outline = 'outline.material2d.json';
const _flash = 'flash.material2d.json';

final _files = <String, String>{
  _outline: jsonEncode({
    'outline': {'color': 0xFF0000FF, 'width': 2},
  }),
  _flash: jsonEncode({
    'flash': {'color': 0xFFFF0000, 'amount': 1},
  }),
};

/// A green [width] × [height] box drawn in its own space, around its origin.
final class _Box extends Renderable {
  _Box(this.width, this.height);
  final double width, height;

  @override
  void render(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromCenter(center: Offset.zero, width: width, height: height),
    Paint()..color = const Color(0xFF00FF00),
  );

  @override
  Rect? get bounds =>
      Rect.fromCenter(center: Offset.zero, width: width, height: height);
}

Future<ui.Image> _green(int size) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  return picture.toImage(size, size).whenComplete(picture.dispose);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Material2DLibrary library;
  late Material2DBatch batch;
  late ShapeSheets sheets;
  late World world;

  setUp(() async {
    library = Material2DLibrary((path) async => _files[path]!);
    for (final path in _files.keys) {
      library.fileOf(path);
    }
    library.program;
    for (var i = 0; i < 200; i++) {
      if (library.program != null &&
          _files.keys.every((p) => library.fileOf(p) != null)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(library.program, isNotNull, reason: 'the shader loads in tests');
    batch = Material2DBatch(library);
    sheets = ShapeSheets();
    world = World()..initialize();
  });

  tearDown(() {
    batch.dispose();
    sheets.clear();
    world.dispose();
  });

  /// What [draw] puts on a 48 × 32 canvas.
  Future<ByteData> frame(void Function(Canvas canvas) draw) async {
    final recorder = ui.PictureRecorder();
    batch.beginFrame();
    draw(Canvas(recorder));
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

  /// An 8 × 8 box at (24, 16) — 20 to 28 across — drawn from its sheet at
  /// [scale] through the outline material, its own [overrides] on top.
  Future<ByteData> outlinedBox(
    double scale, {
    Map<String, Object> overrides = const {},
  }) {
    final sheet = sheets.sheetOf(
      world.createEntity(),
      _Box(8, 8),
      'box',
      scale,
    )!;
    expect(sheet.resolution, scale);
    return frame((canvas) {
      batch.begin(
        _outline,
        library.fileOf(_outline)!,
        sheet.image,
        FilterQuality.medium,
        unitScale: sheet.resolution,
      );
      expect(
        batch.addBox(
          sheet.frame,
          sheet.bounds,
          x: 24,
          y: 16,
          overrides: overrides,
        ),
        isTrue,
      );
      batch.flush(canvas, 0);
    });
  }

  group('a shape sheet at any resolution', () {
    for (final scale in [1.0, 2.0, 4.0]) {
      test('has an outline 2 units wide at resolution $scale', () async {
        final d = await outlinedBox(scale);
        expect(at(d, 24, 16), const Color(0xFF00FF00), reason: 'the box');
        expect(at(d, 28, 16), const Color(0xFF0000FF));
        expect(at(d, 29, 16), const Color(0xFF0000FF), reason: '2 units out');
        expect(at(d, 30, 16).a, 0, reason: 'and no further');
        expect(at(d, 18, 16), const Color(0xFF0000FF), reason: 'left too');
        expect(at(d, 17, 16).a, 0);
      });

      test(
        'has an overridden outline 3 units wide at resolution $scale',
        () async {
          final d = await outlinedBox(scale, overrides: {'outline.width': 3});
          expect(at(d, 30, 16), const Color(0xFF0000FF), reason: '3 units out');
          expect(at(d, 31, 16).a, 0);
        },
      );
    }

    test("its effects' reach grows with the resolution", () {
      final file = library.fileOf(_outline)!;
      expect(Material2DShader.reach(file, const {}), 2);
      expect(Material2DShader.reach(file, const {}, unitScale: 4), 8);
      expect(
        Material2DShader.reach(file, {'outline.width': 3}, unitScale: 2),
        6,
      );
    });

    test('of another resolution does not join the batch', () {
      final a = sheets.sheetOf(world.createEntity(), _Box(8, 8), 'a', 2)!;
      batch.begin(
        _outline,
        library.fileOf(_outline)!,
        a.image,
        FilterQuality.medium,
        unitScale: 2,
      );
      expect(
        batch.accepts(_outline, a.image, FilterQuality.medium, unitScale: 2),
        isTrue,
      );
      expect(batch.accepts(_outline, a.image, FilterQuality.medium), isFalse);
    });
  });

  test('a shape too big for an image at 1 still takes its material', () async {
    final sheet = sheets.sheetOf(
      world.createEntity(),
      _Box(5000, 16),
      'ground',
      1,
    )!;
    expect(sheet.resolution, lessThan(1));
    final d = await frame((canvas) {
      batch.begin(
        _flash,
        library.fileOf(_flash)!,
        sheet.image,
        FilterQuality.medium,
        unitScale: sheet.resolution,
      );
      expect(batch.addBox(sheet.frame, sheet.bounds, x: 24, y: 16), isTrue);
      batch.flush(canvas, 0);
    });
    expect(at(d, 2, 16), const Color(0xFFFF0000), reason: 'flashed red');
    expect(at(d, 46, 16), const Color(0xFFFF0000));
  });

  group('overridden values', () {
    late ui.Image green;
    setUp(() async => green = await _green(8));

    Future<ByteData> flashed(Map<String, Object> overrides) => frame((canvas) {
      final sprite = Sprite(image: green)..position.setValues(16, 16, 0);
      batch.begin(_flash, library.fileOf(_flash)!, green, FilterQuality.none);
      expect(batch.addSprite(sprite, seed: 1, overrides: overrides), isTrue);
      batch.flush(canvas, 0);
    });

    test('follow a map changed in place', () async {
      final overrides = <String, Object>{'flash.amount': 1.0};
      expect(at(await flashed(overrides), 16, 16), const Color(0xFFFF0000));
      overrides['flash.amount'] = 0.0;
      expect(at(await flashed(overrides), 16, 16), const Color(0xFF00FF00));
      overrides['flash.color'] = 0xFF0000FF;
      overrides['flash.amount'] = 1.0;
      expect(at(await flashed(overrides), 16, 16), const Color(0xFF0000FF));
      overrides.remove('flash.color');
      expect(at(await flashed(overrides), 16, 16), const Color(0xFFFF0000));
    });

    test("follow a component's changes", () async {
      final m = Material2DComponent(
        material: _flash,
        overrides: {'flash.amount': 0.0},
      );
      expect(at(await flashed(m.overrides), 16, 16), const Color(0xFF00FF00));
      m.set('flash.amount', 1.0);
      expect(at(await flashed(m.overrides), 16, 16), const Color(0xFFFF0000));
      m.remove('flash.amount');
      expect(at(await flashed(m.overrides), 16, 16), const Color(0xFFFF0000));
    });
  });

  group("a component's overrides", () {
    test('are one map until they change, which never changes', () {
      final m = Material2DComponent(overrides: {'flash.amount': 0.5});
      final first = m.overrides;
      expect(m.overrides, same(first), reason: 'not copied every read');
      m.set('flash.amount', 1.0);
      expect(m.overrides, isNot(same(first)));
      expect(first, {'flash.amount': 0.5}, reason: 'handed out, kept as was');
      expect(m.overrides, {'flash.amount': 1.0});
      expect(() => m.overrides['x'] = 1, throwsUnsupportedError);
      m.set('flash.amount', 1.0);
      final second = m.overrides;
      m.remove('nothing');
      expect(m.overrides, same(second), reason: 'nothing changed');
      m.overrides = {'dissolve.amount': 0.2};
      expect(m.overrides, {'dissolve.amount': 0.2});
    });

    test("of a screen material, the same", () {
      final s = ScreenMaterialComponent(overrides: {'vignette.amount': 0.5});
      final first = s.overrides;
      expect(s.overrides, same(first));
      s.set('vignette.amount', 0.75);
      expect(s.overrides, isNot(same(first)));
      expect(first, {'vignette.amount': 0.5});
      expect(s.overrides, {'vignette.amount': 0.75});
    });
  });
}
