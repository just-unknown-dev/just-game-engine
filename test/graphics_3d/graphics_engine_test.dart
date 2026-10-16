// The engine glue on the null device: components saved and loaded through
// their definitions, a scene extracted into the renderer's scene, models
// loaded for the asset manager, and the service starting with no GPU.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('components', () {
    late EngineContext context;
    setUp(() => context = EngineContext(extensions: [Graphics3D()]));
    tearDown(() => context.dispose());

    T roundTrip<T extends Component>(T component) {
      final json = jsonDecode(jsonEncode(context.definitions.encode(component)));
      final back = context.definitions.decode(json as Map<String, dynamic>);
      expect(back, isA<T>());
      return back! as T;
    }

    test('every field of every component survives a save and a load', () {
      final model = roundTrip(
        ModelComponent(model: 'assets/models/a.glb', castShadows: false, visible: false),
      );
      expect(model.model, 'assets/models/a.glb');
      expect(model.castShadows, isFalse);
      expect(model.visible, isFalse);

      final light = roundTrip(
        LightComponent(
          kind: LightKind.spot,
          color: const Color(0xFF336699),
          intensity: 42.5,
          range: 12.25,
          innerConeAngle: 0.25,
          outerConeAngle: 0.5,
        ),
      );
      expect(light.kind, LightKind.spot);
      expect(light.color.toARGB32(), 0xFF336699);
      expect(light.intensity, 42.5);
      expect(light.range, 12.25);
      expect(light.innerConeAngle, closeTo(0.25, 1e-12));
      expect(light.outerConeAngle, closeTo(0.5, 1e-12));

      final env = roundTrip(
        EnvironmentComponent(
          sky: false,
          zenith: const Color(0xFF010203),
          horizon: const Color(0xFF040506),
          ground: const Color(0xFF070809),
          ambientSky: const Color(0xFF0A0B0C),
          ambientGround: const Color(0xFF0D0E0F),
          exposure: 1.75,
          background: const Color(0xFF101112),
          fog: true,
          fogColor: const Color(0xFF131415),
          fogDensity: 0.05,
          fogStart: 3,
        ),
      );
      expect(env.sky, isFalse);
      expect(env.zenith.toARGB32(), 0xFF010203);
      expect(env.horizon.toARGB32(), 0xFF040506);
      expect(env.ground.toARGB32(), 0xFF070809);
      expect(env.ambientSky.toARGB32(), 0xFF0A0B0C);
      expect(env.ambientGround.toARGB32(), 0xFF0D0E0F);
      expect(env.exposure, 1.75);
      expect(env.background.toARGB32(), 0xFF101112);
      expect((env.fog, env.fogColor.toARGB32(), env.fogDensity, env.fogStart), (true, 0xFF131415, 0.05, 3.0));
    });

    test('they are 3-D components with a model-sized extent', () {
      for (final c in [ModelComponent(), LightComponent(), EnvironmentComponent()]) {
        final definition = context.definitions.definitionFor(c)!;
        expect(definition.hints.dimensions, Dimensions.threeD, reason: '${c.runtimeType}');
      }
      final model = ModelComponent();
      final extent = context.definitions.definitionFor(model)!.extent!;
      final box = Aabb3();
      expect(extent.boundsInto(model, box), isTrue);
      expect(box.min.x, -0.5, reason: 'a 1 m cube until loaded');
      model.bounds.setValues(0, -2, 0, 1, 0, 3);
      extent.boundsInto(model, box);
      expect((box.min.y, box.max.z), (-2.0, 3.0));
    });

    test('refreshing after a hot reload is safe to repeat', () {
      final extension = Graphics3D() as RefreshableExtension;
      extension.refresh(context);
      extension.refresh(context);
      expect(context.definitions.decode(context.definitions.encode(ModelComponent())!), isA<ModelComponent>());
    });
  });

  group('on the null device', () {
    late Engine engine;
    late Graphics3D service;
    late NullGpuDevice device;

    setUp(() async {
      device = NullGpuDevice(shaders: rendererNullShaders);
      service = Graphics3D(device: device);
      engine = Engine(
        config: EngineConfig(graphics3D: service),
        context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
      );
      await engine.initialize();
    });
    tearDown(() => engine.dispose());

    Map<String, dynamic> scene(Map<String, List<Component>> entities) =>
        sceneJson(engine.context, entities);

    Future<void> loadModels(FrameView view) async {
      service.sceneRenderer.update(view); // starts the loads
      await service.models.load(cubePath);
      service.sceneRenderer.update(view);
    }

    test('starts with the device given, draws itself into the frame', () {
      expect(service.isSupported, isTrue);
      expect(engine.rendering.sceneRenderers, contains(service.sceneRenderer));
    });

    test('a scene from JSON becomes the renderer\'s scene', () async {
      final entities = SceneLoader.load(
        engine.world,
        scene({
          'Crate': [
            TransformComponent(position: Vector3(2, 0, 3)),
            ModelComponent(model: cubePath),
          ],
          'Lamp': [
            TransformComponent(position: Vector3(0, -2, 0)),
            LightComponent(color: const Color(0xFFFF0000), intensity: 20, range: 5),
          ],
          'Sky': [EnvironmentComponent(exposure: 2)],
        }),
      );
      expect(entities, hasLength(3));
      final view = frameView(eye: Vector3(0, -2, -6));
      await loadModels(view);

      final renderer = service.sceneRenderer;
      expect(renderer.debugInstances, {cubePath: 1});
      final instance = renderer.scene.instances.single;
      // The model's +Y up became the engine's -Y up: it rests on y = 0 and
      // rises towards -Y.
      final bounds = instance.bounds;
      expect(bounds.min.x, closeTo(1.5, 1e-6));
      expect(bounds.max.x, closeTo(2.5, 1e-6));
      expect(bounds.min.y, closeTo(-1, 1e-6));
      expect(bounds.max.y, closeTo(0, 1e-6));
      // The component knows its size, in its own space.
      final component = entities.first.getComponent<ModelComponent>()!;
      expect(component.bounds.min.y, closeTo(-1, 1e-6));
      expect(component.bounds.max.y, closeTo(0, 1e-6));

      final light = renderer.scene.lights.single;
      expect(light.type, LightType.point);
      expect((light.position.x, light.position.y, light.position.z), (0.0, -2.0, 0.0));
      expect(light.color, (1.0, 0.0, 0.0), reason: 'sRGB red is linear red');
      expect(light.range, 5);
      expect(renderer.scene.sun.enabled, isFalse, reason: 'the scene has its own light');
      expect(renderer.scene.environment.exposure, 2);
    });

    test('instances follow their entities; edits and removals rebuild', () async {
      final crate = SceneLoader.load(
        engine.world,
        scene({
          'Crate': [TransformComponent(), ModelComponent(model: cubePath)],
        }),
      ).single;
      final view = frameView(eye: Vector3(0, -2, -6));
      await loadModels(view);
      final renderer = service.sceneRenderer;

      crate.getComponent<TransformComponent>()!.position.setValues(5, 0, 0);
      renderer.update(view);
      expect(renderer.scene.instances.single.bounds.min.x, closeTo(4.5, 1e-6));

      crate.getComponent<ModelComponent>()!.visible = false;
      renderer.update(view);
      expect(renderer.scene.instances.single.visible, isFalse);

      crate.getComponent<ModelComponent>()!.model = '';
      renderer.update(view);
      expect(renderer.scene.instances, isEmpty);

      crate.getComponent<ModelComponent>()!.model = cubePath;
      renderer.update(view);
      expect(renderer.scene.instances, hasLength(1));

      engine.world.destroyEntity(crate);
      renderer.update(view);
      expect(renderer.scene.instances, isEmpty);
    });

    test('a scene without lights gets a default sun; a directional light steers it', () async {
      final renderer = service.sceneRenderer;
      final view = frameView(eye: Vector3(0, -2, -6));
      renderer.update(view);
      expect(renderer.scene.sun.enabled, isTrue);

      // Pitched down 90°: the entity's forward (+Z) turns to +Y, down.
      SceneLoader.load(
        engine.world,
        scene({
          'Sun': [
            TransformComponent(euler: Vector3(-1.5707963267948966, 0, 0)),
            LightComponent(kind: LightKind.directional, intensity: 4),
          ],
        }),
      );
      renderer.update(view);
      final sun = renderer.scene.sun;
      expect(sun.enabled, isTrue);
      expect(sun.intensity, 4);
      expect(sun.direction.y.abs(), closeTo(1, 1e-6));
      expect(renderer.scene.lights, isEmpty);
    });

    test('the asset manager loads models: bounds, meshes and triangles', () async {
      final asset = await engine.assets.load(cubePath, AssetType.model) as ModelAsset;
      expect(asset.isLoaded, isTrue);
      expect(asset.meshNames, ['Cube']);
      expect(asset.bounds.min.y, closeTo(-1, 1e-6));
      expect(asset.bounds.max.y, closeTo(0, 1e-6));
      final geometry = asset.geometryOf('Cube')!;
      expect(geometry.triangleCount, 12);
      // Positions are in engine axes too.
      final ys = [for (var i = 1; i < geometry.positions.length; i += 3) geometry.positions[i]];
      expect(ys.reduce((a, b) => a < b ? a : b), closeTo(-1, 1e-6));
      expect(asset.geometryOf('Nope'), isNull);
    });

    test('a frame records its draws on the device', () async {
      SceneLoader.load(
        engine.world,
        scene({
          'A': [TransformComponent(), ModelComponent(model: cubePath)],
          'B': [TransformComponent(position: Vector3(2, 0, 0)), ModelComponent(model: cubePath)],
        }),
      );
      final view = frameView(eye: Vector3(0, -2, -6));
      await loadModels(view);
      final renderer = service.sceneRenderer
        ..pixelRatio = 2
        ..renderWithoutGpu = true;
      service.renderer.shadows.cascades = 1; // one shadow map: one shadow draw
      device.log.clear();
      renderer.render(ui.Canvas(ui.PictureRecorder()), view);
      // Into the shadow map, then the frame: one instanced draw each.
      expect(device.log.where((l) => l.startsWith('drawIndexed')), ['drawIndexed 36 x2', 'drawIndexed 36 x2']);
      expect(service.renderer.stats.instances, 2);
      expect(renderer.scene.instances, hasLength(2));
    });

    test('stopping takes the renderer out of the frame', () async {
      final renderer = service.sceneRenderer;
      await engine.services.remove(service);
      expect(engine.rendering.sceneRenderers, isNot(contains(renderer)));
    });
  });

  test('with no GPU it starts anyway, says why and draws a note', () async {
    final engine = Engine(
      config: EngineConfig(graphics3D: Graphics3D()),
    );
    await engine.initialize();
    addTearDown(engine.dispose);
    final service = engine.service<Graphics3D>();
    final noGpu = gpuUnavailableReason() != null;
    expect(service.isSupported, !noGpu);
    if (!noGpu) return; // the GPU suite has one
    expect(service.unsupportedReason, isNotEmpty);
    expect(service.renderer.device, isA<NullGpuDevice>());
    final recorder = ui.PictureRecorder();
    service.sceneRenderer.render(ui.Canvas(recorder), frameView(eye: Vector3(0, -2, -6)));
    recorder.endRecording();
  });
}
