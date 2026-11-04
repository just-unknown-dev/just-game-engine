// Physics2DSystem keeping bodies and transforms in step, on both backends:
// a kinematic body moved by its transform keeps every move on updates that
// run no step; a body made again keeps its PhysicsBodyRefComponent (and the
// world's structure); a joint holds from the very step its bodies are made
// in, and through a body made again every frame.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _backends = <String, PhysicsEngine Function()>{
  'native': PhysicsEngine.new,
  'pure Dart': PhysicsEngine.pureDart,
};

({World world, PhysicsEngine physics}) _setUp(
  PhysicsEngine engine, {
  double gravityY = 0,
}) {
  final physics = engine..initialize();
  physics.setGravity(0, gravityY);
  final world = World()..initialize();
  world.addSystem(Physics2DSystem(physics));
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics);
}

TransformComponent _t(Entity e) => e.getComponent<TransformComponent>()!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MapEntry(key: name, value: make) in _backends.entries) {
    group('on $name', () {
      test('a kinematic body moved bit by bit keeps every move at half the '
          'step rate', () {
        // Slow motion: the loop's updates are half a physics step long, so
        // every other update runs no step.
        final (:world, :physics) = _setUp(make());
        final platform = world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2DComponent(bodyType: BodyType.kinematic),
          Collider2DComponent(size: Vector2(40, 10)),
        ]);
        final t = _t(platform);
        world.update(1 / 120);
        for (var i = 0; i < 60; i++) {
          t.position.x += 2; // MoveEffect's way: a delta each tick.
          world.update(1 / 120);
          expect(t.position.x, closeTo(2.0 * (i + 1), 1e-6), reason: 'tick $i');
        }
        // Left alone, the body gets there too and stops.
        for (var i = 0; i < 6; i++) {
          world.update(1 / 120);
        }
        final body = platform.getComponent<PhysicsBodyRefComponent>()!.body;
        expect(body.position.x, closeTo(120, 1e-3));
        expect(t.position.x, closeTo(120, 1e-3));
      });

      test('a body made again keeps its ref component and the structure', () {
        final (:world, :physics) = _setUp(make());
        final ball = world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2DComponent(),
          Collider2DComponent(shape: Collider2DShape.circle, radius: 4),
        ]);
        world.update(1 / 60);
        final ref = ball.getComponent<PhysicsBodyRefComponent>()!;
        final first = ref.body;
        final version = world.queryVersion(const [PhysicsBodyRefComponent]);

        _t(ball).scale.setValues(1.5, 1.5, 1);
        world.update(1 / 60);
        expect(ball.getComponent<PhysicsBodyRefComponent>(), same(ref));
        expect(ref.body, isNot(same(first)), reason: 'a new body');
        expect((ref.body.shape as CircleShape).radius, closeTo(6, 1e-9));
        expect(
          world.queryVersion(const [PhysicsBodyRefComponent]),
          version,
          reason: 'no entity changed archetype',
        );
        expect(physics.bodyCount, 1);
      });

      test('a body made again into no shape loses its ref component', () {
        final (:world, :physics) = _setUp(make());
        final collider = Collider2DComponent(
          shape: Collider2DShape.polygon,
          points: const [Offset(0, 0), Offset(10, 0), Offset(0, 10)],
        );
        final e = world.createEntityWithComponents([
          TransformComponent(),
          collider,
        ]);
        world.update(1 / 60);
        expect(e.hasComponent<PhysicsBodyRefComponent>(), isTrue);
        collider.points = const [Offset(0, 0), Offset(10, 0)];
        world.update(1 / 60);
        expect(e.hasComponent<PhysicsBodyRefComponent>(), isFalse);
        expect(physics.bodyCount, 0);
      });

      test('a weld holds from the step its bodies are made in', () {
        final (:world, :physics) = _setUp(make(), gravityY: 981);
        world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2DComponent(bodyType: BodyType.static),
          Collider2DComponent(size: Vector2(10, 10)),
          FixedJoint2DComponent(connectedBody: const EntityTarget.name('B')),
        ], name: 'A');
        final b = world.createEntityWithComponents([
          TransformComponent(position: Vector3(30, 0, 0)),
          RigidBody2DComponent(lockRotation: true),
          Collider2DComponent(size: Vector2(10, 10)),
        ], name: 'B');
        world.update(1 / 60);
        // Falling freely for that first step would be 981 / 60² ≈ 0.27; held,
        // it sags less than that while the joint takes the load.
        expect(_t(b).position.y.abs(), lessThan(0.2));
      });

      test('a weld made again every frame does not slide off', () {
        final (:world, :physics) = _setUp(make(), gravityY: 981);
        world.createEntityWithComponents([
          TransformComponent(),
          RigidBody2DComponent(bodyType: BodyType.static),
          Collider2DComponent(size: Vector2(10, 10)),
          FixedJoint2DComponent(connectedBody: const EntityTarget.name('B')),
        ], name: 'A');
        final b = world.createEntityWithComponents([
          TransformComponent(position: Vector3(30, 0, 0)),
          RigidBody2DComponent(lockRotation: true),
          Collider2DComponent(size: Vector2(10, 10)),
        ], name: 'B');
        for (var i = 0; i < 60; i++) {
          // A squash and stretch: its body is made again each frame.
          final s = i.isEven ? 1.0 : 1.2;
          _t(b).scale.setValues(s, s, 1);
          world.update(1 / 60);
        }
        expect(_t(b).position.y.abs(), lessThan(2));
        expect(_t(b).position.x, closeTo(30, 2));
      });
    });
  }

  test('the system answers queries of its own bodies', () {
    final (:world, :physics) = _setUp(PhysicsEngine.pureDart());
    final system = world.getSystem<Physics2DSystem>()!;
    expect(system.queries, same(system.queries));
    expect(system.queries.physics, same(physics));
  });
}
