// Screen materials: the whole view drawn into an image and painted back
// through a 2-D material of the `screen` kind — the game's drawing under
// it, an editor's (overlay hooks of order 100) over it — chosen from the
// world's ScreenMaterial components.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _grey = 'assets/fx/grey.material2d.json';
const _vignette = 'assets/fx/vignette.material2d.json';
const _crt = 'assets/fx/crt.material2d.json';

final _files = {
  _grey: jsonEncode({
    'kind': 'screen',
    'greyscale': {'amount': 1},
  }),
  _vignette: jsonEncode({
    'kind': 'screen',
    'vignette': {'amount': 1, 'softness': 1},
  }),
  _crt: jsonEncode({
    'kind': 'screen',
    'crt': {'curvature': 1, 'aberration': 0},
  }),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;

  setUp(() async {
    engine = Engine();
    await engine.initialize();
    engine.context.material2DText = (path) async =>
        _files[path] ?? (throw StateError('no $path'));
    engine.rendering
      ..backgroundColor = const Color(0xFFFF0000)
      ..pixelRatio = 1;
    final library = Material2DLibrary.of(engine.context);
    for (final p in _files.keys) {
      library.fileOf(p);
    }
    library.screenProgram;
    for (var i = 0; i < 200; i++) {
      if (library.screenProgram != null &&
          _files.keys.every((p) => library.fileOf(p) != null))
        break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(library.screenProgram, isNotNull);
  });
  tearDown(() => engine.dispose());

  Future<ByteData> frame() async {
    final recorder = ui.PictureRecorder();
    engine.rendering.render(Canvas(recorder), const Size(40, 30));
    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 30);
    final data = (await image.toByteData())!;
    picture.dispose();
    image.dispose();
    return data;
  }

  Color at(ByteData d, int x, int y) {
    final i = (y * 40 + x) * 4;
    return Color.fromARGB(
      d.getUint8(i + 3),
      d.getUint8(i),
      d.getUint8(i + 1),
      d.getUint8(i + 2),
    );
  }

  test(
    'the view drawn through the screen material; an editor drawn over it',
    () async {
      engine.rendering.overlayHooks.add(
        (canvas, size) => canvas.drawRect(
          const Rect.fromLTWH(0, 0, 4, 4),
          Paint()..color = const Color(0xFFFF0000),
        ),
        order: RenderingEngine.screenPassOrder,
      );
      var d = await frame();
      expect(
        at(d, 20, 15),
        const Color(0xFFFF0000),
        reason: 'no screen material yet',
      );

      final holder = engine.world.createEntityWithComponents([
        ScreenMaterial(material: _grey),
      ]);
      d = await frame();
      final grey = at(d, 20, 15);
      expect((grey.r * 255).round(), closeTo(76, 2), reason: 'red, as grey');
      expect(grey.r, closeTo(grey.g, 0.01));
      expect(
        at(d, 1, 1),
        const Color(0xFFFF0000),
        reason: 'the overlay at order 100 is over it, untouched',
      );

      holder.getComponent<ScreenMaterial>()!.enabled = false;
      d = await frame();
      expect(at(d, 20, 15), const Color(0xFFFF0000), reason: 'switched off');
    },
  );

  test('the highest order wins; its overrides count', () async {
    engine.world.createEntityWithComponents([
      ScreenMaterial(material: _grey, order: 1),
    ]);
    final vignette = ScreenMaterial(material: _vignette, order: 2);
    engine.world.createEntityWithComponents([vignette]);
    var d = await frame();
    expect(at(d, 0, 0).r, lessThan(0.2), reason: 'a dark corner');
    final middle = at(d, 20, 15);
    expect(middle.r, greaterThan(0.98), reason: 'the middle all but untouched');
    expect(middle.g, 0, reason: 'not grey: the vignette won');

    vignette.set('vignette.amount', 0.0);
    d = await frame();
    expect(
      at(d, 0, 0),
      const Color(0xFFFF0000),
      reason: 'its own amount, none',
    );
  });

  // The shader says "past the edge" at its end rather than returning early:
  // an early return with its gradient loop crashed Impeller's OpenGL ES
  // compile on Windows.
  test("past a CRT's curved edge, black; inside, the frame", () async {
    engine.world.createEntityWithComponents([ScreenMaterial(material: _crt)]);
    final d = await frame();
    expect(
      at(d, 0, 0),
      const Color(0xFF000000),
      reason: 'a corner, curved off',
    );
    expect(at(d, 20, 15), const Color(0xFFFF0000), reason: 'the middle');
  });

  test('a ScreenMaterial is saved with its entity', () {
    final definitions = engine.context.definitions;
    final c = ScreenMaterial(
      material: _grey,
      order: 3,
      enabled: false,
      overrides: {'greyscale.amount': 0.5},
    );
    final back =
        definitions.decode(
              jsonDecode(jsonEncode(definitions.encode(c)))
                  as Map<String, dynamic>,
            )!
            as ScreenMaterial;
    expect(
      [back.material, back.order, back.enabled, back.overrides],
      [
        _grey,
        3,
        false,
        {'greyscale.amount': 0.5},
      ],
    );
  });
}
