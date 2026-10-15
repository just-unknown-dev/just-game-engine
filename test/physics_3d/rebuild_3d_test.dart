// PhysicsSystem3D when a body is made again (a changed scale or collider):
// no second enter and no lost exit, on the fake backend and on Jolt; scale
// noise makes nothing again; joints made again hold where they held; a body
// refused for its layer is tried again once the layer is fixed; collider
// shapes are kept within limits and a reloaded model's colliders take its
// new triangles.

@Tags(['physics3d'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

const _dt = 1 / 60;

final _backends = <String, PhysicsWorld3D Function()>{
  'fake': () => FakePhysicsWorld3D(PhysicsWorldSettings3D()),
  'Jolt': () => JoltPhysicsEngine().createWorld(PhysicsWorldSettings3D()),
};

({World world, PhysicsWorld3D physics, PhysicsSystem3D system}) _setUp(
  PhysicsWorld3D physics, {
  ColliderGeometry3D? geometry,
}) {
  final system = PhysicsSystem3D(physics, geometry: geometry);
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

Entity _crate(World world, {double x = 0}) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(x, -0.6, 0)),
  Collider3D(),
  RigidBody3D(canSleep: false),
], name: 'Crate');

/// A static sensor 4 m wide round (0, -1, 0).
Entity _zone(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(0, -1, 0)),
  Collider3D(size: Vector3(4, 2, 4)),
  RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
], name: 'Zone');

void _run(World world, int frames, [void Function(int frame)? each]) {
  for (var i = 0; i < frames; i++) {
    each?.call(i);
    world.update(_dt);
  }
}

final class _Log {
  _Log(World world) {
    world.events
      ..on<SensorEnter3DEvent>((e) => sensorEnters.add(e.other.name))
      ..on<SensorExit3DEvent>((e) => sensorExits.add(e.other.name))
      ..on<CollisionEnter3DEvent>((_) => enters++)
      ..on<CollisionExit3DEvent>((_) => exits++);
  }

  final List<String?> sensorEnters = [], sensorExits = [];
  int enters = 0, exits = 0;

  void clear() {
    sensorEnters.clear();
    sensorExits.clear();
    enters = exits = 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MapEntry(key: name, value: make) in _backends.entries) {
    group('on $name', () {
      test('a sensor made again every step sends no second enter', () {
        final (:world, :physics, :system) = _setUp(make());
        _floor(world);
        _crate(world);
        final zone = _zone(world);
        final log = _Log(world);
        _run(world, 30);
        expect(log.sensorEnters, ['Crate']);
        log.clear();

        final scale = zone.getComponent<TransformComponent>()!.scale;
        final first = system.bodyOf(zone);
        _run(world, 30, (i) => scale.x = i.isEven ? 1.001 : 1.0);
        expect(system.bodyOf(zone), isNot(first), reason: 'made again');
        expect(log.sensorEnters, isEmpty);
        expect(log.sensorExits, isEmpty);
      });

      test('a crate made again on the floor sends no second enter', () {
        final (:world, :physics, :system) = _setUp(make());
        _floor(world);
        final crate = _crate(world);
        final log = _Log(world);
        _run(world, 30);
        expect(log.enters, 1);
        log.clear();
        final scale = crate.getComponent<TransformComponent>()!.scale;
        _run(world, 30, (i) => scale.x = i.isEven ? 1.001 : 1.0);
        expect(log.enters, 0);
        expect(log.exits, 0);
      });

      test('a sensor made again too small to hold the crate exits once', () {
        final (:world, :physics, :system) = _setUp(make());
        _floor(world);
        _crate(world, x: 1.5);
        final zone = _zone(world);
        final log = _Log(world);
        _run(world, 30);
        expect(log.sensorEnters, ['Crate']);
        log.clear();
        zone.getComponent<TransformComponent>()!.scale.x = 0.2;
        _run(world, 5);
        expect(log.sensorEnters, isEmpty);
        expect(log.sensorExits, ['Crate']);
      });

      test('scale noise makes nothing again', () {
        final (:world, :physics, :system) = _setUp(make());
        _floor(world);
        final crate = _crate(world);
        _run(world, 5);
        final body = system.bodyOf(crate);
        final scale = crate.getComponent<TransformComponent>()!.scale;
        _run(world, 10, (i) => scale.y = 1 + (i.isEven ? 1e-6 : -1e-6));
        expect(system.bodyOf(crate), body);
        scale.y = 1.5;
        _run(world, 1);
        expect(system.bodyOf(crate), isNot(body));
      });
    });
  }

  group('on the fake backend', () {
    test('a joint made again with a body holds it where it held it', () {
      final physics = FakePhysicsWorld3D(PhysicsWorldSettings3D());
      final (:world, physics: _, :system) = _setUp(physics);
      final frame = world.createEntityWithComponents([
        TransformComponent(position: Vector3.zero()),
        Collider3D(),
        RigidBody3D(bodyType: BodyType3D.kinematic),
      ], name: 'Frame');
      final door = world.createEntityWithComponents([
        TransformComponent(position: Vector3(1, 0, 0)),
        Collider3D(),
        RigidBody3D(bodyType: BodyType3D.kinematic),
        PointJoint3D(
          connectedBody: const EntityTarget.name('Frame'),
          anchor: Vector3(-0.5, 0, 0),
        ),
      ], name: 'Door');
      _run(world, 1);
      final joint = physics.joints.values.single;
      expect(joint.settings.pointB.x, closeTo(0.5, 1e-9));

      // Noise: the joint is left as it is.
      final scale = frame.getComponent<TransformComponent>()!.scale;
      scale.x = 1 + 1e-7;
      _run(world, 1);
      expect(physics.joints.values.single, same(joint));

      // The frame moves away, then is made again (a new scale): the joint
      // still holds it half a metre right of its centre, not where the
      // door's anchor now is.
      frame.getComponent<TransformComponent>()!.position.setValues(0, 1, 0);
      _run(world, 1);
      scale.x = 1.5;
      _run(world, 1);
      final again = physics.joints.values.single;
      expect(again, isNot(same(joint)));
      expect(again.bodyB, system.bodyOf(frame));
      expect(again.settings.pointB.x, closeTo(0.5, 1e-6));
      expect(again.settings.pointB.y, closeTo(1, 1e-6));
      expect(again.settings.pointA.x, closeTo(0.5, 1e-6));
      expect(again.settings.pointA.y, closeTo(0, 1e-6));
      expect(door.getComponent<PointJoint3D>()!.joint, again.handle);
    });

    test('a body refused for its layer is made once the layer is fixed', () {
      final (:world, :physics, :system) = _setUp(
        FakePhysicsWorld3D(PhysicsWorldSettings3D()),
      );
      final rigid = RigidBody3D(layer: 20);
      final box = world.createEntityWithComponents([
        TransformComponent(),
        Collider3D(),
        rigid,
      ]);
      _run(world, 2);
      expect(system.bodyOf(box), 0);
      rigid.layer = 3;
      _run(world, 1);
      expect(system.bodyOf(box), isNot(0));
    });

    test('a reloaded model gives its colliders its new triangles', () {
      final geometry = _Geometry();
      final physics = FakePhysicsWorld3D(PhysicsWorldSettings3D());
      final (:world, physics: _, :system) = _setUp(
        physics,
        geometry: geometry,
      );
      _crate(world);
      final ground = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0.5, 0)),
        Collider3D(shape: ColliderShape3D.mesh, model: 'ground.glb'),
      ], name: 'Ground');
      final log = _Log(world);
      _run(world, 2);
      final first = system.bodyOf(ground);
      final shape = physics.bodies[first]!.shape as MeshShape3D;
      expect(shape.positions[3], 10);

      // Loading again: the old shape meanwhile.
      geometry.ready = false;
      system.reloadModel('ground.glb');
      _run(world, 3);
      expect(system.bodyOf(ground), first);

      geometry
        ..ready = true
        ..size = 20;
      _run(world, 2);
      final now = system.bodyOf(ground);
      expect(now, isNot(first));
      expect((physics.bodies[now]!.shape as MeshShape3D).positions[3], 20);
      expect(log.exits, 0);
    });
  });

  test('collider shapes are kept within their limits', () {
    final shapes = ColliderShapes3D(geometry: _Geometry());
    final mesh = Collider3D(shape: ColliderShape3D.mesh, model: 'a.glb');
    final first = shapes.build(mesh, Vector3(1, 1, 1));
    for (var i = 0; i < ColliderShapes3D.modelLimit * 2; i++) {
      shapes.build(mesh, Vector3(1, 1, 1));
      shapes.build(mesh, Vector3(2 + i.toDouble(), 1, 1));
    }
    expect(shapes.length, ColliderShapes3D.modelLimit);
    expect(
      shapes.build(mesh, Vector3(1, 1, 1)),
      same(first),
      reason: 'used all along: the least recently used went instead',
    );
    shapes.forgetModel('a.glb');
    expect(shapes.length, 0);
  });
}

final class _Geometry implements ColliderGeometry3D {
  bool ready = true;
  double size = 10;

  @override
  ModelGeometry? geometryOf(String model, String meshName) => ready
      ? ModelGeometry(
          Float32List.fromList([-size, 0, -size, size, 0, -size, 0, 0, size]),
          Uint32List.fromList([0, 1, 2]),
        )
      : null;
}
