// PhysicsSystem3D against the fake backend: bodies, characters and joints
// follow their components, gameplay reaches the world, and what happens
// comes back as transforms and events.

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

const _dt = 1 / 60;

({World world, FakePhysicsWorld3D physics, PhysicsSystem3D system}) _setUp({
  bool stay = false,
}) {
  final physics = FakePhysicsWorld3D(
    PhysicsWorldSettings3D(reportContactStay: stay),
  );
  final system = PhysicsSystem3D(physics);
  final world = World()..initialize();
  world.addSystem(system);
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics, system: system);
}

/// A 20 m floor whose top is at y = 0 (+Y is down).
Entity _floor(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(0, 0.5, 0)),
  Collider3D(size: Vector3(20, 1, 20)),
], name: 'Floor');

Entity _box(World world, Vector3 at, {String? name, RigidBody3D? body}) =>
    world.createEntityWithComponents([
      TransformComponent(position: at),
      Collider3D(),
      body ?? RigidBody3D(),
    ], name: name);

void main() {
  test('runs at physics priority', () {
    final (:world, :physics, :system) = _setUp();
    expect(system.priority, SystemPriorities.physics);
  });

  group('bodies', () {
    test('a box falls under +Y gravity, lands, and its transform follows', () {
      final (:world, :physics, :system) = _setUp();
      final floor = _floor(world);
      final box = _box(world, Vector3(0, -3, 0));
      world.update(_dt);
      expect(physics.bodies, hasLength(2));
      expect(
        physics.bodies[system.bodyOf(floor)]!.type,
        BodyType3D.static,
        reason: 'a collider alone is a static body',
      );

      final t = box.getComponent<TransformComponent>()!;
      world.update(_dt);
      expect(
        t.position.y,
        greaterThan(t.prevPosition.y),
        reason: 'falling, +Y down',
      );
      for (var i = 0; i < 180; i++) {
        world.update(_dt);
      }
      expect(
        t.position.y,
        closeTo(-0.5, 0.02),
        reason: 'resting on the floor top',
      );
      final rigid = box.getComponent<RigidBody3D>()!;
      expect(rigid.body, isNot(0));
      expect(rigid.linearVelocity.length, lessThan(0.1));
    });

    test(
      'a body that has not moved keeps its previous pose equal to its pose',
      () {
        final (:world, :physics, :system) = _setUp();
        final floor = _floor(world);
        world.update(_dt);
        final t = floor.getComponent<TransformComponent>()!;
        t.prevPosition.setValues(9, 9, 9); // A snapshot restored over it, say.
        world.update(_dt);
        expect(t.prevPosition, t.position);
      },
    );

    test('forces, impulses and velocities reach the body before the step', () {
      final (:world, :physics, :system) = _setUp();
      final box = _box(
        world,
        Vector3.zero(),
        body: RigidBody3D(gravityScale: 0),
      );
      world.update(_dt);
      final rigid = box.getComponent<RigidBody3D>()!;
      rigid.setVelocity(Vector3(2, 0, 0));
      world.update(_dt);
      expect(rigid.linearVelocity.x, closeTo(2, 0.05));
      rigid.addImpulse(Vector3(0, 0, 3));
      world.update(_dt);
      expect(rigid.linearVelocity.z, closeTo(3, 0.05));
      expect(rigid.pendingImpulse.length, 0, reason: 'used up');
    });

    test('a hand-written transform teleports a dynamic body', () {
      final (:world, :physics, :system) = _setUp();
      final box = _box(
        world,
        Vector3.zero(),
        body: RigidBody3D(gravityScale: 0),
      );
      world.update(_dt);
      final t = box.getComponent<TransformComponent>()!;
      t.position.setValues(5, 0, 0);
      world.update(_dt);
      expect(physics.bodies[system.bodyOf(box)]!.position.x, 5);
      expect(t.prevPosition.x, 5, reason: 'a teleport is not drawn as a slide');
    });

    test(
      'a kinematic body moved by gameplay is moved by the physics, drawn from where it was',
      () {
        final (:world, :physics, :system) = _setUp();
        final lift = _box(
          world,
          Vector3.zero(),
          body: RigidBody3D(bodyType: BodyType3D.kinematic),
        );
        world.update(_dt);
        final t = lift.getComponent<TransformComponent>()!;
        t.position.setValues(1, 0, 0);
        world.update(_dt);
        final body = physics.bodies[system.bodyOf(lift)]!;
        expect(body.position.x, 1);
        expect(
          body.linearVelocity.x,
          closeTo(60, 1e-6),
          reason: 'the velocity that gets it there',
        );
        expect(t.position.x, 1);
        expect(t.prevPosition.x, 0, reason: 'interpolated from its old place');

        // Left alone, it stops where it was put rather than drifting on.
        world.update(_dt);
        world.update(_dt);
        expect(body.linearVelocity.x, 0);
        expect(t.position.x, 1);
      },
    );

    test(
      'a changed collider rebuilds the body; a changed friction does not',
      () {
        final (:world, :physics, :system) = _setUp();
        final box = _box(
          world,
          Vector3.zero(),
          body: RigidBody3D(gravityScale: 0),
        );
        world.update(_dt);
        final first = system.bodyOf(box);
        box.getComponent<RigidBody3D>()!.friction = 0.9;
        world.update(_dt);
        expect(system.bodyOf(box), first);
        expect(physics.bodies[first]!.friction, 0.9);

        box.getComponent<Collider3D>()!.size = Vector3(2, 2, 2);
        world.update(_dt);
        expect(system.bodyOf(box), isNot(first));
        expect(physics.isBody(first), isFalse);
        expect(
          physics.bodies[system.bodyOf(box)]!.shape,
          const BoxShape3D(1, 1, 1),
        );
      },
    );

    test('a scaled entity gets a scaled shape', () {
      final (:world, :physics, :system) = _setUp();
      final box = world.createEntityWithComponents([
        TransformComponent(position: Vector3.zero(), scale: Vector3(2, 3, 4)),
        Collider3D(),
      ]);
      world.update(_dt);
      expect(
        physics.bodies[system.bodyOf(box)]!.shape,
        const BoxShape3D(1, 1.5, 2),
      );
    });

    test('a switched-off or destroyed entity loses its body', () {
      final (:world, :physics, :system) = _setUp();
      final box = _box(world, Vector3.zero());
      world.update(_dt);
      final body = system.bodyOf(box);
      box.isActive = false;
      world.update(_dt);
      expect(physics.isBody(body), isFalse);
      box.isActive = true;
      world.update(_dt);
      final again = system.bodyOf(box);
      expect(again, isNot(0));
      world.destroyEntity(box);
      world.update(_dt);
      expect(physics.isBody(again), isFalse);
      expect(physics.bodyCount, 0);
    });

    test(
      'a mesh on a dynamic body is not made, and not asked for again every step',
      () {
        final (:world, :physics, :system) = _setUp();
        final terrain = world.createEntityWithComponents([
          TransformComponent(),
          Collider3D(
            shape: ColliderShape3D.heightField,
            heights: List.filled(16, 0.0),
            heightFieldSize: 4,
          ),
          RigidBody3D(),
        ]);
        world.update(_dt);
        expect(system.bodyOf(terrain), 0);
        terrain.getComponent<RigidBody3D>()!.bodyType = BodyType3D.static;
        world.update(_dt);
        expect(system.bodyOf(terrain), isNot(0));
      },
    );

    test('taking the system out removes everything it made', () {
      final (:world, :physics, :system) = _setUp();
      _floor(world);
      _box(world, Vector3(0, -3, 0));
      world.update(_dt);
      expect(physics.bodyCount, 2);
      world.removeSystem(system);
      expect(physics.bodyCount, 0);
    });
  });

  group('events', () {
    test(
      'a box landing fires an enter with both entities, and a lift-off an exit',
      () {
        final (:world, :physics, :system) = _setUp();
        final floor = _floor(world);
        final box = _box(world, Vector3(0, -1, 0));
        final enters = <CollisionEnter3DEvent>[];
        final exits = <CollisionExit3DEvent>[];
        world.events.on<CollisionEnter3DEvent>(enters.add);
        world.events.on<CollisionExit3DEvent>(exits.add);
        for (var i = 0; i < 60; i++) {
          world.update(_dt);
        }
        expect(enters, hasLength(1));
        expect({enters.single.entityA, enters.single.entityB}, {floor, box});

        box.getComponent<RigidBody3D>()!.setVelocity(Vector3(0, -5, 0));
        for (var i = 0; i < 10; i++) {
          world.update(_dt);
        }
        expect(exits, hasLength(1));
      },
    );

    test('stays are only sent when asked for', () {
      final (:world, :physics, :system) = _setUp(stay: true);
      _floor(world);
      _box(world, Vector3(0, -0.6, 0));
      final stays = <CollisionStay3DEvent>[];
      world.events.on<CollisionStay3DEvent>(stays.add);
      for (var i = 0; i < 30; i++) {
        world.update(_dt);
      }
      expect(stays, isNotEmpty);
    });

    test(
      'a sensor names itself first, whichever body the backend lists first',
      () {
        final (:world, :physics, :system) = _setUp();
        final zone = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, -2, 0)),
          Collider3D(size: Vector3(4, 2, 4)),
          RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
        ], name: 'Zone');
        final ball = _box(world, Vector3(0, -6, 0), name: 'Ball');
        final enters = <SensorEnter3DEvent>[];
        final exits = <SensorExit3DEvent>[];
        world.events.on<SensorEnter3DEvent>(enters.add);
        world.events.on<SensorExit3DEvent>(exits.add);
        for (var i = 0; i < 120; i++) {
          world.update(_dt);
        }
        expect(enters.single.sensor, zone);
        expect(enters.single.other, ball);
        expect(exits.single.sensor, zone);
      },
    );
  });

  group('characters', () {
    Entity character(World world, Vector3 at, {CharacterBody3D? body}) =>
        world.createEntityWithComponents([
          TransformComponent(position: at),
          body ?? CharacterBody3D(),
        ], name: 'Hero');

    test('stands on the floor, walks, and its feet are its position', () {
      final (:world, :physics, :system) = _setUp();
      _floor(world);
      final hero = character(world, Vector3(0, -1, 0));
      final comp = hero.getComponent<CharacterBody3D>()!;
      for (var i = 0; i < 60; i++) {
        world.update(_dt);
      }
      expect(comp.isGrounded, isTrue);
      final t = hero.getComponent<TransformComponent>()!;
      expect(t.position.y, closeTo(0, 1e-9));
      expect(comp.groundEntity?.name, 'Floor');

      for (var i = 0; i < 60; i++) {
        comp.moveVelocity.setValues(2, 0, 0);
        world.update(_dt);
      }
      expect(t.position.x, closeTo(2, 0.05));
      expect(comp.isGrounded, isTrue);
    });

    test('jumps from the ground and lands again', () {
      final (:world, :physics, :system) = _setUp();
      _floor(world);
      final hero = character(world, Vector3.zero());
      final comp = hero.getComponent<CharacterBody3D>()!;
      final t = hero.getComponent<TransformComponent>()!;
      world.update(_dt);
      expect(comp.isGrounded, isTrue);
      comp.jump(5);
      world.update(_dt);
      expect(comp.isGrounded, isFalse);
      var highest = 0.0;
      for (var i = 0; i < 120; i++) {
        world.update(_dt);
        if (t.position.y < highest) highest = t.position.y;
      }
      expect(highest, lessThan(-1), reason: 'v²/2g ≈ 1.27 m up');
      expect(comp.isGrounded, isTrue);
      expect(t.position.y, closeTo(0, 1e-6));
    });

    test('rides a moving platform', () {
      final (:world, :physics, :system) = _setUp();
      final platform = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0.25, 0)),
        Collider3D(size: Vector3(4, 0.5, 4)),
        RigidBody3D(bodyType: BodyType3D.kinematic),
      ], name: 'Platform');
      final hero = character(world, Vector3.zero());
      final comp = hero.getComponent<CharacterBody3D>()!;
      world.update(_dt);
      platform.getComponent<RigidBody3D>()!.setVelocity(Vector3(1, 0, 0));
      for (var i = 0; i < 60; i++) {
        world.update(_dt);
      }
      expect(comp.groundEntity, platform);
      expect(
        hero.getComponent<TransformComponent>()!.position.x,
        closeTo(1, 0.1),
      );
    });

    test(
      'a hand-written position teleports it; without gravity it moves as told',
      () {
        final (:world, :physics, :system) = _setUp();
        final hero = character(
          world,
          Vector3.zero(),
          body: CharacterBody3D(useGravity: false),
        );
        world.update(_dt);
        final t = hero.getComponent<TransformComponent>()!;
        t.position.setValues(10, -5, 0);
        world.update(_dt);
        expect(physics.characters.values.single.position, Vector3(10, -5, 0));
        final comp = hero.getComponent<CharacterBody3D>()!;
        comp.moveVelocity.setValues(0, -3, 0);
        world.update(_dt);
        expect(t.position.y, closeTo(-5.05, 1e-9), reason: 'flies up at 3 m/s');
      },
    );

    test('sensors see a detectable character', () {
      final (:world, :physics, :system) = _setUp();
      _floor(world);
      final coin = world.createEntityWithComponents([
        TransformComponent(position: Vector3(3, -1, 0)),
        Collider3D(size: Vector3(0.5, 0.5, 0.5)),
        RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
      ], name: 'Coin');
      final hero = character(world, Vector3.zero());
      final enters = <SensorEnter3DEvent>[];
      world.events.on<SensorEnter3DEvent>(enters.add);
      final comp = hero.getComponent<CharacterBody3D>()!;
      for (var i = 0; i < 120; i++) {
        comp.moveVelocity.setValues(3, 0, 0);
        world.update(_dt);
      }
      expect(enters.map((e) => (e.sensor, e.other)), contains((coin, hero)));
    });

    test('a changed capsule is made again where it stands', () {
      final (:world, :physics, :system) = _setUp();
      final hero = character(world, Vector3(1, 0, 0));
      world.update(_dt);
      final first = system.characterOf(hero);
      hero.getComponent<CharacterBody3D>()!.height = 1.2;
      world.update(_dt);
      expect(system.characterOf(hero), isNot(first));
      expect(physics.isCharacter(first), isFalse);
      expect(physics.characters, hasLength(1));
    });

    test('is drawn turning from where the last step left it', () {
      final (:world, :physics, :system) = _setUp();
      _floor(world);
      final hero = character(world, Vector3(0, 0, 0));
      final t = hero.getComponent<TransformComponent>()!;
      final up = Vector3(0, 1, 0);
      world.update(_dt);

      // A controller turns it before the step, as it moves it.
      t.setRotation(Quaternion.axisAngle(up, 0.5));
      world.update(_dt);
      t.setRotation(Quaternion.axisAngle(up, 0.7));
      hero.getComponent<CharacterBody3D>()!.moveVelocity.setValues(3, 0, 0);
      world.update(_dt);

      final previous = Quaternion.identity();
      t.previousRotationInto(previous);
      expect(previous.sameRotation(Quaternion.axisAngle(up, 0.5)), isTrue);
      expect(t.prevPosition.x, closeTo(0, 1e-9));
      expect(t.position.x, closeTo(3 * _dt, 1e-6));
      expect(t.eulerY, closeTo(0.7, 1e-12), reason: 'its rotation is left alone');
    });
  });

  group('joints', () {
    test(
      'made once both bodies exist, again when a setting changes, gone with an entity',
      () {
        final (:world, :physics, :system) = _setUp();
        final hinge = HingeJoint3D(
          connectedBody: const EntityTarget.name('Frame'),
          anchor: Vector3(-0.5, 0, 0),
        );
        final door = _box(world, Vector3(1, 0, 0));
        door.addComponent(hinge);
        world.update(_dt);
        expect(physics.joints, isEmpty, reason: 'no Frame yet');

        final frame = _box(
          world,
          Vector3.zero(),
          name: 'Frame',
          body: RigidBody3D(bodyType: BodyType3D.static),
        );
        world.update(_dt);
        final joint = physics.joints.values.single;
        expect(joint.bodyA, system.bodyOf(door));
        expect(joint.bodyB, system.bodyOf(frame));
        expect(joint.settings.kind, JointKind3D.hinge);
        expect(
          joint.settings.pointA.x,
          closeTo(0.5, 1e-9),
          reason: 'the anchor in world space',
        );
        expect(hinge.joint, joint.handle);

        hinge.motor = MotorState3D.position;
        hinge.motorTarget = 1.2;
        world.update(_dt);
        expect(
          physics.joints.values.single,
          same(joint),
          reason: 'a motor change is not a rebuild',
        );
        expect(joint.motorState, MotorState3D.position);
        expect(hinge.angle, 1.2, reason: 'read back after the step');

        hinge.useLimits = true;
        world.update(_dt);
        expect(physics.joints.values.single, isNot(same(joint)));

        world.destroyEntity(frame);
        world.update(_dt);
        expect(physics.joints, isEmpty);
        expect(hinge.joint, 0);
      },
    );

    test('a joint to nobody holds the body to the world', () {
      final (:world, :physics, :system) = _setUp();
      final weight = _box(world, Vector3.zero());
      weight.addComponent(DistanceJoint3D(connectedAnchor: Vector3(0, -3, 0)));
      world.update(_dt);
      final joint = physics.joints.values.single;
      expect(joint.bodyB, 0);
      expect(joint.settings.pointB, Vector3(0, -3, 0));
    });

    test('switching a joint off keeps it', () {
      final (:world, :physics, :system) = _setUp();
      final a = _box(world, Vector3.zero());
      final fixed = FixedJoint3D();
      a.addComponent(fixed);
      world.update(_dt);
      fixed.enabled = false;
      world.update(_dt);
      expect(physics.joints.values.single.enabled, isFalse);
    });
  });

  group('queries', () {
    test('rays, sweeps and overlaps answer in entities', () {
      final (:world, :physics, :system) = _setUp();
      final floor = _floor(world);
      final crate = _box(
        world,
        Vector3(0, -0.5, 0),
        name: 'Crate',
        body: RigidBody3D(bodyType: BodyType3D.static),
      );
      world.update(_dt);
      final queries = Physics3DQueries(system);

      final hit = queries.raycast(Vector3(0, -10, 0), Vector3(0, 1, 0))!;
      expect(hit.entity, crate);
      expect(hit.point.y, closeTo(-1, 1e-9));
      expect(hit.distance, closeTo(9, 1e-9));
      expect(hit.normal, Vector3(0, -1, 0));

      final all = queries.raycastAll(Vector3(0, -10, 0), Vector3(0, 1, 0));
      expect(all.map((h) => h.entity), [crate, floor]);

      expect(
        queries
            .raycast(Vector3(0, -10, 0), Vector3(0, 1, 0), ignore: crate)!
            .entity,
        floor,
      );
      expect(queries.raycast(Vector3(0, -10, 0), Vector3(0, -1, 0)), isNull);

      final swept = queries.sphereCast(
        Vector3(0, -10, 0),
        0.5,
        Vector3(0, 1, 0),
      )!;
      expect(swept.entity, crate);
      expect(swept.distance, closeTo(8.5, 1e-9));

      expect(queries.overlapSphere(Vector3(0, -0.5, 0), 0.1), [crate]);
      expect(queries.overlapBox(Vector3(0, 0.5, 0), Vector3(1, 0.4, 1)), [
        floor,
      ]);
    });
  });
}
