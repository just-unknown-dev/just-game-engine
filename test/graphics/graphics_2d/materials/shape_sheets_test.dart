// Shapes drawn through a 2-D material are drawn into an image (a sheet)
// once, and drawn again only when they change. A frame can draw the world
// more than once at different scales — an editor's game preview beside its
// zoomed view — and each scale keeps its own sheet: one sheet an entity,
// drawn again whenever the scale changed, was drawn again at every render
// and filled the GPU's memory.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/graphics/graphics_2d/materials/material_2d_shapes.dart'
    show ShapeSheet, ShapeSheets;

/// A square drawn in its own space, counting how often it is drawn.
final class _Square extends Renderable {
  int draws = 0;

  @override
  void render(Canvas canvas, Size size) {
    draws++;
    canvas.drawRect(
      const Rect.fromLTWH(-8, -8, 16, 16),
      Paint()..color = const Color(0xFFFF0000),
    );
  }

  @override
  Rect? get bounds => const Rect.fromLTWH(-8, -8, 16, 16);
}

/// A [width] × [height] box drawn in its own space, around its origin.
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

void main() {
  late World world;
  late ShapeSheets sheets;

  setUp(() {
    world = World()..initialize();
    sheets = ShapeSheets();
  });

  tearDown(() => sheets.clear());

  test('two views at different scales each keep their sheet', () {
    final entity = world.createEntity();
    final square = _Square();
    final near = <ShapeSheet>{};
    final far = <ShapeSheet>{};
    for (var i = 0; i < 6; i++) {
      // The zoomed view, then the preview, each frame.
      sheets.beginFrame();
      near.add(sheets.sheetOf(entity, square, 'look', 2)!);
      sheets.beginFrame();
      far.add(sheets.sheetOf(entity, square, 'look', 1)!);
    }
    expect(square.draws, 2);
    expect(near, hasLength(1));
    expect(far, hasLength(1));
    expect(near.single.resolution, 2);
    expect(far.single.resolution, 1);
    expect(sheets.length, 1);
    expect(sheets.sheetCount, 2);
  });

  test('a changed look draws again at that scale only', () {
    final entity = world.createEntity();
    final square = _Square();
    sheets.beginFrame();
    final first = sheets.sheetOf(entity, square, 'look', 2)!;
    sheets.sheetOf(entity, square, 'look', 1);
    expect(square.draws, 2);

    sheets.beginFrame();
    final changed = sheets.sheetOf(entity, square, 'other', 2)!;
    expect(square.draws, 3);
    expect(changed, isNot(same(first)));
    expect(sheets.sheetCount, 2);
  });

  test('a sheet nobody draws with is let go of', () {
    final entity = world.createEntity();
    final square = _Square();
    sheets.beginFrame();
    final sheet = sheets.sheetOf(entity, square, 'look', 4)!;
    for (var i = 0; i < ShapeSheets.keepFor; i++) {
      sheets.beginFrame();
    }
    expect(sheets.sheetCount, 1, reason: 'kept for keepFor renders unused');
    sheets.beginFrame();
    expect(sheets.length, 0);
    expect(sheets.sheetCount, 0);
    // Its image goes two renders later, once no draw can still hold it.
    expect(sheet.image.debugDisposed, isFalse);
    sheets
      ..beginFrame()
      ..beginFrame();
    expect(sheet.image.debugDisposed, isTrue);

    sheets.sheetOf(entity, square, 'look', 4);
    expect(square.draws, 2);
  });

  test('clear lets go of every scale of every entity', () {
    final a = world.createEntity();
    final b = world.createEntity();
    final square = _Square();
    sheets.beginFrame();
    final held = <ui.Image>[
      for (final entity in [a, b])
        for (final scale in [1.0, 2.0, 4.0])
          sheets.sheetOf(entity, square, 'look', scale)!.image,
    ];
    expect(sheets.sheetCount, 6);
    sheets.clear();
    expect(sheets.sheetCount, 0);
    expect(held.every((image) => image.debugDisposed), isTrue);
  });

  test('many views a frame each keep their sheet', () {
    final entity = world.createEntity();
    final square = _Square();
    // A zoomed-in view, then an editor's four split panes and its game
    // preview at another scale: six renders a frame.
    const scales = [4.0, 1.0, 1.0, 1.0, 1.0, 1.0];
    for (var frame = 0; frame < 5; frame++) {
      for (final scale in scales) {
        sheets.beginFrame();
        sheets.sheetOf(entity, square, 'look', scale);
      }
    }
    expect(square.draws, 2, reason: 'once a scale, never again');
  });

  test('a shape too big for an image at 1 is drawn smaller, to fit', () {
    expect(
      ShapeSheets.resolutionFor(1, const Rect.fromLTWH(0, 0, 5000, 64)),
      0.25,
    );
    expect(
      ShapeSheets.resolutionFor(4, const Rect.fromLTWH(0, 0, 1000, 64)),
      2,
    );
    expect(
      ShapeSheets.resolutionFor(1, const Rect.fromLTWH(0, 0, 2048, 64)),
      1,
    );

    final entity = world.createEntity();
    sheets.beginFrame();
    final sheet = sheets.sheetOf(entity, _Box(5000, 64), 'look', 1)!;
    expect(sheet.resolution, 0.25);
    expect(sheet.image.width, lessThanOrEqualTo(ShapeSheets.maxSide));
    expect(sheet.image.width, 1250);
    expect(sheet.image.height, 16);
  });

  test('a shape too big for any image has no sheet', () {
    final entity = world.createEntity();
    sheets.beginFrame();
    expect(sheets.sheetOf(entity, _Box(1e9, 64), 'look', 1), isNull);
  });
}
