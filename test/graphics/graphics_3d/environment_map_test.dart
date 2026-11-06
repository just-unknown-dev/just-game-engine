// The environment's map: with Reflections off over a skybox, the skybox
// only shows as the sky — nothing mirrors it and the two ambient colours
// light the scene, as with no map — and on again it lights the scene
// itself; a skybox file read again builds the map again, the old one shown
// until the new one is there.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, rendererNullShaders;

import 'fixtures.dart';

const _skyPath = 'assets/sky.hdr';

/// A flat Radiance `.hdr` [width]×[height] pixels, every one [rgbe].
Uint8List _hdr({
  int width = 8,
  int height = 4,
  List<int> rgbe = const [200, 100, 50, 129],
}) => Uint8List.fromList([
  ...ascii.encode(
    '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n',
  ),
  for (var i = 0; i < width * height; i++) ...rgbe,
]);

/// The shaders' diffuse light from nine spherical harmonics, facing [n].
List<double> _irradiance(Float32List sh, Vector3 n) => [
  for (var c = 0; c < 3; c++)
    math.max(
      0,
      sh[c] * 0.282095 +
          sh[3 + c] * 0.488603 * n.y +
          sh[6 + c] * 0.488603 * n.z +
          sh[9 + c] * 0.488603 * n.x +
          sh[12 + c] * 1.092548 * n.x * n.y +
          sh[15 + c] * 1.092548 * n.y * n.z +
          sh[18 + c] * 0.315392 * (3 * n.z * n.z - 1) +
          sh[21 + c] * 1.092548 * n.x * n.z +
          sh[24 + c] * 0.546274 * (n.x * n.x - n.y * n.y),
    ),
];

/// The shaders' hemisphere light facing [n] (up is -Y).
List<double> _hemisphere(
  (double, double, double) sky,
  (double, double, double) ground,
  Vector3 n,
) {
  final t = (0.5 - 0.5 * n.y).clamp(0.0, 1.0);
  return [
    ground.$1 + (sky.$1 - ground.$1) * t,
    ground.$2 + (sky.$2 - ground.$2) * t,
    ground.$3 + (sky.$3 - ground.$3) * t,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  late TestBundle bundle;
  final view = frameView(eye: Vector3(0, -3, -8));

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    bundle = TestBundle({_skyPath: _hdr()});
    engine = Engine(
      config: EngineConfig(services: [service]),
      context: EngineContext(bundle: bundle),
    );
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  /// Draws frames until [done], or gives up.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.sceneRenderer.update(view);
    }
    expect(done(), isTrue);
  }

  final normals = [
    Vector3(0, -1, 0),
    Vector3(0, 1, 0),
    Vector3(1, 0, 0),
    Vector3(0.6, -0.48, 0.64),
  ];

  test(
    'Reflections off over a skybox: nothing mirrors it, the hemisphere lights',
    () async {
      final environment = EnvironmentComponent(
        skybox: _skyPath,
        reflectionStrength: 0.8,
      );
      engine.world.createEntityWithComponents([environment]);
      final renderer = service.sceneRenderer..update(view);
      final env = renderer.scene.environment;
      await until(() => env.map != null);
      final map = env.map!;
      final own = Float32List.fromList(map.sh);
      expect(env.reflections, 0.8);
      expect(
        _irradiance(map.sh, normals.first),
        isNot(_hemisphere(env.ambientSky, env.ambientGround, normals.first)),
      );

      environment.reflections = false;
      renderer.update(view);
      expect(env.reflections, 0, reason: 'nothing mirrors the skybox');
      expect(env.skybox, isTrue, reason: 'it still shows as the sky');
      expect(env.map, same(map));
      for (final n in normals) {
        final got = _irradiance(map.sh, n),
            want = _hemisphere(env.ambientSky, env.ambientGround, n);
        for (var c = 0; c < 3; c++) {
          expect(
            got[c],
            closeTo(want[c], 1e-5),
            reason: 'lit as with no map, facing $n',
          );
        }
      }

      environment.reflections = true;
      renderer.update(view);
      expect(env.reflections, 0.8);
      expect(map.sh, own, reason: 'its own light back');
    },
  );

  test(
    'a skybox read again is built again, the old map shown meanwhile',
    () async {
      engine.world.createEntityWithComponents([
        EnvironmentComponent(skybox: _skyPath),
      ]);
      final renderer = service.sceneRenderer..update(view);
      final env = renderer.scene.environment;
      await until(() => env.map != null);
      final old = env.map!;
      bundle.files[_skyPath] = _hdr(rgbe: const [10, 200, 10, 130]);
      renderer.reload(_skyPath);
      renderer.update(view);
      expect(env.map, same(old), reason: 'until the new one is there');
      await until(() => !identical(env.map, old));
      expect(
        env.map!.sh[1],
        greaterThan(env.map!.sh[0]),
        reason: 'the new, green sky',
      );
    },
  );
}
