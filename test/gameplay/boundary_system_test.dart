// BoundarySystem: one test per behaviour — clamp, bounce, wrap, destroy.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  const bounds = Rect.fromLTRB(0, 0, 100, 50);

  World worldWith(BoundaryBehavior behavior) {
    world = World()..initialize();
    world.addSystem(BoundarySystem(bounds: bounds, behavior: behavior));
    return world;
  }

  tearDown(() => world.dispose());

  Vector3 at(Entity e) => e.getComponent<TransformComponent>()!.position;

  test('clamp holds an entity at the edge', () {
    worldWith(BoundaryBehavior.clamp);
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(120, -10, 0)),
    ]);
    world.update(1 / 60);
    expect([at(e).x, at(e).y], [100, 0]);
  });

  test('bounce reverses only the crossed axis', () {
    worldWith(BoundaryBehavior.bounce);
    final velocity = VelocityComponent(velocity: Vector3(30, 20, 0));
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(105, 25, 0)),
      velocity,
    ]);
    world.update(1 / 60);
    expect([at(e).x, at(e).y], [100, 25]);
    expect([velocity.velocity.x, velocity.velocity.y], [-30, 20]);
  });

  test('bounce leaves an entity without velocity alone', () {
    worldWith(BoundaryBehavior.bounce);
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(105, 60, 0)),
    ]);
    world.update(1 / 60);
    expect([at(e).x, at(e).y], [105, 60]);
  });

  test('wrap sends an entity past one edge to the other', () {
    worldWith(BoundaryBehavior.wrap);
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(-1, 51, 0)),
    ]);
    world.update(1 / 60);
    expect([at(e).x, at(e).y], [100, 0]);
  });

  test('destroy removes an entity outside, once commands flush', () {
    worldWith(BoundaryBehavior.destroy);
    final outside = world.createEntityWithComponents([
      TransformComponent(position: Vector3(200, 10, 0)),
    ]);
    final inside = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 10, 0)),
    ]);
    world.update(1 / 60);
    expect(outside.isAlive, isFalse);
    expect(inside.isAlive, isTrue);
  });
}
