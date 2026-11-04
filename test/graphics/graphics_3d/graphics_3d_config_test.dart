// Graphics3D as the engine's opt-in 3-D: a 2-D engine has none of it, a
// scene with 3-D components says how to turn it on, and with no GPU the
// game still starts and is told why nothing 3-D is drawn — keeping only
// the models' bounds up to date, nothing made to draw.
@Tags(['graphics3d'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'fixtures.dart';

/// Records whether Graphics3D had started when the engine started it.
final class _Probe implements EngineService {
  bool? graphicsStarted;

  @override
  Future<void> start(ServiceContext context) async {
    graphicsStarted = context.engine.graphics3D?.isStarted;
  }

  @override
  Future<void> stop() async {}
}

Map<String, dynamic> _sceneWith(Map<String, dynamic> component) => {
  'version': 9,
  'entities': [
    {
      'name': 'Thing',
      'components': [component],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 2-D engine has no 3-D graphics, and reads no 3-D components', () {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.graphics3D, isNull);
    expect(
      engine.context.definitions.definitionByType('ModelComponent'),
      isNull,
    );
    expect(
      engine.context.definitions.definitionByType('Cube3DComponent'),
      isNull,
    );
  });

  test('a 3-D component without Graphics3D says how to turn it on', () {
    final world = World(extensions: [BuiltInComponents.extension]);
    addTearDown(world.dispose);
    final error = _loadError(world, {'type': 'ModelComponent'});
    expect(error, isA<UnknownComponentTypeException>());
    expect('$error', contains('EngineConfig(services: [Graphics3D()])'));
    final overrides = _loadError(world, {
      'type': 'MaterialOverrides3DComponent',
    });
    expect('$overrides', contains('EngineConfig(services: [Graphics3D()])'));
    final physics = _loadError(world, {'type': 'RigidBody3DComponent'});
    expect('$physics', contains('EngineConfig(services: [Physics3D()])'));
    final other = _loadError(world, {'type': 'NoSuchThing'});
    expect('$other', contains("Install the owning package's extension"));
  });

  test('the ECS core alone knows nothing of 3-D, not even its names', () {
    final world = World();
    addTearDown(world.dispose);
    final error = _loadError(world, {'type': 'ModelComponent'});
    expect(error, isA<UnknownComponentTypeException>());
    expect((error! as UnknownComponentTypeException).hint, isNull);
    expect('$error', contains("Install the owning package's extension"));
  });

  test('without a GPU the game starts, and is told why once', () async {
    final reasons = <String>[];
    final probe = _Probe();
    final engine = Engine(
      config: EngineConfig(
        services: [
          Graphics3D(onUnsupported: reasons.add),
          probe,
        ],
      ),
      context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    final graphics = engine.graphics3D!;
    expect(graphics.isStarted, isTrue);
    // Plain `flutter test` has no Flutter GPU.
    expect(graphics.isSupported, isFalse);
    expect(reasons, [graphics.unsupportedReason]);
    // Started before the game's own services, so they can load models.
    expect(probe.graphicsStarted, isTrue);
    expect(engine.service<Graphics3D>(), same(graphics));

    // Scenes and models still load (models for their bounds).
    SceneLoader.load(
      engine.world,
      sceneJson(engine.context, {
        'Crate': [TransformComponent(), ModelComponent(model: cubePath)],
      }),
    );
    final model = await graphics.models.load(cubePath);
    expect(model.data.bounds.max.y, closeTo(1, 1e-6));
  });

  test(
    'without a GPU a frame keeps only the bounds of models up to date',
    () async {
      final engine = Engine(
        config: EngineConfig(services: [Graphics3D()]),
        context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      final graphics = engine.graphics3D!;
      expect(graphics.isSupported, isFalse);
      await graphics.models.load(cubePath);
      final crate = ModelComponent(model: cubePath);
      engine.world.createEntityWithComponents([TransformComponent(), crate]);
      engine.world.createEntityWithComponents([
        TransformComponent(),
        Cube3DComponent(),
      ]);
      final renderer = graphics.sceneRenderer;
      renderer.render(
        ui.Canvas(ui.PictureRecorder()),
        frameView(eye: Vector3(0, -2, -6)),
      );
      expect(crate.bounds.max.y, closeTo(0, 1e-6));
      expect(
        crate.bounds.min.y,
        closeTo(-1, 1e-6),
        reason: '1 m up, in engine axes',
      );
      expect(
        renderer.debugShapeInstances.single,
        isNull,
        reason: 'no mesh made to draw',
      );
    },
  );
}

Object? _loadError(World world, Map<String, dynamic> component) {
  try {
    SceneLoader.load(world, _sceneWith(component));
  } on Object catch (error) {
    return error;
  }
  return null;
}
