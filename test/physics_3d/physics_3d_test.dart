// Physics3D in a real engine, on the fake physics engine: installed as the
// engine is made, started as it initializes, its world made only with the
// first 3-D body (with the project's layers), queries answered, everything
// taken down again — and where 3-D cannot run, initializing fails saying why.

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

Future<Engine> _engine(Physics3D physics3D) async {
  final engine = Engine(config: EngineConfig(physics3D: physics3D));
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
    expect(engine.context.definitions.definitionByType('RigidBody3D'), isNull);
  });

  test('the components are known as soon as the engine is made', () {
    final engine = Engine(config: EngineConfig(physics3D: Physics3D(engine: FakePhysicsEngine3D())));
    addTearDown(engine.dispose);
    expect(engine.context.definitions.definitionByType('RigidBody3D'), isNotNull);
    expect(engine.context.definitions.definitionByType('Collider3D'), isNotNull);
    expect(engine.physics3D!.isStarted, isFalse);
  });

  test('starts with the engine, and makes no world until the first 3-D body', () async {
    final fake = FakePhysicsEngine3D();
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
      Collider3D(),
      RigidBody3D(),
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

  test('stopping takes the system out and disposes the world', () async {
    final fake = FakePhysicsEngine3D();
    final engine = await _engine(Physics3D(engine: fake));
    final physics3D = engine.physics3D!;
    final system = physics3D.system;
    engine.world.createEntityWithComponents([TransformComponent(), Collider3D()]);
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
    final fake = FakePhysicsEngine3D();
    final engine = await _engine(Physics3D(engine: fake));
    await engine.services.remove(engine.physics3D!);
    expect(fake.worlds, isEmpty);
  });

  test('where 3-D physics cannot run, initializing fails saying why', () async {
    final engine = Engine(
      config: EngineConfig(
        physics3D: Physics3D(engine: FakePhysicsEngine3D(unavailableReason: 'not here')),
      ),
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
    final engine = await _engine(Physics3D(engine: FakePhysicsEngine3D()));
    final loaded =
        engine.context.definitions.definitionByType('RigidBody3D')!.decode({
              'type': 'RigidBody3D',
              'fields': {'bodyType': 'kinematic', 'layer': 2, 'mass': 4},
            })
            as RigidBody3D;
    expect(loaded.bodyType, BodyType3D.kinematic);
    expect(loaded.layer, 2);
    expect(loaded.mass, 4);
  });

  test('registerSchemas teaches a bare context the components, for tools', () {
    final context = EngineContext();
    addTearDown(context.dispose);
    Physics3D.registerSchemas(context);
    expect(context.definitions.definitionByType('CharacterBody3D'), isNotNull);
  });
}
