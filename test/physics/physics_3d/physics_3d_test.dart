// Physics3D in a real engine, on the fake physics engine: installed as the
// engine is made, started as it initializes, its world made only with the
// first 3-D body (with the project's layers), queries answered, everything
// taken down again — and where 3-D cannot run, initializing fails saying why.

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_physics_engine/testing.dart';

Future<Engine> _engine(Physics3D physics3D) async {
  final engine = Engine(config: EngineConfig(services: [physics3D]));
  addTearDown(engine.dispose);
  await engine.initialize();
  return engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 2-D engine knows no 3-D components', () {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.physics3D, isNull);
    expect(engine.context.definitions.definitionByType('RigidBody3DComponent'), isNull);
  });

  test('the components are known as soon as the engine is made', () {
    final engine = Engine(config: EngineConfig(services: [Physics3D(engine: FakePhysics3DEngine())]));
    addTearDown(engine.dispose);
    expect(engine.context.definitions.definitionByType('RigidBody3DComponent'), isNotNull);
    expect(engine.context.definitions.definitionByType('Collider3DComponent'), isNotNull);
    expect(engine.physics3D!.isStarted, isFalse);
  });

  test('starts with the engine, and makes no world until the first 3-D body', () async {
    final fake = FakePhysics3DEngine();
    final engine = await _engine(Physics3D(engine: fake));
    final physics3D = engine.physics3D!;
    expect(physics3D.isStarted, isTrue);
    expect(physics3D.engine, same(fake));
    expect(engine.service<Physics3D>(), same(physics3D));
    expect(engine.world.systems.contains(physics3D.system), isTrue);

    engine.world.update(1 / 60);
    expect(fake.worlds, isEmpty, reason: 'nothing 3-D yet');
    expect(physics3D.hasWorld, isFalse);
    expect(physics3D.queries.raycast(Vector3(0, -10, 0), Vector3(0, 1, 0)), isNull);

    final box = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -2, 0)),
      Collider3DComponent(),
      RigidBody3DComponent(),
    ]);
    engine.world.update(1 / 60);
    final world = fake.worlds.single;
    expect(physics3D.hasWorld, isTrue);
    expect(physics3D.world, same(world));
    expect(world.gravity, Vector3(0, 9.81, 0));
    expect(world.settings.layerMasks, [
      for (var i = 0; i < 16; i++) engine.context.physicsLayers.maskOf(i),
    ]);
    expect(world.bodies, hasLength(1));
    expect(world.steps, 1);
    expect(physics3D.queries.raycast(Vector3(0, -10, 0), Vector3(0, 1, 0))?.entity, box);
  });

  test('a collision grid edited while a 3-D scene plays reaches its world', () async {
    final fake = FakePhysics3DEngine();
    final engine = await _engine(Physics3D(engine: fake));
    List<int> grid() => [for (var i = 0; i < 16; i++) engine.context.physicsLayers.maskOf(i)];
    engine.world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(size: Vector3(10, 1, 10)),
      RigidBody3DComponent(bodyType: Body3DType.static, layer: 1),
    ], name: 'Floor');
    final crate = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -1.5, 0)),
      Collider3DComponent(),
      RigidBody3DComponent(layer: 2),
    ], name: 'Crate');
    double crateY() => crate.getComponent<TransformComponent>()!.position.y;
    for (var i = 0; i < 60; i++) {
      engine.world.update(1 / 60);
    }
    final world = fake.worlds.single;
    expect(world.layerMasks, grid());
    expect(crateY(), closeTo(-1, 0.1), reason: 'resting on the floor');

    engine.context.physicsLayers = engine.context.physicsLayers.withCollision(1, 2, false);
    engine.world.update(1 / 60);
    expect(world.layerMasks, grid());
    expect((world.layerMasks[1] >> 2) & 1, 0, reason: 'layers 1 and 2 no longer collide');
    for (var i = 0; i < 60; i++) {
      engine.world.update(1 / 60);
    }
    expect(crateY(), greaterThan(0), reason: 'fallen through the floor');
  });

  test('stopping takes the system out and disposes the world', () async {
    final fake = FakePhysics3DEngine();
    final engine = await _engine(Physics3D(engine: fake));
    final physics3D = engine.physics3D!;
    final system = physics3D.system;
    engine.world.createEntityWithComponents([TransformComponent(), Collider3DComponent()]);
    engine.world.update(1 / 60);
    final world = fake.worlds.single;
    expect(world.bodies, hasLength(1));
    await engine.services.remove(physics3D);
    expect(world.bodies, isEmpty, reason: 'the system took out what it made');
    expect(world.isDisposed, isTrue);
    expect(engine.world.systems.contains(system), isFalse);
    expect(physics3D.isStarted, isFalse);
    expect(() => physics3D.world, throwsStateError);
  });

  test('stopping before any 3-D body makes no world on the way out', () async {
    final fake = FakePhysics3DEngine();
    final engine = await _engine(Physics3D(engine: fake));
    await engine.services.remove(engine.physics3D!);
    expect(fake.worlds, isEmpty);
  });

  test('where 3-D physics cannot run, initializing fails saying why', () async {
    final engine = Engine(
      config: EngineConfig(services: [Physics3D(engine: FakePhysics3DEngine(unavailableReason: 'not here'))]),
    );
    addTearDown(engine.dispose);
    await expectLater(
      engine.initialize(),
      throwsA(
        isA<EngineInitException>()
            .having((e) => e.stage, 'stage', 'service:Physics3D')
            .having(
          (e) => e.cause,
          'cause',
          isA<Physics3DUnsupportedError>().having((e) => e.message, 'message', contains('not here')),
        ),
      ),
    );
  });

  test('a scene with 3-D physics components loads through the definitions', () async {
    final engine = await _engine(Physics3D(engine: FakePhysics3DEngine()));
    final loaded =
        engine.context.definitions.definitionByType('RigidBody3DComponent')!.decode({
              'type': 'RigidBody3DComponent',
              'fields': {'bodyType': 'kinematic', 'layer': 2, 'mass': 4},
            })
            as RigidBody3DComponent;
    expect(loaded.bodyType, Body3DType.kinematic);
    expect(loaded.layer, 2);
    expect(loaded.mass, 4);
  });

  test('registerDefinitions teaches a bare context the components, for tools', () {
    final context = EngineContext();
    addTearDown(context.dispose);
    Physics3D.registerDefinitions(context);
    expect(context.definitions.definitionByType('CharacterBody3DComponent'), isNotNull);
  });
}
