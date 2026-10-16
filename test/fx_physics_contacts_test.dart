// PhysicsSystem's enter and exit events on both 2-D backends: a body made
// again (a changed scale or shape) sends no second enter, and an exit only
// when its new body no longer touches; tiny scale noise makes nothing again;
// a static sensor over static ground sees nothing; a chain's many shapes
// make one enter and one exit; an end and a begin in one update net out.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/ecs/systems/physics/contact_pairs.dart';

const _frame = 1 / 60;

final _backends = <String, PhysicsEngine Function()>{
  'native': PhysicsEngine.new,
  'pure Dart': PhysicsEngine.pureDart,
};

({World world, PhysicsEngine physics}) _setUp(PhysicsEngine engine) {
  final physics = engine..initialize();
  physics.setGravity(0, 981);
  final world = World()..initialize();
  world.addSystem(PhysicsSystem(physics));
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics);
}

/// A slab whose top is at y = 280.
Entity _ground(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(0, 300, 0)),
  Collider2D(size: Vector2(2000, 40)),
], name: 'Ground');

Entity _crate(World world, {double x = 0, double y = 260}) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      RigidBody2D(restitution: 0, lockRotation: true),
      Collider2D(size: Vector2(20, 20)),
    ], name: 'Crate');

/// A static sensor 100 wide round (0, 250).
Entity _zone(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(0, 250, 0)),
  RigidBody2D(bodyType: BodyType.static, isSensor: true),
  Collider2D(size: Vector2(100, 100)),
], name: 'Zone');

void _step(World world, [int frames = 1, void Function(int)? each]) {
  for (var i = 0; i < frames; i++) {
    each?.call(i);
    world.update(_frame);
  }
}

PhysicsBody _bodyOf(Entity entity) =>
    entity.getComponent<PhysicsBodyRefComponent>()!.body;

final class _Log {
  _Log(World world) {
    world.events
      ..on<SensorEnter2DEvent>((e) => sensorEnters.add(e.other.name))
      ..on<SensorExit2DEvent>((e) => sensorExits.add(e.other.name))
      ..on<CollisionEnter2DEvent>((e) => enters++)
      ..on<CollisionExit2DEvent>((e) => exits++);
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
      test('a sensor made again every frame sends no second enter', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        _crate(world);
        final zone = _zone(world);
        final log = _Log(world);
        _step(world, 60);
        expect(log.sensorEnters, ['Crate']);
        log.clear();

        final scale = zone.getComponent<TransformComponent>()!.scale;
        final first = _bodyOf(zone);
        _step(world, 30, (i) => scale.x = i.isEven ? 1.001 : 1.0);
        expect(_bodyOf(zone), isNot(same(first)), reason: 'made again');
        expect(log.sensorEnters, isEmpty);
        expect(log.sensorExits, isEmpty);
      });

      test('a crate made again on the ground sends no second enter', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        final crate = _crate(world);
        final log = _Log(world);
        _step(world, 60);
        expect(log.enters, 1);
        expect(crate.getComponent<RigidBody2D>()!.isGrounded, isTrue);
        log.clear();

        final scale = crate.getComponent<TransformComponent>()!.scale;
        _step(world, 30, (i) => scale.y = i.isEven ? 1.001 : 1.0);
        expect(log.enters, 0);
        expect(log.exits, 0);
        expect(crate.getComponent<RigidBody2D>()!.isGrounded, isTrue);
      });

      test('a sensor made again too small to hold the crate exits once', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        _crate(world, x: 40);
        final zone = _zone(world);
        final log = _Log(world);
        _step(world, 60);
        expect(log.sensorEnters, ['Crate']);
        log.clear();

        zone.getComponent<TransformComponent>()!.scale.x = 0.2;
        _step(world, 10);
        expect(log.sensorEnters, isEmpty);
        expect(log.sensorExits, ['Crate']);
      });

      test('a frame with no step leaves a body made again waiting', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        _crate(world);
        final zone = _zone(world);
        final log = _Log(world);
        _step(world, 60);
        log.clear();
        // 240 Hz: a step every fourth frame.
        final scale = zone.getComponent<TransformComponent>()!.scale;
        for (var i = 0; i < 40; i++) {
          scale.x = i.isEven ? 1.001 : 1.0;
          world.update(_frame / 4);
        }
        expect(log.sensorEnters, isEmpty);
        expect(log.sensorExits, isEmpty);
      });

      test('scale noise makes nothing again', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        final crate = _crate(world);
        _step(world, 5);
        final body = _bodyOf(crate);
        final scale = crate.getComponent<TransformComponent>()!.scale;
        _step(world, 10, (i) => scale.x = 1 + (i.isEven ? 1e-6 : -1e-6));
        expect(_bodyOf(crate), same(body));
        // A real change does.
        scale.x = 1.5;
        _step(world);
        expect(_bodyOf(crate), isNot(same(body)));
      });

      test('a static sensor over static ground sees nothing of it', () {
        final (:world, :physics) = _setUp(make());
        _ground(world);
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(300, 280, 0)),
          RigidBody2D(bodyType: BodyType.static, isSensor: true),
          Collider2D(size: Vector2(100, 100)),
        ], name: 'Low zone');
        final log = _Log(world);
        _step(world, 10);
        expect(log.sensorEnters, isEmpty);
      });

      for (final thickness in [0.0, 2.0]) {
        test('a chain of many segments, $thickness thick, is one pair', () {
          final (:world, :physics) = _setUp(make());
          world.createEntityWithComponents([
            TransformComponent(position: Vector3(0, 280, 0)),
            Collider2D(
              shape: ColliderShape2D.chain,
              thickness: thickness,
              points: [
                for (var i = 0; i <= 40; i++) Offset(-200 + i * 10.0, 0),
              ],
            ),
          ], name: 'Chain');
          final crate = world.createEntityWithComponents([
            TransformComponent(position: Vector3(-150, 260, 0)),
            RigidBody2D(restitution: 0, friction: 0, lockRotation: true),
            Collider2D(size: Vector2(40, 20)),
          ], name: 'Crate');
          final log = _Log(world);
          final rigid = crate.getComponent<RigidBody2D>()!;
          _step(world, 30);
          // Slides across the segments (a 2-thick chain's rounded joins
          // can bump it off them for a moment: a real exit and enter).
          _step(world, 60, (_) => rigid.setVelocity(const Offset(200, 0)));
          if (thickness == 0) expect(log.enters, 1);
          expect(log.exits, log.enters - 1);
          crate.getComponent<TransformComponent>()!.position.y = -3000;
          rigid.setVelocity(Offset.zero);
          _step(world, 3);
          expect(log.exits, log.enters);
          expect(rigid.isGrounded, isFalse, reason: 'in the air');
        });
      }
    });
  }

  group('ContactPairs', () {
    Entity entity(World world, String name) =>
        world.createEntityWithComponents([TransformComponent()], name: name);

    test('an end and a begin in one update net out', () {
      final world = World()..initialize();
      final a = entity(world, 'a'), b = entity(world, 'b');
      final pairs = ContactPairs<int>();
      expect(pairs.begin(1, 2, a, b, sensor: false)!.enters, isTrue);
      // The next update ran two steps: they parted, then touched again.
      // Begins are read first.
      expect(pairs.begin(2, 1, b, a, sensor: false), isNull);
      expect(pairs.end(1, 2, sensor: false), isNull);
      expect(pairs.entityPairCount, 1);
      final last = pairs.end(1, 2, sensor: false)!;
      expect(last.exits, isTrue);
      expect(pairs.isEmpty, isTrue);
    });

    test('a body made again waits for the next step', () {
      final world = World()..initialize();
      final a = entity(world, 'a'), b = entity(world, 'b');
      final pairs = ContactPairs<int>()..begin(1, 2, a, b, sensor: true);
      pairs.removeBody(1, rebuilt: true);
      expect(pairs.begin(3, 2, a, b, sensor: true)!.enters, isFalse);
      expect(pairs.settle(), isEmpty, reason: 'found again');
      pairs.removeBody(3, rebuilt: true);
      final parted = pairs.settle();
      expect(parted.single.a, a);
      expect(parted.single.sensor, isTrue);
      expect(pairs.entityPairCount, 0);
    });

    test('a body gone for good ends its pairs with no exit', () {
      final world = World()..initialize();
      final a = entity(world, 'a'), b = entity(world, 'b');
      final pairs = ContactPairs<int>()..begin(1, 2, a, b, sensor: false);
      pairs.removeBody(1, rebuilt: true);
      pairs.removeBody(2, rebuilt: false, entity: b);
      expect(pairs.settle(), isEmpty);
      expect(pairs.entityPairCount, 0);
    });
  });
}
