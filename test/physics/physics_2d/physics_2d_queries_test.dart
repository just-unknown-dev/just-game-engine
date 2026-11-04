// Rays and overlaps against 2-D bodies, answered in entities: layers,
// sensors and an entity to look through, as the 3-D queries take them.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late Physics2DEngine physics;
  late World world;
  late Physics2DSystem system;
  late Physics2DQueries queries;

  setUp(() {
    physics = Physics2DEngine()..initialize();
    physics.setGravity(0, 0);
    world = World()..initialize();
    world.addSystem(system = Physics2DSystem(physics));
    queries = system.queries;
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity wall(String name, double x, {int layer = 0, bool sensor = false}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
        RigidBody2DComponent(
          bodyType: Body2DType.static,
          layer: layer,
          isSensor: sensor,
        ),
        Collider2DComponent(size: Vector2(10, 100)),
      ], name: name);

  test('a ray finds the nearest wall, and every wall in order', () {
    final near = wall('near', 50);
    final far = wall('far', 150);
    world.update(1 / 60);
    final hit = queries.raycast(
      Offset.zero,
      const Offset(1, 0),
      maxDistance: 500,
    )!;
    expect(hit.entity, near);
    expect(hit.point.dx, closeTo(45, 1));
    expect(hit.normal.dx, closeTo(-1, 1e-6));
    expect(hit.fraction, closeTo(45 / 500, 0.01));
    expect(
      [
        for (final h in queries.raycastAll(Offset.zero, const Offset(1, 0)))
          h.entity,
      ],
      [near, far],
    );
  });

  test('layers, sensors and the entity to look through', () {
    final near = wall('near', 50, layer: 1);
    final zone = wall('zone', 100, sensor: true);
    final far = wall('far', 150);
    world.update(1 / 60);
    expect(
      queries.raycast(Offset.zero, const Offset(1, 0), layerMask: 1)?.entity,
      far,
      reason: 'layer 1 is not looked for; the sensor is passed over',
    );
    expect(
      queries
          .raycast(
            Offset.zero,
            const Offset(1, 0),
            layerMask: 1,
            includeSensors: true,
          )
          ?.entity,
      zone,
    );
    expect(
      queries.raycast(Offset.zero, const Offset(1, 0), ignore: near)?.entity,
      far,
    );
    expect(queries.overlapCircle(const Offset(50, 0), 10), [near]);
    expect(
      queries.overlapBox(const Rect.fromLTRB(0, -10, 200, 10)),
      unorderedEquals([near, far]),
    );
    expect(
      queries.circleCast(Offset.zero, 5, const Offset(1, 0))?.entity,
      near,
    );
  });

  test('a box overlaps shapes, not the boxes round them', () {
    final ball = world.createEntityWithComponents([
      TransformComponent(),
      RigidBody2DComponent(bodyType: Body2DType.static),
      Collider2DComponent(shape: Collider2DShape.circle, radius: 50),
    ], name: 'ball');
    world.update(1 / 60);
    // Inside the ball's bounds, but past its curve: ~6.6 off it.
    expect(queries.overlapBox(const Rect.fromLTRB(40, 40, 50, 50)), isEmpty);
    expect(queries.overlapBox(const Rect.fromLTRB(30, 30, 40, 40)), [ball]);
    expect(queries.overlapBox(const Rect.fromLTRB(-5, -5, 5, 5)), [ball]);
  });
}
