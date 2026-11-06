// RenderBatcher, through RenderSystem: a shape drawn through a 2-D material
// keeps its effects' sizes in the world whatever the zoom its sheet is
// drawn at — through the real shader, pixel by pixel.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _outline = 'outline.material2d.json';

final _files = {
  _outline: jsonEncode({
    'outline': {'color': 0xFF0000FF, 'width': 2},
  }),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;

  setUp(() async {
    world = World(extensions: [BuiltInComponents.extension])..initialize();
    world.context.material2DText = (path) async =>
        _files[path] ?? (throw StateError('no $path'));
    world.addSystem(RenderSystem(passes: const []));
    final library = world.context.material2DLibrary;
    for (var i = 0; i < 200; i++) {
      library.fileOf(_outline);
      if (library.program != null && library.fileOf(_outline) != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(library.program, isNotNull, reason: 'the shader loads in tests');
  });
  tearDown(() => world.dispose());

  /// The world drawn at [zoom] onto a canvas 48 units wide and 32 tall.
  Future<ByteData> frame(double zoom) async {
    final width = (48 * zoom).round(), height = (32 * zoom).round();
    final recorder = ui.PictureRecorder();
    world.render(Canvas(recorder)..scale(zoom), Size.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = (await image.toByteData())!;
    picture.dispose();
    image.dispose();
    return data;
  }

  /// The colour at world point ([x], [y]) of [d], drawn at [zoom].
  Color at(ByteData d, double zoom, double x, double y) {
    final px = (x * zoom).floor(), py = (y * zoom).floor();
    final i = (py * (48 * zoom).round() + px) * 4;
    return Color.fromARGB(
      d.getUint8(i + 3),
      d.getUint8(i),
      d.getUint8(i + 1),
      d.getUint8(i + 2),
    );
  }

  for (final zoom in [1.0, 2.0, 4.0]) {
    test('an outline is 2 units wide in the world at zoom $zoom', () async {
      // An 8 × 8 box at (24, 16): 20 to 28 across.
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(24, 16, 0)),
        Rectangle2DComponent(
          width: 8,
          height: 8,
          fillStyle: const ShapePaintStyle(color: Color(0xFF00FF00)),
          strokeStyle: const ShapePaintStyle(color: Color(0x00000000)),
          strokeWidth: 0,
        ),
        Material2DComponent(material: _outline),
      ]);
      // A first frame reads what it needs; the second draws through it.
      await frame(zoom);
      final d = await frame(zoom);
      expect(at(d, zoom, 24.5, 16.5), const Color(0xFF00FF00));
      expect(at(d, zoom, 28.5, 16.5), const Color(0xFF0000FF));
      expect(
        at(d, zoom, 29.5, 16.5),
        const Color(0xFF0000FF),
        reason: '2 units out — at zoom 2 it used to be 1 unit, at 4 half',
      );
      expect(at(d, zoom, 30.5, 16.5).a, 0, reason: 'and no further');
    });
  }
}
