// What a 3-D renderer reads from the engine: the frame's frustum, camera
// pose and interpolation; culling by frustum for a camera in space; a cursor
// the game can hide; and a model asset type a renderer fills in.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A camera 10 units back from the world plane, looking along +Z.
Camera _camera({double pitch = 0}) => Camera(
  viewportSize: const Size(400, 400),
  z: -10,
  pitch: pitch,
  lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
);

class _Model extends ModelAsset {
  _Model(super.path);

  final Aabb3 _bounds = Aabb3();

  @override
  Aabb3 get bounds => _bounds;

  @override
  List<String> get meshNames => const ['body'];

  @override
  ModelGeometry? geometryOf(String meshName) => meshName == 'body'
      ? ModelGeometry(
          Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Uint32List.fromList([0, 1, 2]),
        )
      : null;

  @override
  Future<void> load() async {
    _bounds.setValues(-1, -2, -3, 1, 2, 3);
    markAsLoaded();
  }

  @override
  void unload() => markAsUnloaded();

  @override
  int getMemoryUsage() => 36;
}

class _ModelLoader extends AssetLoader {
  @override
  Asset createAsset(String path) => _Model(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the frame view', () {
    test('holds the frustum, the camera pose and the interpolation', () {
      final view = FrameView()
        ..update(_camera(), const Size(400, 400), interpolation: 0.25);
      expect(view.interpolation, 0.25);
      expect(view.cameraPosition.z, closeTo(-10, 1e-9));
      expect(view.cameraPosition.x, closeTo(0, 1e-9));
      expect(view.cameraForward.z, closeTo(1, 1e-9));
      expect(view.frustum.containsPoint(Vector3(0, 0, 10)), isTrue);
      expect(view.frustum.containsPoint(Vector3(0, 0, -20)), isFalse);
    });

    test('a camera pitched down (+Y is down) looks down', () {
      final view = FrameView()..update(_camera(pitch: -0.5), const Size(400, 400));
      expect(view.cameraForward.y, greaterThan(0.4));
      expect(view.cameraForward.length, closeTo(1, 1e-9));
    });

    test('the rendering engine hands the loop\'s interpolation to the view', () {
      final rendering = RenderingEngine()..camera = _camera();
      rendering.interpolation = 0.5;
      expect(rendering.view.interpolation, 0.5);
    });
  });

  group('culling for a camera in space', () {
    late World world;

    setUp(() {
      world = World();
      addTearDown(world.dispose);
      world.addSystem(ViewCullingSystem(camera: _camera())..activeDistance = 50);
    });

    CullStateComponent at(double x, double y, double z) => world
        .createEntityWithComponents([
          TransformComponent(position: Vector3(x, y, z)),
          CullStateComponent(),
        ])
        .getComponent<CullStateComponent>()!;

    test('uses the frustum, and distance for what is out of it', () {
      final ahead = at(0, 0, 0);
      final behindNear = at(0, 0, -20);
      final behindFar = at(0, 0, -200);
      final aside = at(1000, 0, 0);
      world.update(1 / 60);

      expect((ahead.isVisible, ahead.isActive), (true, true));
      expect((behindNear.isVisible, behindNear.isActive), (false, true));
      expect((behindFar.isVisible, behindFar.isActive), (false, false));
      expect((aside.isVisible, aside.isActive), (false, false));
    });

    test('a 2-D camera still culls by its rectangle', () {
      final flat = World();
      addTearDown(flat.dispose);
      flat.addSystem(
        ViewCullingSystem(
          camera: Camera(viewportSize: const Size(800, 600)),
        ),
      );
      final near = flat
          .createEntityWithComponents([
            TransformComponent(position: Vector3.fromXY(10, 10)),
            CullStateComponent(),
          ])
          .getComponent<CullStateComponent>()!;
      final far = flat
          .createEntityWithComponents([
            TransformComponent(position: Vector3.fromXY(5000, 0)),
            CullStateComponent(),
          ])
          .getComponent<CullStateComponent>()!;
      flat.update(1 / 60);
      expect(near.isVisible, isTrue);
      expect(far.isVisible, isFalse);
    });
  });

  testWidgets('the game widget shows the engine\'s cursor, and follows it', (
    tester,
  ) async {
    final engine = (await tester.runAsync(() async {
      final e = Engine();
      await e.initialize();
      return e;
    }))!;
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
    );

    bool hidden() => tester
        .widgetList<MouseRegion>(find.byType(MouseRegion))
        .any((r) => r.cursor == SystemMouseCursors.none);

    expect(hidden(), isFalse);
    engine.cursor.value = SystemMouseCursors.none;
    await tester.pump();
    expect(hidden(), isTrue);
    engine.cursor.value = SystemMouseCursors.basic;
    await tester.pump();
    expect(hidden(), isFalse);
  });

  test('a renderer\'s model loader fills in a ModelAsset', () async {
    final assets = AssetManager()..initialize();
    assets.registerLoader(AssetType.model, _ModelLoader());
    final model = await assets.load<ModelAsset>('hero.glb', AssetType.model);
    expect(model, isA<ModelAsset>());
    model as ModelAsset;
    expect(model.isLoaded, isTrue);
    expect(model.bounds.max.z, 3);
    expect(model.meshNames, ['body']);
    expect(model.geometryOf('body')!.triangleCount, 1);
    expect(model.geometryOf('nothing'), isNull);
  });
}
