@Tags(['gpu', 'graphics3d'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

const _size = 64;

void main() {
  final skip = gpuUnavailableReason();
  late GpuDevice device;
  late Renderer3D renderer;
  late GraphicsShapes shapes;
  final files = <String, Uint8List>{};

  setUpAll(() async {
    if (skip != null) return;
    device = createGpuDevice()!;
    renderer = await Renderer3D.create(device);
    shapes = GraphicsShapes(renderer.uploader, (path) async => files[path]!);
  });

  RenderView camera({Vector3? eye}) {
    final view = RenderView()
      ..width = _size
      ..height = _size;
    view.lookAt(eye ?? Vector3(0, 0, -4), Vector3.zero());
    view.projection.setPerspectiveYDown(math.pi / 3, 1, 0.1, 100);
    return view;
  }

  /// A dark scene with no sky, lit by a sun travelling along [sun].
  RenderScene dark({Vector3? sun}) {
    final scene = RenderScene();
    scene.environment
      ..sky = false
      ..clearColor = (0, 0, 0)
      ..ambientSky = (0.02, 0.02, 0.02)
      ..ambientGround = (0.02, 0.02, 0.02);
    scene.sun
      ..enabled = sun != null
      ..intensity = 3;
    if (sun != null) scene.sun.direction.setFrom(sun..normalize());
    return scene;
  }

  MeshInstance place(RenderScene scene, Primitive3D shape, {Vector3? at}) {
    final instance = MeshInstance(
      shapes.meshFor(shape, Vector3(1, 1, 1))!,
      shapes.materialFor(shape),
      Matrix4.translationValues(at?.x ?? 0, at?.y ?? 0, at?.z ?? 0),
    );
    scene.instances.add(instance);
    return instance;
  }

  Future<RgbaPixels> draw(RenderScene scene, RenderView view) async {
    final surface = device.createSurface(_size, _size);
    expect(await renderer.render(scene, view, surface), isTrue);
    return readPixels(surface.image!);
  }

  test('a cube faces out: the face towards the camera takes the light from in front', () async {
    Future<int> red(Vector3 sun) async {
      final scene = dark(sun: sun);
      place(scene, Cube3D(color: const ui.Color(0xFFFF0000), roughness: 1));
      return (await draw(scene, camera())).atFraction(0.5, 0.5)[0];
    }

    // The camera looks along +Z at the cube's −Z face.
    final front = await red(Vector3(0, 0, 1));
    final behind = await red(Vector3(0, 0, -1));
    // ignore: avoid_print
    print('SHAPES lit from in front $front, from behind $behind');
    expect(front, greaterThan(behind + 60), reason: 'a cube drawn inside out shows its far face');
  }, skip: skip);

  test('a texture is drawn, tiled', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = const ui.Color(0xFF00C800));
    final image = await recorder.endRecording().toImage(4, 4);
    files['green.png'] = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final cube = Cube3D(color: const ui.Color(0xFFFFFFFF), unlit: true, texture: 'green.png', tiling: Vector2(3, 3));
    shapes.materialFor(cube); // starts the load
    for (var i = 0; i < 100 && shapes.counts.$3 == 1 && shapes.revision == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final scene = dark();
    place(scene, cube);
    final c = (await draw(scene, camera())).atFraction(0.5, 0.5);
    expect(c[1], greaterThan(150), reason: 'green texture: $c');
    expect(c[0], lessThan(40), reason: '$c');
  }, skip: skip);

  test('every shape draws, and fifty equal cubes are one draw', () async {
    for (final shape in <Primitive3D>[
      Cube3D(),
      Sphere3D(),
      Plane3D(width: 1, depth: 1),
      Cylinder3D(),
      Capsule3D(height: 1.5),
      Cone3D(),
      Torus3D(),
      Ramp3D(depth: 1),
      Stairs3D(depth: 1),
      Arch3D(radius: 1),
      Polygon3D(),
    ]) {
      shape
        ..color = const ui.Color(0xFFFFFFFF)
        ..unlit = true;
      final scene = dark();
      place(scene, shape);
      // Seen from above and in front, so even a plane shows.
      final px = await draw(scene, camera(eye: Vector3(0, -2.5, -2.5)));
      var lit = 0;
      for (var y = 0; y < _size; y++) {
        for (var x = 0; x < _size; x++) {
          if (px.at(x, y)[0] > 200) lit++;
        }
      }
      expect(lit, greaterThan(_size * _size ~/ 40), reason: '${shape.shapeName} drew $lit pixels');
    }

    renderer.shadows.cascades = 1;
    final scene = dark(sun: Vector3(0.3, 1, 0.5));
    for (var i = 0; i < 50; i++) {
      place(scene, Cube3D(width: 0.2, height: 0.2, depth: 0.2), at: Vector3((i % 10 - 4.5) * 0.3, 0, (i ~/ 10) * 0.3));
    }
    await draw(scene, camera(eye: Vector3(0, -2, -3)));
    expect(renderer.stats.instances, 50);
    // One lit draw and the tonemap (no sky), and one into the shadow map.
    expect(renderer.stats.drawCalls, 3, reason: '${renderer.stats}');
    expect(renderer.stats.shadowDrawCalls, 1);
  }, skip: skip);
}
