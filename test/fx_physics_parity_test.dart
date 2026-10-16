// The 2-D physics backends agreeing where they did not: a wake reaches a
// sleeping native body, a wheel turns on its own axle, joint springs are
// hertz and a damping ratio on both, a slider's axis is in its entity's
// space, jointed bodies send no contact events, culling freezes a body,
// torque turns by a body's inertia, angles stay continuous, a kinematic body
// moved by its transform carries what it holds; and a capsule stretched by
// its entity, a ray along a box's side and the collider debugger.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _frame = 1 / 60;

final _backends = <String, PhysicsEngine Function()>{
  'native': PhysicsEngine.new,
  'pure Dart': PhysicsEngine.pureDart,
};

({World world, PhysicsEngine physics}) _setUp(
  PhysicsEngine engine, {
  double gravityY = 981,
  bool joints = false,
}) {
  final physics = engine..initialize();
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

void _step(World world, [int frames = 1, void Function(int)? each]) {
  for (var i = 0; i < frames; i++) {
    each?.call(i);
    world.update(_frame);
  }
}

PhysicsBody _bodyOf(Entity entity) =>
    entity.getComponent<PhysicsBodyRefComponent>()!.body;

TransformComponent _t(Entity e) => e.getComponent<TransformComponent>()!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MapEntry(key: name, value: make) in _backends.entries) {
    group('on $name', () {
      test('a body asleep wakes for a new gravity scale and wakeUp', () {
        final (:world, :physics) = _setUp(make());
        final rigid = RigidBody2D(gravityScale: 0, linearDamping: 0);
        final box = world.createEntityWithComponents([
          TransformComponent(),
          rigid,
          Collider2D(size: Vector2(20, 20)),
        ]);
        _step(world, 120);
        expect(_bodyOf(box).isAwake, isFalse, reason: 'asleep at rest');

        rigid.gravityScale = 1;
        _step(world, 30);
        expect(_t(box).position.y, greaterThan(50), reason: 'falls');

        rigid.gravityScale = 0;
        rigid.setVelocity(Offset.zero);
        _step(world, 120);
        expect(_bodyOf(box).isAwake, isFalse);
        rigid.wakeUp();
        _step(world, 1);
        expect(_bodyOf(box).isAwake, isTrue);
      });

      test('a wheel turns on its own axle, not round the chassis', () {
        final (:world, :physics) = _setUp(make(), gravityY: 0, joints: true);
        final chassis = world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2D(lockRotation: true, linearDamping: 0),
          Collider2D(size: Vector2(80, 20)),
          WheelJoint2D(connectedBody: const EntityTarget.name('Wheel')),
        ], name: 'Chassis');
        final wheel = world.createEntityWithComponents([
          TransformComponent(position: Vector3(30, 40, 0)),
          RigidBody2D(linearDamping: 0),
          Collider2D(shape: ColliderShape2D.circle, radius: 12),
        ], name: 'Wheel');
        _step(world, 90);
        final dx = _t(wheel).position.x - _t(chassis).position.x;
        final dy = _t(wheel).position.y - _t(chassis).position.y;
        expect(dx, closeTo(30, 4));
        expect(dy, closeTo(40, 8));
      });

      test('a distance spring in hertz settles as on Box2D', () {
        final (:world, :physics) = _setUp(make(), gravityY: 0, joints: true);
        world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2D(bodyType: BodyType.static),
          Collider2D(size: Vector2(10, 10)),
          DistanceJoint2D(connectedBody: const EntityTarget.name('Bob')),
        ], name: 'Pin');
        final bob = world.createEntityWithComponents([
          TransformComponent(position: Vector3(100, 0, 0)),
          RigidBody2D(linearDamping: 0, lockRotation: true),
          Collider2D(size: Vector2(10, 10)),
        ], name: 'Bob');
        _step(world, 20);
        expect(_t(bob).position.x, closeTo(48, 3));
        _step(world, 40);
        expect(_t(bob).position.x, closeTo(48, 2));
      });

      test('a slider slides along its axis turned with its entity', () {
        final (:world, :physics) = _setUp(make(), joints: true);
        world.createEntityWithComponents([
          TransformComponent(angle: math.pi / 2),
          RigidBody2D(bodyType: BodyType.static),
          Collider2D(size: Vector2(10, 10)),
          SliderJoint2D(connectedBody: const EntityTarget.name('Car')),
        ], name: 'Rail');
        final car = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 40, 0)),
          RigidBody2D(linearDamping: 0),
          Collider2D(size: Vector2(10, 10)),
        ], name: 'Car');
        _step(world, 30);
        expect(_t(car).position.y, greaterThan(100), reason: 'down the rail');
        expect(_t(car).position.x, closeTo(0, 1));
      });

      test('jointed bodies send no contact events between them', () {
        final (:world, :physics) = _setUp(make(), joints: true);
        var enters = 0, exits = 0;
        world.events
          ..on<CollisionEnter2DEvent>((_) => enters++)
          ..on<CollisionExit2DEvent>((_) => exits++);
        world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2D(bodyType: BodyType.static),
          Collider2D(size: Vector2(40, 40)),
          FixedJoint2D(connectedBody: const EntityTarget.name('Plate')),
        ], name: 'Base');
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(10, 10, 0)),
          RigidBody2D(),
          Collider2D(size: Vector2(40, 40)),
        ], name: 'Plate');
        // The first step finds them touching before the joint is made: that
        // contact ends as it is made, and no other begins.
        _step(world, 30);
        expect(enters, lessThanOrEqualTo(1));
        expect(exits, enters);
      });

      test('a culled body is frozen, and moves on once back', () {
        final (:world, :physics) = _setUp(make());
        final cull = CullStateComponent()..isActive = false;
        final box = world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2D(initialVelocity: const Offset(50, 0)),
          Collider2D(size: Vector2(20, 20)),
          cull,
        ]);
        _step(world, 30);
        expect(_t(box).position.x, closeTo(0, 1e-6));
        expect(_t(box).position.y, closeTo(0, 1e-6));
        expect(_bodyOf(box).position.y, closeTo(0, 1e-3));
        cull.isActive = true;
        _step(world, 30);
        expect(_t(box).position.y, greaterThan(50));
        expect(_t(box).position.x, greaterThan(10), reason: 'as it was');
      });

      test('torque and angular impulse turn by the body\'s inertia', () {
        final (:world, :physics) = _setUp(make(), gravityY: 0);
        final rigid = RigidBody2D(mass: 1, angularDamping: 0);
        world.createEntityWithComponents([
          TransformComponent(),
          rigid,
          Collider2D(size: Vector2(64, 64)),
        ]);
        _step(world);
        // A 64 Ã— 64 box of 1 kg: I = (64Â² + 64Â²) / 12.
        const inertia = (64 * 64 * 2) / 12;
        rigid.addAngularImpulse(10);
        _step(world);
        expect(rigid.angularVelocity, closeTo(10 / inertia, 0.003));
        rigid
          ..setAngularVelocity(0)
          ..addTorque(1000);
        _step(world);
        expect(rigid.angularVelocity, closeTo(1000 / inertia / 60, 0.006));
      });

      test('a spinning body\'s angle goes on round', () {
        final (:world, :physics) = _setUp(make(), gravityY: 0);
        final rigid = RigidBody2D(
          initialAngularVelocity: 12,
          angularDamping: 0,
          // The pure-Dart engine puts a body to sleep by its linear speed
          // alone.
          canSleep: false,
        );
        final box = world.createEntityWithComponents([
          TransformComponent(),
          rigid,
          Collider2D(size: Vector2(20, 20)),
        ]);
        var last = _t(box).angle;
        for (var i = 0; i < 60; i++) {
          world.update(_frame);
          final now = _t(box).angle;
          expect(now - last, inInclusiveRange(0, 1), reason: 'frame $i');
          last = now;
        }
        expect(last, greaterThan(2 * math.pi));
      });

      test('a platform moved by its transform carries what is on it', () {
        final (:world, :physics) = _setUp(make());
        final platform = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 300, 0)),
          RigidBody2D(bodyType: BodyType.kinematic, friction: 1),
          Collider2D(size: Vector2(400, 20)),
        ], name: 'Platform');
        final crate = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 280, 0)),
          RigidBody2D(friction: 1, lockRotation: true, restitution: 0),
          Collider2D(size: Vector2(20, 20)),
        ], name: 'Crate');
        _step(world, 30);
        final start = _t(crate).position.x;
        _step(world, 60, (_) => _t(platform).position.x += 2);
        expect(_t(platform).position.x, closeTo(120, 3));
        expect(_t(crate).position.x - start, greaterThan(60));
        expect(_bodyOf(platform).velocity.x, closeTo(120, 1));
        _step(world, 3);
        expect(_bodyOf(platform).velocity.x, 0, reason: 'stopped with it');
      });
    });
  }

  test('a capsule stretched by its entity keeps its caps', () {
    final collider = Collider2D(
      shape: ColliderShape2D.capsule,
      radius: 16,
      height: 64,
    );
    final stretched = ColliderGeometry.of(
      collider,
      TransformComponent(scale: Vector3(1, 2, 1)),
    )!;
    final viaOwnScale = ColliderGeometry.of(
      Collider2D(
        shape: ColliderShape2D.capsule,
        radius: 16,
        height: 64,
        scale: Vector2(1, 2),
      ),
    )!;
    expect(ColliderGeometry.boundsOf(stretched).height, closeTo(128, 1e-9));
    expect(
      ColliderGeometry.boundsOf(stretched).height,
      closeTo(ColliderGeometry.boundsOf(viaOwnScale).height, 1e-9),
    );
  });

  test('a ray along a box side hits its near end', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final rays = RaycastSystem();
    world.addSystem(rays);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(50, 0, 0)),
      RaycastColliderComponent(width: 20, height: 20),
    ]);
    final hit = rays.castRay(
      Ray(origin: const Offset(0, -10), direction: const Offset(1, 0)),
    )!;
    expect(hit.point.dx, closeTo(40, 1e-9));
    expect(
      rays.castRay(
        Ray(origin: const Offset(0, -11), direction: const Offset(1, 0)),
      ),
      isNull,
    );
  });

  test('the collider debugger draws every kind of shape', () {
    final physics = PhysicsEngine.pureDart()..initialize();
    final world = World()..initialize();
    addTearDown(() {
      world.dispose();
      physics.dispose();
    });
    world
      ..addSystem(PhysicsSystem(physics))
      ..addSystem(ColliderDebuggerSystem());
    for (final collider in [
      Collider2D(shape: ColliderShape2D.capsule),
      Collider2D(shape: ColliderShape2D.circle, offset: const Offset(10, 0)),
      Collider2D(
        shape: ColliderShape2D.chain,
        points: const [Offset(0, 0), Offset(10, 0), Offset(20, 5)],
      ),
    ]) {
      world.createEntityWithComponents([TransformComponent(), collider]);
    }
    world.createEntityWithComponents([
      TransformComponent(angle: 1),
      RaycastColliderComponent(width: 10, radius: 4),
    ]);
    world.update(_frame);
    final recorder = ui.PictureRecorder();
    world.render(ui.Canvas(recorder), const ui.Size(100, 100));
    recorder.endRecording().dispose();
  });
}
