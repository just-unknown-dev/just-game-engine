// The scene renderer over many frames: what stays on screen keeps its mesh,
// material and texture however long it stands unchanged; a change of the
// world's structure keeps what still stands; a shape changed in place is
// seen; colours made linear follow their components; and Graphics3D takes
// everything back out when it stops.
@Tags(['graphics3d'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

Future<Uint8List> _png(ui.Color colour) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = colour);
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

const _gridPath = 'assets/textures/grid.png';
const _barPath = 'assets/models/bar.glb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(
      config: EngineConfig(graphics3D: service),
      context: EngineContext(
        bundle: TestBundle({
          _gridPath: await _png(const ui.Color(0xFF00FF00)),
          _barPath: skinnedBarGlb(),
          cubePath: cubeGlb(),
        }),
      ),
    );
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  final view = frameView(eye: Vector3(0, -3, -8));

  Entity add(String name, Component shape, {Vector3? at}) => engine.world.createEntity(name: name)
    ..addComponent(TransformComponent(position: at ?? Vector3.zero()))
    ..addComponent(shape);

  Future<MeshInstance> texturedCube(GraphicsSceneRenderer renderer) async {
    add('crate', Cube3D(texture: _gridPath));
    renderer.update(view);
    final instance = renderer.debugShapeInstances.single!;
    final untextured = instance.material;
    await engine.context.bundle.load(_gridPath);
    for (var i = 0; i < 50 && identical(instance.material, untextured); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      renderer.update(view);
    }
    expect(instance.material, isNot(same(untextured)), reason: 'its texture arrived');
    return instance;
  }

  group('shapes on screen', () {
    test('keep their mesh, material and texture however long they stand', () async {
      final renderer = service.sceneRenderer;
      final instance = await texturedCube(renderer);
      final (mesh, material) = (instance.primitive, instance.material);
      for (var i = 0; i < 480; i++) {
        renderer.update(view);
      }
      expect(renderer.shapes.counts, (1, 1, 1));

      // One more like it shares what is held: textured from its first frame.
      add('another', Cube3D(texture: _gridPath), at: Vector3(2, 0, 0));
      renderer.update(view);
      final second = renderer.debugShapeInstances.last!;
      expect(second.primitive, same(mesh));
      expect(second.material, same(material));
      expect(renderer.shapes.counts, (1, 1, 1));

      // And its texture can still be read again.
      final revision = renderer.shapes.revision;
      renderer.shapes.reloadTexture(_gridPath);
      expect(renderer.shapes.revision, revision + 1);
    });

    test('what is no longer drawn is still let go', () {
      final renderer = service.sceneRenderer;
      add('stays', Cube3D());
      final gone = add('goes', Sphere3D());
      renderer.update(view);
      expect(renderer.shapes.counts.$1, 2);
      gone.removeComponent<Primitive3D>();
      for (var i = 0; i < 480; i++) {
        renderer.update(view);
      }
      expect(renderer.shapes.counts.$1, 1);
    });

    test('a look or an outline changed in place is seen', () {
      final renderer = service.sceneRenderer;
      final cube = Cube3D(texture: _gridPath);
      final polygon = Polygon3D(points: [const ui.Offset(0, 0), const ui.Offset(1, 0), const ui.Offset(0, 1)]);
      add('crate', cube);
      add('floor', polygon, at: Vector3(3, 0, 0));
      renderer.update(view);
      final [crate!, floor!] = renderer.debugShapeInstances;
      final (look, outline) = (crate.material, floor.primitive);

      cube.tiling.x = 3;
      polygon.points[2] = const ui.Offset(0, 2);
      renderer.update(view);
      expect(crate.material, isNot(same(look)));
      expect(crate.material.data.baseColorTexture?.scale, (3.0, 1.0));
      expect(floor.primitive, isNot(same(outline)));
      expect(floor.bounds.max.z, closeTo(2, 1e-9));
    });
  });

  group('a change of structure', () {
    test('keeps the instances of what still stands', () async {
      await service.models.load(cubePath);
      await service.models.load(_barPath);
      final renderer = service.sceneRenderer;
      add('crate', ModelComponent(model: cubePath));
      engine.world.createEntityWithComponents([
        TransformComponent(position: Vector3(2, 0, 0)),
        ModelComponent(model: _barPath),
        AnimationPlayerComponent(clip: 'bend'),
      ], name: 'Bar');
      add('box', Cube3D(), at: Vector3(-2, 0, 0));
      renderer.update(view);
      final before = List.of(renderer.scene.instances);
      expect(before, hasLength(3));
      final palette = before.firstWhere((i) => i.skin != null).skin;

      add('newcomer', Sphere3D(), at: Vector3(0, 0, 3));
      renderer.update(view);
      final after = renderer.scene.instances;
      expect(after, hasLength(4));
      for (final instance in before) {
        expect(after, contains(same(instance)));
      }
      expect(after.firstWhere((i) => i.skin != null).skin, same(palette), reason: 'the same pose');
    });

    test('remakes a model whose path changed, and drops a removed one', () async {
      await service.models.load(cubePath);
      await service.models.load(_barPath);
      final renderer = service.sceneRenderer;
      final component = ModelComponent(model: cubePath);
      final crate = add('crate', component);
      renderer.update(view);
      final cube = renderer.scene.instances.single;

      component.model = _barPath;
      renderer.update(view);
      expect(renderer.scene.instances.single, isNot(same(cube)));
      expect(renderer.debugInstances, {_barPath: 1});

      crate.removeComponent<ModelComponent>();
      renderer.update(view);
      expect(renderer.scene.instances, isEmpty);
    });
  });

  test('lights and the environment follow their colours', () {
    final renderer = service.sceneRenderer;
    final light = LightComponent(kind: LightKind.point, color: const ui.Color(0xFFFFFFFF));
    final sky = EnvironmentComponent(zenith: const ui.Color(0xFFFFFFFF));
    add('lamp', light);
    add('sky', sky);
    renderer.update(view);
    expect(renderer.scene.lights.single.color, (1.0, 1.0, 1.0));
    expect(renderer.scene.environment.zenith, (1.0, 1.0, 1.0));

    light.color = const ui.Color(0xFF000000);
    sky.zenith = const ui.Color(0xFF000000);
    renderer.update(view);
    expect(renderer.scene.lights.single.color, (0.0, 0.0, 0.0));
    expect(renderer.scene.environment.zenith, (0.0, 0.0, 0.0));
  });

  test('stopping takes out the renderer, the models and the model loader', () async {
    expect(engine.assets.hasLoader(AssetType.model), isTrue);
    await service.stop();
    expect(service.isStarted, isFalse);
    expect(() => service.renderer, throwsStateError);
    expect(() => service.models, throwsStateError);
    expect(engine.assets.hasLoader(AssetType.model), isFalse);
  });
}
