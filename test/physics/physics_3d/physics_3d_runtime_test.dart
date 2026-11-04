// Physics3DSystem while a game runs, against the fake backend: every
// rigid-body command reaches the body once and is used up; settings
// changed on a live body reach it; a joint whose other body is its own
// joins nothing; a teleported character starts again from rest; and the
// solid parts a mesh or a height field gives become the right shapes.

@Tags(['physics3d'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_physics_engine/testing.dart';

const _dt = 1 / 60;

({World world, FakePhysics3DWorld physics, Physics3DSystem system}) _setUp() {
  final physics = FakePhysics3DWorld(Physics3DWorldSettings());
  final system = Physics3DSystem(physics);
  final world = World()..initialize();
  world.addSystem(system);
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics, system: system);
}

void main() {
  group('rigid-body commands', () {
    late World world;
    late FakePhysics3DWorld physics;
    late Physics3DSystem system;
    late RigidBody3DComponent rigid;
    late Entity box;

    FakeBody3D body() => physics.bodies[system.bodyOf(box)]!;

    setUp(() {
      (:world, :physics, :system) = _setUp();
      rigid = RigidBody3DComponent(gravityScale: 0, canSleep: false);
      box = world.createEntityWithComponents([
        TransformComponent(),
        Collider3DComponent(),
        rigid,
      ]);
      world.update(_dt);
    });

    // An update of no time sends what was asked but steps nothing, so what
    // the body was given is still there to see.
    test('a force reaches the body once, and is used up', () {
      rigid.addForce(Vector3(3, 0, 0));
      world.update(0);
      expect(body().force, Vector3(3, 0, 0));
      expect(rigid.pendingForce, Vector3.zero());
      world.update(0);
      expect(body().force, Vector3(3, 0, 0), reason: 'not sent twice');
    });

    test('a torque reaches the body once, and is used up', () {
      rigid.addTorque(Vector3(0, 2, 0));
      world.update(0);
      expect(body().torque, Vector3(0, 2, 0));
      expect(rigid.pendingTorque, Vector3.zero());
      world.update(0);
      expect(body().torque, Vector3(0, 2, 0));
    });

    test('an angular impulse turns it once', () {
      rigid.addAngularImpulse(Vector3(0, 0, 4));
      world.update(0);
      final spin = Vector3.copy(body().angularVelocity);
      expect(spin.z, greaterThan(0));
      expect(rigid.pendingAngularImpulse, Vector3.zero());
      world.update(0);
      expect(body().angularVelocity, spin);
    });

    test('a spin is set', () {
      rigid.setAngularVelocity(Vector3(1, 2, 3));
      world.update(0);
      expect(body().angularVelocity, Vector3(1, 2, 3));
      expect(rigid.pendingAngularVelocity, isNull);
    });

    test('wakeUp wakes a sleeping body', () {
      final sleeper = RigidBody3DComponent(gravityScale: 0);
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(5, 0, 0)),
        Collider3DComponent(),
        sleeper,
      ]);
      for (var i = 0; i < 60; i++) {
        world.update(_dt);
      }
      final b = physics.bodies[system.bodyOf(e)]!;
      expect(b.awake, isFalse, reason: 'at rest long enough to sleep');
      sleeper.wakeUp();
      world.update(0);
      expect(b.awake, isTrue);
      expect(sleeper.pendingWake, isFalse);
    });

    test('settings changed on a live body reach it', () {
      final made = system.bodyOf(box);
      rigid
        ..friction = 0.1
        ..restitution = 0.7
        ..gravityScale = 2
        ..layer = 3
        ..continuousCollision = true;
      world.update(0);
      expect(system.bodyOf(box), made, reason: 'changed, not made again');
      final b = body();
      expect(b.friction, 0.1);
      expect(b.restitution, 0.7);
      expect(b.gravityFactor, 2);
      expect(b.layer, 3);
      expect(b.motionQuality, Motion3DQuality.linearCast);
    });
  });

  test('a joint whose other body is its own joins nothing', () {
    final (:world, :physics, :system) = _setUp();
    world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(),
      RigidBody3DComponent(),
      HingeJoint3DComponent(connectedBody: const EntityTarget.self()),
    ]);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(3, 0, 0)),
      Collider3DComponent(),
      RigidBody3DComponent(),
      TagComponent('door'),
      // Its tag is its own too: the oldest so tagged is itself.
      FixedJoint3DComponent(connectedBody: const EntityTarget.tag('door')),
    ]);
    world.update(_dt);
    expect(physics.joints, isEmpty);
  });

  test('a teleported character starts again from rest, in the air', () {
    final (:world, :physics, :system) = _setUp();
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0.5, 0)),
      Collider3DComponent(size: Vector3(20, 1, 20)),
    ]);
    final character = CharacterBody3DComponent();
    final player = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -20, 0)),
      character,
    ]);
    for (var i = 0; i < 30; i++) {
      world.update(_dt);
    }
    expect(character.velocity.y, greaterThan(1), reason: 'falling');

    player.getComponent<TransformComponent>()!.position.setValues(0, -40, 0);
    world.update(_dt);
    // One step of gravity from rest, not the fall it had.
    expect(character.velocity.y, lessThan(0.5));
    expect(character.groundEntity, isNull);
  });

  group('solid parts', () {
    test('a mirrored mesh turns each triangle back', () {
      final part = SolidMesh(
        Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
        Uint32List.fromList([0, 1, 2]),
      );
      final kept = Collider3DShapes.solidPart(part, 1, 1, 1)! as Mesh3DShape;
      expect(kept.indices, [0, 1, 2]);
      final mirrored =
          Collider3DShapes.solidPart(part, -1, 1, 1)! as Mesh3DShape;
      expect(mirrored.indices, [0, 2, 1]);
      expect(mirrored.positions[3], -1, reason: 'x mirrored');
      expect(part.indices, [0, 1, 2], reason: "the source's are left alone");
    });

    test('a height field scales its heights but keeps its holes', () {
      const hole = SolidHeightField.holeHeight;
      final heights = Float32List.fromList([
        for (var i = 0; i < 16; i++) i == 5 ? hole : i.toDouble(),
      ]);
      final shape =
          Collider3DShapes.solidPart(SolidHeightField(heights, 4, 1), 1, 2, 1)!
              as HeightField3DShape;
      expect(shape.heights[3], 6);
      expect(shape.heights[5], heights[5], reason: 'a hole, not doubled');
    });
  });
}
