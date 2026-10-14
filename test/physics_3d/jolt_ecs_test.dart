// The 3-D components and PhysicsSystem3D on Jolt: what a 3-D game does.
// This package's pubspec asks for Jolt to be built (hooks: user_defines).

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

const _dt = 1 / 60;
final _backend = JoltPhysicsEngine();

World _world({void Function(PhysicsWorld3D)? withPhysics}) {
  final physics = _backend.createWorld(PhysicsWorldSettings3D());
  final world = World()..initialize();
  world.addSystem(PhysicsSystem3D(physics));
  withPhysics?.call(physics);
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return world;
}

Entity _static(World world, Vector3 at, Vector3 size, {String? name}) =>
    world.createEntityWithComponents([
      TransformComponent(position: at),
      Collider3D(size: size),
    ], name: name);

void _run(World world, int frames, [void Function(int frame)? each]) {
  for (var i = 0; i < frames; i++) {
    each?.call(i);
    world.update(_dt);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Physics3D() runs on Jolt by default, here where it is built', () async {
    expect(Physics3D.isSupported, isTrue);
    expect(Physics3D.unsupportedReason, isNull);
    final engine = Engine(config: EngineConfig(physics3D: Physics3D()));
    addTearDown(engine.dispose);
    await engine.initialize();
    final physics3D = engine.physics3D!;
    expect(physics3D.engine, isA<JoltPhysicsEngine>());
    expect(physics3D.hasWorld, isFalse);
    engine.world.createEntityWithComponents([TransformComponent(), Collider3D()]);
    engine.world.update(_dt);
    expect(physics3D.hasWorld, isTrue);
    expect(physics3D.world.bodyCount, 1);
  });

  test('crates fall onto the floor and their transforms follow', () {
    final world = _world();
    _static(world, Vector3(0, 0.5, 0), Vector3(20, 1, 20));
    final crates = [
      for (var i = 0; i < 3; i++)
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(i * 2.0, -2 - i.toDouble(), 0)),
          Collider3D(),
          RigidBody3D(),
        ]),
    ];
    _run(world, 240);
    for (final crate in crates) {
      final t = crate.getComponent<TransformComponent>()!;
      expect(t.position.y, closeTo(-0.5, 0.03));
      expect(
        t.prevPosition.y,
        closeTo(t.position.y, 1e-6),
        reason: 'at rest: drawn where it is',
      );
    }
  });

  test(
    'a character climbs stairs, picks up a coin and rides a platform the game moves',
    () {
      final world = _world();
      _static(world, Vector3(0, 0.5, 0), Vector3(40, 1, 40), name: 'Floor');
      for (var k = 1; k <= 3; k++) {
        _static(
          world,
          Vector3(2 + 0.5 * (k - 1) + 2.5, -0.1 * k, 0),
          Vector3(5, 0.2 * k, 4),
        );
      }
      final coin = world.createEntityWithComponents([
        TransformComponent(position: Vector3(4, -1.2, 0)),
        Collider3D(shape: ColliderShape3D.sphere, radius: 0.3),
        RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
      ], name: 'Coin');
      final hero = world.createEntityWithComponents([
        TransformComponent(position: Vector3.zero()),
        CharacterBody3D(),
      ], name: 'Hero');
      final picked = <Entity>[];
      world.events.on<SensorEnter3DEvent>((e) {
        if (e.other == hero) picked.add(e.sensor);
      });
      final body = hero.getComponent<CharacterBody3D>()!;
      final t = hero.getComponent<TransformComponent>()!;
      _run(world, 120, (_) => body.moveVelocity.setValues(2, 0, 0));
      expect(t.position.y, closeTo(-0.6, 0.05), reason: 'on the third step');
      expect(picked, [coin]);

      // A platform the game moves by writing its transform.
      final platform = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, -0.35, 0)),
        Collider3D(size: Vector3(3, 0.5, 3)),
        RigidBody3D(bodyType: BodyType3D.kinematic),
      ], name: 'Platform');
      t.position.setValues(10, -0.6, 0); // Teleported onto it.
      _run(world, 20, (_) => body.moveVelocity.setZero());
      expect(body.groundEntity, platform);
      final startX = t.position.x;
      final pt = platform.getComponent<TransformComponent>()!;
      _run(world, 60, (_) => pt.position.x += 2 * _dt);
      expect(t.position.x - startX, closeTo(2, 0.15), reason: 'carried along');
      expect(body.isGrounded, isTrue);
    },
  );

  test('a door on a hinge swings to its motor target', () {
    final world = _world();
    // Jointed bodies still collide, so the frame stands clear of the door.
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(-0.5, -1, 0)),
      Collider3D(size: Vector3(0.2, 2, 0.2)),
    ], name: 'Frame');
    final hinge = HingeJoint3D(
      connectedBody: const EntityTarget.name('Frame'),
      anchor: Vector3(-0.5, 0, 0),
      motor: MotorState3D.position,
      motorTarget: 1,
    );
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0.6, -1, 0)),
      Collider3D(size: Vector3(1, 2, 0.1)),
      RigidBody3D(gravityScale: 0),
      hinge,
    ], name: 'Door');
    _run(world, 120);
    expect(hinge.joint, isNot(0));
    expect(hinge.angle, closeTo(1, 0.05));
  });

  test('500 bodies through PhysicsSystem3D on Jolt', () {
    final world = _world();
    _static(world, Vector3(0, 0.5, 0), Vector3(60, 1, 60));
    for (var i = 0; i < 500; i++) {
      world.createEntityWithComponents([
        TransformComponent(
          position: Vector3(
            (i % 10) * 1.5 - 7,
            -1 - (i ~/ 100) * 1.5,
            ((i ~/ 10) % 10) * 1.5 - 7,
          ),
        ),
        Collider3D(
          shape: i.isEven ? ColliderShape3D.box : ColliderShape3D.sphere,
        ),
        RigidBody3D(),
      ]);
    }
    _run(world, 30);
    const frames = 240;
    final watch = Stopwatch()..start();
    _run(world, frames);
    watch.stop();
    final ms = watch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'just_jolt + PhysicsSystem3D perf, 500 bodies: ${ms.toStringAsFixed(3)} ms per update',
    );
    expect(ms, lessThan(16));
  });
}
