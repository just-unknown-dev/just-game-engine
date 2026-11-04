// Physics3D as an engine service, with a model loader: a mesh collider
// takes its triangles from the engine's loaded model, and when the asset
// manager says the model was loaded again (its reload listeners), the body
// is made again from the new triangles.

@Tags(['physics3d'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_physics_engine/testing.dart';

/// A model of one mesh whose triangles a test can swap.
final class _Model extends ModelAsset {
  _Model(super.path, this.geometry);

  ModelGeometry geometry;

  @override
  Aabb3 get bounds => Aabb3();

  @override
  List<String> get meshNames => const ['mesh'];

  @override
  ModelGeometry? geometryOf(String meshName) => geometry;

  @override
  Future<void> load() async => markAsLoaded();

  @override
  void unload() => markAsUnloaded();

  @override
  int get memoryUsage => 0;
}

final class _Loader implements AssetLoader {
  _Loader(this.model);

  final _Model model;

  @override
  Asset createAsset(String path) => model;
}

ModelGeometry _triangles(int count) => ModelGeometry(
  Float32List.fromList([
    for (var i = 0; i < count; i++) ...[
      i * 2.0,
      0,
      0,
      i * 2.0 + 1,
      0,
      0,
      0,
      0,
      1,
    ],
  ]),
  Uint32List.fromList([for (var i = 0; i < count * 3; i++) i]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a reloaded model gives its mesh collider the new triangles', () async {
    final engine = Engine(
      config: EngineConfig(
        services: [Physics3D(engine: FakePhysicsEngine3D())],
      ),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    final model = _Model('ground.glb', _triangles(1));
    engine.assets.registerLoader(AssetType.model, _Loader(model));

    final ground = engine.world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(shape: Collider3DShape.mesh, model: 'ground.glb'),
    ]);
    final physics3D = engine.physics3D!;
    engine.world.update(1 / 60); // Asks for the model.
    await pumpEventQueue();
    engine.world.update(1 / 60);
    final world = physics3D.world as FakePhysicsWorld3D;
    MeshShape3D shape() =>
        world.bodies[physics3D.system.bodyOf(ground)]!.shape as MeshShape3D;
    expect(shape().indices, hasLength(3));

    model.geometry = _triangles(2);
    engine.world.update(1 / 60);
    expect(shape().indices, hasLength(3), reason: 'not told yet');

    engine.assets.notifyReloaded('ground.glb');
    engine.world.update(1 / 60);
    expect(shape().indices, hasLength(6));
  });
}
