// The scene renderer over many frames: what stays on screen keeps its mesh,
// material and texture however long it stands unchanged; a change of the
// world's structure keeps what still stands; a shape changed in place is
// seen; colours made linear follow their components; and Graphics3D takes
// everything back out when it stops. A shape whose size or look animates
// keeps one mesh and one material, a view that stops drawing lets go of
// its surface, and releaseUnused lets go of what the world no longer draws
// — asked by the engine after a level change too.
@Tags(['graphics3d'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart' show NullGpuDevice, rendererNullShaders;

import 'fixtures.dart';

Future<Uint8List> _png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = color);
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
      config: EngineConfig(services: [service]),
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

  Future<MeshInstance> texturedCube(Graphics3DSceneRenderer renderer) async {
    add('crate', Cube3DComponent(texture: _gridPath));
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
      add('another', Cube3DComponent(texture: _gridPath), at: Vector3(2, 0, 0));
      renderer.update(view);
      final second = renderer.debugShapeInstances.last!;
      expect(second.primitive, same(mesh));
      expect(second.material, same(material));
      expect(renderer.shapes.counts, (1, 1, 1));

      // And its texture can still be read again: what it was is drawn until
      // the new one arrives.
      final revision = renderer.shapes.revision;
      renderer.shapes.reloadTexture(_gridPath);
      renderer.update(view);
      expect(second.material, same(material), reason: 'no flicker while it is read');
      for (var i = 0; i < 50 && renderer.shapes.revision == revision; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        renderer.update(view);
      }
      expect(renderer.shapes.revision, revision + 1);
      expect(second.material, isNot(same(material)), reason: 'made again with the new texture');
      expect(second.material.textures.first.$1, isNot(same(material.textures.first.$1)));
    });

    test('what is no longer drawn is still let go', () {
      final renderer = service.sceneRenderer;
      add('stays', Cube3DComponent());
      final gone = add('goes', Sphere3DComponent());
      renderer.update(view);
      expect(renderer.shapes.counts.$1, 2);
      gone.removeComponent<Primitive3DComponent>();
      for (var i = 0; i < 480; i++) {
        renderer.update(view);
      }
      expect(renderer.shapes.counts.$1, 1);
    });

    test('one whose size or colour animates keeps one mesh and one material', () {
      final renderer = service.sceneRenderer;
      add('stays', Cube3DComponent());
      final ball = Sphere3DComponent();
      add('pulse', ball, at: Vector3(3, 0, 0));
      renderer.update(view);
      for (var i = 0; i < 400; i++) {
        ball
          ..radius = 0.5 + i / 1000
          ..color = ui.Color(0xFF000000 + i);
        renderer.update(view);
      }
      expect(renderer.shapes.counts.$1, 2, reason: "the cube's mesh and the ball's now");
      expect(renderer.shapes.counts.$2, 2);
    });

    test('two alike share a mesh, kept while either draws it', () {
      final renderer = service.sceneRenderer;
      final a = Cube3DComponent(), b = Cube3DComponent();
      add('a', a);
      add('b', b, at: Vector3(2, 0, 0));
      renderer.update(view);
      final shared = renderer.debugShapeInstances.first!.primitive;
      a.width = 2;
      renderer.update(view);
      renderer.update(view);
      expect(renderer.debugShapeInstances.last!.primitive, same(shared));
      expect(renderer.shapes.counts.$1, 2);
      a.width = 1;
      renderer.update(view);
      expect(renderer.debugShapeInstances.first!.primitive, same(shared), reason: 'held by the other');
    });

    test('a look or an outline changed in place is seen', () {
      final renderer = service.sceneRenderer;
      final cube = Cube3DComponent(texture: _gridPath);
      final polygon = Polygon3DComponent(points: [const ui.Offset(0, 0), const ui.Offset(1, 0), const ui.Offset(0, 1)]);
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
      add('box', Cube3DComponent(), at: Vector3(-2, 0, 0));
      renderer.update(view);
      final before = List.of(renderer.scene.instances);
      expect(before, hasLength(3));
      final palette = before.firstWhere((i) => i.skin != null).skin;

      add('newcomer', Sphere3DComponent(), at: Vector3(0, 0, 3));
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
    final light = Light3DComponent(kind: Light3DKind.point, color: const ui.Color(0xFFFFFFFF));
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
  group('letting go', () {
    test('a view that stops drawing lets go of its surface', () {
      final renderer = service.sceneRenderer..renderWithoutGpu = true;
      final game = frameView(eye: Vector3(0, -3, -8)), pane = frameView(eye: Vector3(0, -3, -8));
      final canvas = ui.Canvas(ui.PictureRecorder());
      renderer
        ..render(canvas, game)
        ..render(canvas, pane);
      expect(renderer.debugSurfaces, 2);
      for (var i = 0; i < Graphics3DSceneRenderer.keepSurfaceRenders + 60; i++) {
        renderer.render(canvas, game);
      }
      expect(renderer.debugSurfaces, 1, reason: "the pane's surface let go");
      renderer.dispose();
      expect(renderer.debugSurfaces, 0);
    });

    test('releaseUnused lets go of the models and materials no longer drawn', () async {
      const red = 'assets/materials/red.material.json';
      const blue = 'assets/materials/blue.material.json';
      final bundle = engine.context.bundle as TestBundle;
      bundle.files[red] = Uint8List.fromList('{"color": 4294901760}'.codeUnits);
      bundle.files[blue] = Uint8List.fromList('{"color": 4278190335}'.codeUnits);
      final renderer = service.sceneRenderer;
      await service.models.load(cubePath);
      await service.models.load(_barPath);
      final crate = add('crate', ModelComponent(model: cubePath, materials: {'*': red}));
      add('bar', ModelComponent(model: _barPath));
      final hidden = add('hidden', Cube3DComponent(material: blue))..isActive = false;
      add('ball', Sphere3DComponent(material: red), at: Vector3(3, 0, 0));
      renderer.update(view);
      for (var i = 0; i < 50 && (renderer.materials.fileOf(red) == null || renderer.materials.fileOf(blue) == null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        renderer.update(view);
      }

      engine.world.destroyEntity(crate);
      expect(renderer.releaseUnused(), (1, 0), reason: "the crate's model went; red is still the ball's");
      expect(service.models.paths, [_barPath]);
      expect(renderer.materials.fileOf(blue), isNotNull, reason: "a switched-off entity's is kept");

      engine.world.destroyEntity(hidden);
      expect(renderer.releaseUnused().$2, 1);
      expect(renderer.debugShapeInstances.single, isNotNull, reason: 'what stays is still drawn');
    });

    test('after a level change, the engine lets go of what only the old level drew', () async {
      const red = 'assets/materials/red.material.json';
      const blue = 'assets/materials/blue.material.json';
      final bundle = engine.context.bundle as TestBundle;
      bundle.files[red] = Uint8List.fromList('{"color": 4294901760}'.codeUnits);
      bundle.files[blue] = Uint8List.fromList('{"color": 4278190335}'.codeUnits);
      final renderer = service.sceneRenderer;
      await service.models.load(cubePath);
      await service.models.load(_barPath);
      void both() {
        add('bar', ModelComponent(model: _barPath));
        add('ball', Sphere3DComponent(material: red));
      }

      // The old level: a crate and a blue box, besides what both levels have.
      add('crate', ModelComponent(model: cubePath));
      add('box', Cube3DComponent(material: blue), at: Vector3(3, 0, 0));
      both();
      renderer.update(view);
      for (var i = 0; i < 50 && (renderer.materials.fileOf(red) == null || renderer.materials.fileOf(blue) == null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        renderer.update(view);
      }
      expect(renderer.materials.fileOf(blue), isNotNull);

      engine.world.destroyAllEntities();
      both();
      engine.releaseUnused();
      expect(service.models.paths, [_barPath], reason: "the crate's model went");
      expect(renderer.materials.fileOf(red), isNotNull, reason: 'both levels draw with it');
      expect(renderer.materials.fileOf(blue), isNull, reason: 'gone: asked for again, it is read again');
    });

    test('a renderer draws a bare world, no engine needed', () async {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final renderer3D = await Renderer3D.create(NullGpuDevice(shaders: rendererNullShaders));
      final renderer = Graphics3DSceneRenderer(
        world: () => world,
        renderer: renderer3D,
        models: Graphics3DModels(TestBundle({}), renderer3D.uploader),
      );
      addTearDown(renderer.dispose);
      world.createEntityWithComponents([TransformComponent(position: Vector3(2, 0, 0)), Cube3DComponent()]);
      renderer.update(view);
      expect(renderer.debugShapeInstances.single!.world.storage[12], 2);
    });
  });
}
