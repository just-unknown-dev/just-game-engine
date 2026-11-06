// Turning a body's Sensor on or off, or giving it another shape, while the
// game runs. Both are fixed when a native Box2D body is made, so the change
// used to reach only the Dart side: a box switched from sensor to solid in
// the inspector kept letting everything through. A sensor's flag also
// outlived its body, so a later solid body could come out a sensor.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late Physics2DEngine physics;
  late World world;

  setUp(() {
    physics = PhysicsEngineFactory.create2D()..initialize();
    physics.setGravity(0, 2200);
    world = World()..initialize();
    world.addSystem(Physics2DSystem(physics));
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity box({required bool sensor}) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 0, 0)),
    RigidBody2DComponent(
      bodyType: Body2DType.static,
      isSensor: sensor,
      restitution: 0,
    ),
    Collider2DComponent(size: Vector2(200, 20)),
  ], name: 'box');

  Entity ball() => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -150, 0)),
    RigidBody2DComponent(restitution: 0),
    Collider2DComponent(shape: Collider2DShape.circle, radius: 10),
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
    b.getComponent<RigidBody2DComponent>()!.isSensor = false;
    final y = run(ball(), 90);
    // Resting on the box's top (-10) — not fallen through it.
    expect(y, closeTo(-20, 1));
  });

  test('a box made a sensor at runtime lets it through', () {
    final b = box(sensor: false);
    final ballEntity = ball();
    expect(run(ballEntity, 90), closeTo(-20, 1));
    b.getComponent<RigidBody2DComponent>()!.isSensor = true;
    expect(run(ballEntity, 60), greaterThan(100));
  });

  test('a new shape reaches the simulation', () {
    final b = box(sensor: false);
    final ballEntity = ball();
    expect(run(ballEntity, 90), closeTo(-20, 1));
    // Taller box, same centre: its top moves up from -10 to -30.
    b.getComponent<Collider2DComponent>()!.size = Vector2(200, 60);
    expect(run(ballEntity, 60), closeTo(-40, 1));
  });

  test(
    'locking a live body\'s rotation keeps the body and stops it turning',
    () {
      final spinner = world.createEntityWithComponents([
        TransformComponent(position: Vector3(500, 0, 0)),
        RigidBody2DComponent(
          gravityScale: 0,
          angularDamping: 0,
          initialAngularVelocity: 3,
        ),
        Collider2DComponent(size: Vector2(20, 20)),
      ], name: 'spinner');
      final transform = spinner.getComponent<TransformComponent>()!;
      run(spinner, 10);
      final body = spinner.getComponent<Physics2DBodyRefComponent>()!.body;
      expect(transform.angle, isNot(closeTo(0, 1e-3)), reason: 'it turns');

      spinner.getComponent<RigidBody2DComponent>()!.lockRotation = true;
      run(spinner, 2);
      expect(
        spinner.getComponent<Physics2DBodyRefComponent>()!.body,
        same(body),
        reason: 'not made again',
      );
      final locked = transform.angle;
      run(spinner, 30);
      expect(transform.angle, closeTo(locked, 1e-6));
    },
  );

  test('a solid body made after a sensor in a disposed world is solid', () {
    // A sensor in another world, gone before this one starts.
    final other = PhysicsEngineFactory.create2D()..initialize();
    other.addBody(
      Physics2DBody(
        position: Vector2(0, 0),
        shape: Rectangle2DShape(200, 20),
        mass: 0,
        bodyType: Body2DType.static,
        isSensor: true,
      ),
    );
    other.dispose();

    box(sensor: false);
    expect(run(ball(), 90), closeTo(-20, 1));
  });
}
