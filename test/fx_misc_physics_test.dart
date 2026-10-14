// PhysicsSystem and PhysicsJointBindingSystem: bodies leave the shared engine
// with the system, riders stop standing on what is gone, a resting body may
// sleep and anything the game does wakes it, and joints are made once and
// never destroyed twice.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/just_physics_engine.dart'
    show PrismaticJoint;

const _frame = 1 / 60;

({World world, PhysicsEngine physics}) _setUp({
  PhysicsEngine? engine,
  double gravityY = 981,
  bool joints = false,
}) {
  final physics = (engine ?? PhysicsEngine())..initialize();
  physics.setGravity(0, gravityY);
  final world = World()..initialize();
  world.addSystem(PhysicsSystem(physics));
  if (joints) world.addSystem(PhysicsJointBindingSystem(physics));
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics);
}

/// A slab whose top is at y = 280.
Entity _ground(World world, {double x = 0, String name = 'Ground'}) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, 300, 0)),
      RigidBody2D(bodyType: BodyType.static, restitution: 0),
      Collider2D(size: Vector2(2000, 40)),
    ], name: name);

Entity _box(
  World world, {
  double x = 0,
  double y = 0,
  String? name,
  double gravityScale = 1,
  List<Component> extra = const [],
}) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(x, y, 0)),
  VelocityComponent(),
  RigidBody2D(
    restitution: 0,
    linearDamping: 0,
    lockRotation: true,
    gravityScale: gravityScale,
  ),
  Collider2D(size: Vector2(20, 20)),
  ...extra,
], name: name);

void _step(World world, [int frames = 1]) {
  for (var i = 0; i < frames; i++) {
    world.update(_frame);
  }
}

PhysicsBody _bodyOf(Entity entity) =>
    entity.getComponent<PhysicsBodyRefComponent>()!.body;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bodies leave with the system', () {
    test('clearSystems takes every body out of the shared engine', () {
      final (:world, :physics) = _setUp();
      _ground(world);
      final box = _box(world);
      _step(world);
      expect(physics.stats['bodyCount'], 2);

      world.clearSystems();
      expect(physics.stats['bodyCount'], 0);
      expect(box.hasComponent<PhysicsBodyRefComponent>(), isFalse);
    });

    test('so does removing the system alone', () {
      final (:world, :physics) = _setUp();
      _box(world);
      _step(world);
      world.removeSystem(world.getSystem<PhysicsSystem>()!);
      expect(physics.stats['bodyCount'], 0);
    });

    test('a system added again builds the bodies afresh', () {
      final (:world, :physics) = _setUp();
      final box = _box(world, y: 100);
      _step(world);
      world.clearSystems();
      world.addSystem(PhysicsSystem(physics));
      _step(world);
      expect(physics.stats['bodyCount'], 1);
      expect(box.hasComponent<PhysicsBodyRefComponent>(), isTrue);
    });
  });

  group('entities and their bodies', () {
    test('a destroyed platform stops grounding its rider', () {
      final (:world, physics: _) = _setUp();
      final platform = _ground(world);
      final rider = _box(world, y: 260);
      _step(world, 60);
      final comp = rider.getComponent<RigidBody2D>()!;
      expect(comp.isGrounded, isTrue);
      expect(comp.groundEntity, same(platform));

      world.destroyEntity(platform);
      _step(world);
      expect(comp.isGrounded, isFalse);
      expect(comp.groundEntity, isNull);
    });

    test('an entity that takes a destroyed one\'s id gets its own body', () {
      final (:world, :physics) = _setUp(gravityY: 0);
      final first = _box(world);
      _step(world);
      final oldBody = _bodyOf(first);

      world.destroyAllEntities();
      final second = _box(world, x: 500);
      _step(world);

      final ref = second.getComponent<PhysicsBodyRefComponent>();
      expect(ref, isNotNull);
      expect(ref!.body, isNot(same(oldBody)));
      expect(physics.stats['bodyCount'], 1);
      expect(
        second.getComponent<TransformComponent>()!.position.x,
        closeTo(500, 1e-3),
      );
    });

    test('switched off, an entity leaves; switched on, it comes back', () {
      final (:world, :physics) = _setUp(gravityY: 0);
      final box = _box(world, x: 40);
      _step(world);
      expect(physics.stats['bodyCount'], 1);

      box.isActive = false;
      _step(world);
      expect(physics.stats['bodyCount'], 0);
      expect(box.hasComponent<PhysicsBodyRefComponent>(), isFalse);

      box.getComponent<TransformComponent>()!.position.x = 90;
      box.isActive = true;
      // Switching back on may not change the world's structure; a query the
      // world already cached would miss it, but the physics system must not.
      _step(world);
      expect(physics.stats['bodyCount'], 1);
      expect(_bodyOf(box).position.x, closeTo(90, 1e-3));
    });

    test('a static body\'s transform takes the stored position once', () {
      final (:world, physics: _) = _setUp();
      final wall = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0.1, 0.3, 0)),
        RigidBody2D(bodyType: BodyType.static),
        Collider2D(size: Vector2(10, 10)),
      ]);
      _step(world);
      final transform = wall.getComponent<TransformComponent>()!;
      final body = _bodyOf(wall);
      expect(transform.position.x, body.position.x);
      expect(transform.position.y, body.position.y);
      _step(world, 5);
      expect(transform.position.x, body.position.x);
      expect(transform.prevPosition.x, transform.position.x);
    });

    test('a static body moved through its transform carries its load', () {
      final (:world, physics: _) = _setUp();
      final platform = _ground(world);
      final rider = _box(world, y: 260);
      _step(world, 30);
      final riderY = rider.getComponent<TransformComponent>()!.position.y;

      platform.getComponent<TransformComponent>()!.position.y = 400;
      _step(world, 60);
      expect(_bodyOf(platform).position.y, closeTo(400, 1e-3));
      expect(
        rider.getComponent<TransformComponent>()!.position.y,
        closeTo(riderY + 100, 2),
      );
    });
  });

  group('sleep, on the pure-Dart backend', () {
    // Without gravity nothing holds a body down, so at rest it can sleep.
    ({World world, PhysicsEngine physics}) restful() =>
        _setUp(engine: PhysicsEngine.pureDart(), gravityY: 0);

    test('a body at rest falls asleep', () {
      final (:world, physics: _) = restful();
      final box = _box(world);
      _step(world, 60);
      expect(_bodyOf(box).isAwake, isFalse);
    });

    test('a velocity written to a sleeping body wakes it, and it moves', () {
      final (:world, physics: _) = restful();
      final box = _box(world);
      _step(world, 60);
      expect(_bodyOf(box).isAwake, isFalse);

      box.getComponent<VelocityComponent>()!.velocity.x = 120;
      _step(world);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(
        box.getComponent<TransformComponent>()!.position.x,
        greaterThan(1),
      );
    });

    test('a teleport wakes a sleeping body', () {
      final (:world, physics: _) = restful();
      final box = _box(world);
      _step(world, 60);
      expect(_bodyOf(box).isAwake, isFalse);

      box.getComponent<TransformComponent>()!.position.x = 300;
      _step(world);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(_bodyOf(box).position.x, closeTo(300, 1e-6));
    });

    test('a force waiting on a sleeping body wakes it', () {
      final (:world, physics: _) = restful();
      final box = _box(world);
      _step(world, 60);
      _bodyOf(box).applyForce(Vector2(5000, 0));
      _step(world);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(_bodyOf(box).velocity.x, greaterThan(0));
    });

    test('a changed setting wakes it: gravity switched back on', () {
      final (:world, physics: _) = _setUp(
        engine: PhysicsEngine.pureDart(),
        gravityY: 500,
      );
      // Weightless, it rests in mid-air and sleeps.
      final box = _box(world, gravityScale: 0);
      _step(world, 60);
      expect(_bodyOf(box).isAwake, isFalse);

      box.getComponent<RigidBody2D>()!.gravityScale = 1;
      _step(world, 10);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(
        box.getComponent<TransformComponent>()!.position.y,
        greaterThan(1),
      );
    });

    test('a body something keeps moving never sleeps', () {
      final (:world, physics: _) = restful();
      final box = _box(world);
      for (var i = 0; i < 60; i++) {
        box.getComponent<VelocityComponent>()!.velocity.x = 60.0 + i;
        _step(world);
      }
      expect(_bodyOf(box).isAwake, isTrue);
    });
  });

  group('sleep, on Box2D', () {
    test('a body resting on the ground sleeps; input wakes it', () {
      final (:world, physics: _) = _setUp();
      _ground(world);
      final box = _box(world, y: 260);
      _step(world, 120);
      expect(_bodyOf(box).isAwake, isFalse);
      expect(
        box.getComponent<RigidBody2D>()!.isGrounded,
        isTrue,
        reason: 'asleep, it still stands on the ground',
      );

      box.getComponent<VelocityComponent>()!.velocity.x = 200;
      _step(world);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(
        box.getComponent<TransformComponent>()!.position.x,
        greaterThan(1),
      );
    });

    test('a teleport wakes it, and it falls from where it was put', () {
      final (:world, physics: _) = _setUp();
      _ground(world);
      final box = _box(world, y: 260);
      _step(world, 120);
      expect(_bodyOf(box).isAwake, isFalse);

      final transform = box.getComponent<TransformComponent>()!;
      transform.position.setValues(50, 100, 0);
      _step(world, 5);
      expect(_bodyOf(box).isAwake, isTrue);
      expect(transform.position.x, closeTo(50, 1e-3));
      expect(transform.position.y, greaterThan(100));
      expect(transform.position.y, lessThan(200));
    });
  });

  group('joints', () {
    test('a weld on a moving body is made once, not every frame', () {
      final (:world, :physics) = _setUp(
        engine: PhysicsEngine.pureDart(),
        joints: true,
      );
      _box(world, extra: [FixedJoint2D(connectedBody: const EntityTarget.name('B'))]);
      _box(world, x: 30, name: 'B');
      _step(world);
      final joint = physics.joints.single;

      _step(world, 10); // both fall, so the weld's world anchor moves
      expect(physics.joints.single, same(joint));
    });

    test('a changed setting makes the joint again', () {
      final (:world, :physics) = _setUp(
        engine: PhysicsEngine.pureDart(),
        gravityY: 0,
        joints: true,
      );
      final spring = DistanceJoint2D(connectedBody: const EntityTarget.name('B'), length: 40);
      _box(world, extra: [spring]);
      _box(world, x: 40, name: 'B');
      _step(world);
      final first = physics.joints.single as DistanceJoint;
      expect(first.minLength, 40);

      spring.length = 60;
      _step(world);
      final second = physics.joints.single as DistanceJoint;
      expect(second, isNot(same(first)));
      expect(second.minLength, 60);
    });

    test('a prismatic joint takes its limits and motor', () {
      final (:world, :physics) = _setUp(
        engine: PhysicsEngine.pureDart(),
        gravityY: 0,
        joints: true,
      );
      _box(
        world,
        extra: [
          SliderJoint2D(
            connectedBody: const EntityTarget.name('B'),
            useLimits: true,
            minPosition: -5,
            maxPosition: 7,
            enableMotor: true,
            motorSpeed: 3,
          ),
        ],
      );
      _box(world, x: 40, name: 'B');
      _step(world);
      final joint = physics.joints.single as PrismaticJoint;
      expect(joint.limitEnabled, isTrue);
      expect((joint.lowerLimit, joint.upperLimit), (-5, 7));
      expect(joint.motorEnabled, isTrue);
      expect(joint.motorSpeed, 3);
    });

    test('a target renamed away loses its joint; named back, regains it', () {
      final (:world, :physics) = _setUp(
        engine: PhysicsEngine.pureDart(),
        gravityY: 0,
        joints: true,
      );
      _box(world, extra: [DistanceJoint2D(connectedBody: const EntityTarget.name('B'))]);
      final b = _box(world, x: 40, name: 'B');
      _step(world);
      expect(physics.joints, hasLength(1));

      b.name = 'C';
      _step(world);
      expect(physics.joints, isEmpty);

      b.name = 'B';
      _step(world);
      expect(physics.joints, hasLength(1));
    });

    test('on Box2D, a joint that went with its body is not destroyed '
        'again', () {
      final (:world, :physics) = _setUp(gravityY: 0, joints: true);
      _box(world, extra: [DistanceJoint2D(connectedBody: const EntityTarget.name('B'))]);
      final b = _box(world, x: 40, name: 'B');
      _step(world);
      final joint = physics.joints.single;
      expect(joint, isA<Box2DJoint>());

      // Box2D destroys B's joints with B's body; destroying this one as well
      // would free it twice.
      world.destroyEntity(b);
      _step(world);
      expect(physics.joints, isEmpty);
      expect((joint as Box2DJoint).isDestroyed, isFalse);
    });

    test('on Box2D, clearing the systems leaves no joint to destroy twice', () {
      final (:world, :physics) = _setUp(gravityY: 0, joints: true);
      _box(world, extra: [FixedJoint2D(connectedBody: const EntityTarget.name('B'))]);
      _box(world, x: 30, name: 'B');
      _step(world);
      final joint = physics.joints.single as Box2DJoint;

      world.clearSystems();
      expect(physics.joints, isEmpty);
      expect(joint.isDestroyed, isFalse);
    });

    test('on Box2D, removing the physics system alone leaves no joint to '
        'destroy twice', () {
      final (:world, :physics) = _setUp(gravityY: 0, joints: true);
      _box(world, extra: [FixedJoint2D(connectedBody: const EntityTarget.name('B'))]);
      _box(world, x: 30, name: 'B');
      _step(world);
      final joint = physics.joints.single as Box2DJoint;

      world.removeSystem(world.getSystem<PhysicsSystem>()!);
      _step(world); // the joint system finds its bodies gone
      expect(physics.joints, isEmpty);
      expect(joint.isDestroyed, isFalse);
    });

    test('on Box2D, removing the joint system alone destroys its joints', () {
      final (:world, :physics) = _setUp(gravityY: 0, joints: true);
      _box(world, extra: [FixedJoint2D(connectedBody: const EntityTarget.name('B'))]);
      _box(world, x: 30, name: 'B');
      _step(world);
      final joint = physics.joints.single as Box2DJoint;

      world.removeSystem(world.getSystem<PhysicsJointBindingSystem>()!);
      expect(physics.joints, isEmpty);
      expect(joint.isDestroyed, isTrue);
    });
  });

  group('checkpoints', () {
    test('a player-tagged entity with no transform is passed over', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(CheckpointSystem());
      // Tagged, but nowhere: a record, not a body.
      world.createEntityWithComponents([TagComponent(EngineTags.player)]);
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        TagComponent(EngineTags.player),
      ]);
      final checkpoint = CheckpointComponent(
        respawnPosition: Vector3(5, 0, 0),
        radius: 20,
      );
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(5, 0, 0)),
        checkpoint,
      ]);

      expect(() => world.update(_frame), returnsNormally);
      expect(checkpoint.isActivated, isTrue);
    });
  });
}
