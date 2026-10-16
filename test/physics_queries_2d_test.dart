// Rays and overlaps against 2-D bodies, answered in entities: layers,
// sensors and an entity to look through, as the 3-D queries take them.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late PhysicsEngine physics;
  late World world;
  late PhysicsSystem system;
  late Physics2DQueries queries;

  setUp(() {
    physics = PhysicsEngine()..initialize();
    physics.setGravity(0, 0);
    world = World()..initialize();
    world.addSystem(system = PhysicsSystem(physics));
    queries = Physics2DQueries(physics, system);
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity wall(String name, double x, {int layer = 0, bool sensor = false}) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(x, 0, 0)),
    RigidBody2D(bodyType: BodyType.static, layer: layer, isSensor: sensor),
    Collider2D(size: Vector2(10, 100)),
  ], name: name);

  test('a ray finds the nearest wall, and every wall in order', () {
    final near = wall('near', 50);
    final far = wall('far', 150);
    world.update(1 / 60);
    final hit = queries.raycast(Offset.zero, const Offset(1, 0), maxDistance: 500)!;
    expect(hit.entity, near);
    expect(hit.point.dx, closeTo(45, 1));
    expect(hit.normal.dx, closeTo(-1, 1e-6));
    expect(hit.fraction, closeTo(45 / 500, 0.01));
    expect([for (final h in queries.raycastAll(Offset.zero, const Offset(1, 0))) h.entity], [near, far]);
  });

  test('layers, sensors and the entity to look through', () {
    final near = wall('near', 50, layer: 1);
    final zone = wall('zone', 100, sensor: true);
    final far = wall('far', 150);
    world.update(1 / 60);
    expect(queries.raycast(Offset.zero, const Offset(1, 0), layerMask: 1)?.entity, far, reason: 'layer 1 is not looked for; the sensor is passed over');
    expect(queries.raycast(Offset.zero, const Offset(1, 0), layerMask: 1, includeSensors: true)?.entity, zone);
    expect(queries.raycast(Offset.zero, const Offset(1, 0), ignore: near)?.entity, far);
    expect(queries.overlapCircle(const Offset(50, 0), 10), [near]);
    expect(queries.overlapBox(const Rect.fromLTRB(0, -10, 200, 10)), unorderedEquals([near, far]));
    expect(queries.circleCast(Offset.zero, 5, const Offset(1, 0))?.entity, near);
  });
}
