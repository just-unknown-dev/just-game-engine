@Tags(['gpu', 'graphics3d'])
library;

// A scene file, through the engine, to pixels: the extension decodes it, the
// service loads the model, the scene renderer draws it into a texture and
// that texture onto the frame's canvas.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

const _size = 64;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = gpuUnavailableReason();

  test('a red cube in a scene file is drawn in front of the sky', () async {
    final service = Graphics3D();
    final engine = Engine(
      config: EngineConfig(graphics3D: service),
      context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
    );
    await engine.initialize();
    addTearDown(engine.dispose);
    expect(service.isSupported, isTrue, reason: service.unsupportedReason);

    SceneLoader.load(
      engine.world,
      sceneJson(engine.context, {
        // Centred on the origin: the model rests on y = 0, so lift it half.
        'Crate': [TransformComponent(position: Vector3(0, 0.5, 0)), ModelComponent(model: cubePath)],
        'Sun': [
          TransformComponent(euler: Vector3(-1.2, 0.4, 0)),
          LightComponent(kind: LightKind.directional, intensity: 3),
        ],
        'Sky': [EnvironmentComponent()],
      }),
    );
    final view = frameView(
      eye: Vector3(0, -1, -4),
      size: const Size(_size + 0.0, _size + 0.0),
    );
    final renderer = service.sceneRenderer..pixelRatio = 1;
    renderer.update(view);
    await service.models.load(cubePath);

    final recorder = ui.PictureRecorder();
    renderer.render(ui.Canvas(recorder), view);
    expect(await renderer.lastFrame, isTrue);
    final image = await recorder.endRecording().toImage(_size, _size);
    final px = await readPixels(image);

    final centre = px.atFraction(0.5, 0.55);
    final corner = px.at(1, 1);
    // ignore: avoid_print
    print('ENGINE centre $centre corner $corner ${service.renderer.stats}');
    expect(centre[0], greaterThan(centre[1] + 40), reason: 'red cube in the middle: $centre');
    expect(corner[2], greaterThan(corner[0]), reason: 'blue sky above: $corner');
    expect(service.renderer.stats.instances, 1);
  }, skip: skip);
}
