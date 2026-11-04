// An entity's own values for its material files: read through a view, not
// a copy; and, animated, drawn with one material made for them at a time —
// each frame's is let go once the next one is drawn.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, rendererNullShaders;

import 'fixtures.dart';

const _red = 'assets/materials/red.material.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('its values are a view that follows set and remove, not a copy', () {
    final overrides = MaterialOverrides3DComponent(values: {'metallic': 0.5});
    final values = overrides.values;
    expect(overrides.values, same(values));
    overrides.set('roughness', 0.2);
    expect(values, {'metallic': 0.5, 'roughness': 0.2});
    overrides.remove('metallic');
    expect(values, {'roughness': 0.2});
    expect(() => values['metallic'] = 1, throwsUnsupportedError);
    overrides.values = {'metallic': 1};
    expect(overrides.values, {'metallic': 1});
    expect(values, {'roughness': 0.2}, reason: 'the old map, given a new one');
  });

  test(
    'animated, it is drawn with one material made for its values at a time',
    () async {
      final service = Graphics3D(
        device: NullGpuDevice(shaders: rendererNullShaders),
      );
      final engine = Engine(
        config: EngineConfig(services: [service]),
        context: EngineContext(
          bundle: TestBundle({
            _red: Uint8List.fromList(
              utf8.encode(const Material3DFile(color: 0xFFFF0000).encode()),
            ),
          }),
        ),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      final overrides = MaterialOverrides3DComponent(values: {'metallic': 0.0});
      engine.world.createEntityWithComponents([
        TransformComponent(),
        Cube3DComponent(material: _red),
        overrides,
      ]);
      final renderer = service.sceneRenderer;
      final view = frameView(eye: Vector3(0, -3, -8));
      for (var i = 0; i < 100 && renderer.materials.fileOf(_red) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        renderer.update(view);
      }
      renderer.update(view);
      final first = renderer.debugShapeInstances.single!.material;
      expect(first.data.metallic, 0);

      for (var i = 1; i <= 100; i++) {
        overrides.set('metallic', i / 100);
        renderer.update(view);
      }
      final drawn = renderer.debugShapeInstances.single!.material;
      expect(drawn.data.metallic, 1);
      expect(
        renderer.materials.gpuOf(_red, overrides: {'metallic': 1.0}),
        same(drawn),
      );
      expect(
        renderer.materials.gpuOf(_red, overrides: {'metallic': 0.0}),
        isNot(same(first)),
        reason: 'the first frame\'s was let go once no longer drawn',
      );
    },
  );
}
