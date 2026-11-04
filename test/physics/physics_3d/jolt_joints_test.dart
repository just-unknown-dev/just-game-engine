// The 3-D joints on Jolt that the other tests leave out: a distance joint
// keeps its bodies within its range, a six-axis joint with every axis fixed
// holds its body still, and a joint whose other body is its own entity's
// makes no joint at all (Jolt itself would join a body to itself).

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

const _dt = 1 / 60;
final _backend = JoltPhysicsEngine();

World _world() {
  final physics = _backend.createWorld(PhysicsWorldSettings3D());
  final world = World()..initialize();
  world.addSystem(Physics3DSystem(physics));
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return world;
}

Entity _anchor(World world, List<Component> joint) =>
    world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(size: Vector3(0.5, 0.5, 0.5)),
      ...joint,
    ], name: 'Anchor');

Entity _weight(World world, Vector3 at) => world.createEntityWithComponents([
  TransformComponent(position: at),
  Collider3DComponent(size: Vector3(0.5, 0.5, 0.5)),
  RigidBody3DComponent(canSleep: false),
], name: 'Weight');

void _run(World world, int frames) {
  for (var i = 0; i < frames; i++) {
    world.update(_dt);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a distance joint keeps its bodies within its range', () {
    final world = _world();
    final joint = DistanceJoint3DComponent(
      connectedBody: const EntityTarget.name('Weight'),
      minDistance: 0,
      maxDistance: 2,
    );
    _anchor(world, [joint]);
    final weight = _weight(world, Vector3(1, 0, 0));
    final t = weight.getComponent<TransformComponent>()!;
    for (var i = 0; i < 120; i++) {
      world.update(_dt);
      expect(t.position.length, lessThan(2.1), reason: 'step $i');
    }
    expect(joint.joint, isNot(0));
    expect(t.position.y, greaterThan(1), reason: 'it swung down');
  });

  test('a six-axis joint with every axis fixed holds its body still', () {
    final world = _world();
    final joint = SixDofJoint3DComponent(
      connectedBody: const EntityTarget.name('Weight'),
    );
    _anchor(world, [joint]);
    final weight = _weight(world, Vector3(1, 0, 0));
    _run(world, 120);
    expect(joint.joint, isNot(0));
    final t = weight.getComponent<TransformComponent>()!;
    expect(t.position.x, closeTo(1, 0.05));
    expect(t.position.y, closeTo(0, 0.05), reason: 'not fallen');
  });

  test('a joint to its own entity makes no joint', () {
    final world = _world();
    final hinge = HingeJoint3DComponent(
      connectedBody: const EntityTarget.self(),
    );
    world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(),
      RigidBody3DComponent(),
      hinge,
    ]);
    _run(world, 2);
    expect(hinge.joint, 0);
  });
}
