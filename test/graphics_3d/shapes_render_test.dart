// The shapes on the null device: extracted into the renderer's scene,
// equal shapes sharing one mesh and one material, a change of size or look
// swapping them, a texture arriving after the shape, and a shape with no
// triangles drawn as nothing.
@Tags(['graphics3d'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'fixtures.dart';

Future<Uint8List> _png(ui.Color colour) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = colour);
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  const gridPath = 'assets/textures/grid.png';

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(
      config: EngineConfig(graphics3D: service),
      context: EngineContext(bundle: TestBundle({gridPath: await _png(const ui.Color(0xFF00FF00))})),
    );
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  final view = frameView(eye: Vector3(0, -3, -8));

  Entity add(String name, Primitive3D shape, {Vector3? at, Vector3? scale}) => engine.world.createEntity(name: name)
    ..addComponent(TransformComponent(position: at ?? Vector3.zero(), scale: scale))
    ..addComponent(shape);

  test('a shape becomes an instance where its entity is', () {
    add('box', Cube3D(width: 2, height: 1, depth: 1), at: Vector3(3, -0.5, 1));
    final renderer = service.sceneRenderer..update(view);
    final instance = renderer.debugShapeInstances.single!;
    expect(renderer.scene.instances, contains(instance));
    final b = instance.bounds;
    expect((b.min.x, b.max.x), (2.0, 4.0));
    expect((b.min.y, b.max.y), (-1.0, 0.0));
    expect(instance.visible, isTrue);
    expect(instance.material.data.baseColor.$4, 1);
  });

  test('equal shapes share one mesh and one material, so they draw as one', () {
    for (var i = 0; i < 5; i++) {
      add('crate $i', Cube3D(), at: Vector3(i * 2.0, 0, 0));
    }
    add('other', Cube3D(width: 3));
    final renderer = service.sceneRenderer..update(view);
    final instances = renderer.debugShapeInstances.cast<MeshInstance>();
    expect(instances.take(5).map((i) => i.primitive).toSet(), hasLength(1));
    expect(instances.take(5).map((i) => i.material).toSet(), hasLength(1));
    expect(instances.last.primitive, isNot(same(instances.first.primitive)));
    expect(instances.last.material, same(instances.first.material), reason: 'the same look');
    expect(renderer.shapes.counts.$1, 2);
  });

  test('a change of size swaps the mesh, a change of look the material', () {
    final cube = Cube3D();
    add('box', cube);
    final renderer = service.sceneRenderer..update(view);
    final instance = renderer.debugShapeInstances.single!;
    final mesh = instance.primitive, look = instance.material;

    cube.height = 4;
    renderer.update(view);
    expect(instance.primitive, isNot(same(mesh)));
    expect(instance.bounds.max.y, 2, reason: 'bounds follow the new mesh');
    expect(instance.material, same(look));

    cube
      ..color = const ui.Color(0xFFFF0000)
      ..opacity = 0.5;
    renderer.update(view);
    expect(instance.material, isNot(same(look)));
    expect(instance.material.data.baseColor, (1.0, 0.0, 0.0, 0.5));
    expect(instance.material.data.alphaMode, AlphaMode.blend);

    cube
      ..visible = false
      ..castShadows = false;
    renderer.update(view);
    expect((instance.visible, instance.castShadows), (false, false));
  });

  test('a plane is drawn from both sides; glow and unlit carry over', () {
    add('floor', Plane3D(emission: const ui.Color(0xFFFFFFFF), emissionStrength: 2, unlit: true));
    final data = (service.sceneRenderer..update(view)).debugShapeInstances.single!.material.data;
    expect(data.doubleSided, isTrue);
    expect(data.unlit, isTrue);
    expect(data.emissive, (1.0, 1.0, 1.0));
    expect(data.emissiveStrength, 2);
  });

  test('a texture arrives after its shape and is tiled', () async {
    final cube = Cube3D(texture: gridPath, tiling: Vector2(4, 2));
    add('box', cube);
    final renderer = service.sceneRenderer..update(view);
    final instance = renderer.debugShapeInstances.single!;
    final before = instance.material;
    expect(before.data.baseColorTexture?.scale, (4.0, 2.0));
    await pumpEventQueue();
    await engine.context.bundle.load(gridPath);
    for (var i = 0; i < 20 && identical(instance.material, before); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      renderer.update(view);
    }
    expect(instance.material, isNot(same(before)), reason: 'made again with its texture');
    expect(renderer.shapes.counts.$3, 1);
  });

  test('a texture tiled per metre follows the entity\'s scale; otherwise scale needs no new mesh', () {
    final plain = Cube3D();
    final tiled = Cube3D(texture: gridPath, tileInMetres: true);
    final a = add('plain', plain);
    final b = add('tiled', tiled);
    final renderer = service.sceneRenderer..update(view);
    final [first!, second!] = renderer.debugShapeInstances;
    final plainMesh = first.primitive, tiledMesh = second.primitive;
    a.getComponent<TransformComponent>()!.scale = Vector3(3, 1, 1);
    b.getComponent<TransformComponent>()!.scale = Vector3(3, 1, 1);
    renderer.update(view);
    expect(first.primitive, same(plainMesh));
    expect(second.primitive, isNot(same(tiledMesh)));
  });

  test('an outline of fewer than three points draws nothing, until it has three', () {
    final polygon = Polygon3D(points: const [ui.Offset(0, 0), ui.Offset(1, 0)]);
    add('line', polygon);
    final renderer = service.sceneRenderer..update(view);
    expect(renderer.debugShapeInstances.single, isNull);
    polygon.points = [...polygon.points, const ui.Offset(0, 1)];
    renderer.update(view);
    final instance = renderer.debugShapeInstances.single!;
    expect(instance.visible, isTrue);
    polygon.points = const [ui.Offset(0, 0)];
    renderer.update(view);
    expect(instance.visible, isFalse);
  });

  test('disabled entities and removed shapes leave the scene', () {
    final e = add('box', Sphere3D());
    final renderer = service.sceneRenderer..update(view);
    expect(renderer.debugShapeInstances, hasLength(1));
    e.removeComponent<Primitive3D>();
    renderer.update(view);
    expect(renderer.debugShapeInstances, isEmpty);
    expect(renderer.scene.instances, isEmpty);
  });

  test('a scene saved with shapes loads and draws them', () {
    final json = sceneJson(engine.context, {
      'Floor': [TransformComponent(), Plane3D(width: 20, depth: 20)],
      'Steps': [TransformComponent(position: Vector3(0, -0.5, 4)), Stairs3D(steps: 3)],
      'Pillar': [TransformComponent(position: Vector3(3, -1, 0)), Cylinder3D(height: 2)],
    });
    SceneLoader.load(engine.world, json);
    final renderer = service.sceneRenderer..update(view);
    expect(renderer.debugShapeInstances.whereType<MeshInstance>(), hasLength(3));
  });
}
