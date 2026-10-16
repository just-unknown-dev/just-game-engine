// Turning a body's Sensor on or off, or giving it another shape, while the
// game runs. Both are fixed when a native Box2D body is made, so the change
// used to reach only the Dart side: a box switched from sensor to solid in
// the inspector kept letting everything through. A sensor's flag also
// outlived its body, so a later solid body could come out a sensor.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late PhysicsEngine physics;
  late World world;

  setUp(() {
    physics = PhysicsEngine()..initialize();
    physics.setGravity(0, 2200);
    world = World()..initialize();
    world.addSystem(PhysicsSystem(physics));
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity box({required bool sensor}) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 0, 0)),
    RigidBody2D(bodyType: BodyType.static, isSensor: sensor, restitution: 0),
    Collider2D(size: Vector2(200, 20)),
  ], name: 'box');

  Entity ball() => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -150, 0)),
    RigidBody2D(restitution: 0),
    Collider2D(shape: ColliderShape2D.circle, radius: 10),
  ], name: 'ball');

  double run(Entity e, int frames) {
    for (var i = 0; i < frames; i++) {
      world.update(1 / 60);
    }
    return e.getComponent<TransformComponent>()!.position.y;
  }

  test('a box made solid at runtime catches what falls on it', () {
    final b = box(sensor: true);
    world.update(1 / 60);
    b.getComponent<RigidBody2D>()!.isSensor = false;
    final y = run(ball(), 90);
    // Resting on the box's top (-10) — not fallen through it.
    expect(y, closeTo(-20, 1));
  });

  test('a box made a sensor at runtime lets it through', () {
    final b = box(sensor: false);
    final ballEntity = ball();
    expect(run(ballEntity, 90), closeTo(-20, 1));
    b.getComponent<RigidBody2D>()!.isSensor = true;
    expect(run(ballEntity, 60), greaterThan(100));
  });

  test('a new shape reaches the simulation', () {
    final b = box(sensor: false);
    final ballEntity = ball();
    expect(run(ballEntity, 90), closeTo(-20, 1));
    // Taller box, same centre: its top moves up from -10 to -30.
    b.getComponent<Collider2D>()!.size = Vector2(200, 60);
    expect(run(ballEntity, 60), closeTo(-40, 1));
  });

  test('a solid body made after a sensor in a disposed world is solid', () {
    // A sensor in another world, gone before this one starts.
    final other = PhysicsEngine()..initialize();
    other.addBody(
      PhysicsBody(
        position: Vector2(0, 0),
        shape: RectangleShape(200, 20),
        mass: 0,
        bodyType: BodyType.static,
        isSensor: true,
      ),
    );
    other.dispose();

    box(sensor: false);
    expect(run(ball(), 90), closeTo(-20, 1));
  });
}
