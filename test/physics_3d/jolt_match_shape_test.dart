// Colliders matching their entity's shape on Jolt: a compound of boxes and
// a ring of hulls made as one static compound shape, falling, resting and
// hit by rays like any other body.

@Tags(['physics3d'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

const _dt = 1 / 60;
final _backend = JoltPhysicsEngine();

/// Three 1 m boxes in a row along Z, the middle one at the origin.
class _Row extends Component implements SolidShapeSource {
  @override
  Object get solidKey => 'row';

  @override
  List<SolidPart> get solidParts => [
    for (var i = -1; i <= 1; i++) SolidBox(0.5, 0.5, 0.5, z: i.toDouble()),
  ];
}

/// A ring lying flat: [pieces] hulls of a tube of radius 0.2 round a
/// circle of radius 1.
class _Ring extends Component implements SolidShapeSource {
  static const int pieces = 12;

  @override
  Object get solidKey => 'ring';

  @override
  List<SolidPart> get solidParts => [
    for (var i = 0; i < pieces; i++)
      SolidHull(
        Float32List.fromList([
          for (final step in [i, i + 1])
            for (var k = 0; k < 8; k++) ...[
              (1 + 0.2 * math.cos(2 * math.pi * k / 8)) * math.cos(2 * math.pi * step / pieces),
              -0.2 * math.sin(2 * math.pi * k / 8),
              (1 + 0.2 * math.cos(2 * math.pi * k / 8)) * math.sin(2 * math.pi * step / pieces),
            ],
        ]),
      ),
  ];
}

void main() {
  late World world;
  late PhysicsWorld3D physics;
  late PhysicsSystem3D system;

  setUp(() {
    physics = _backend.createWorld(PhysicsWorldSettings3D());
    world = World()..initialize();
    world.addSystem(system = PhysicsSystem3D(physics));
    // A floor whose top is at y = 0 (+Y is down).
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0.5, 0)),
      Collider3D(size: Vector3(20, 1, 20)),
    ]);
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  void run(int frames) {
    for (var i = 0; i < frames; i++) {
      world.update(_dt);
    }
  }

  test('a row of boxes falls as one body and rests flat', () {
    final row = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -3, 0)),
      _Row(),
      Collider3D(shape: ColliderShape3D.matchShape),
      RigidBody3D(),
    ]);
    run(240);
    final t = row.getComponent<TransformComponent>()!;
    expect(t.position.y, closeTo(-0.5, 0.03));
    expect(t.position.z, closeTo(0, 0.05), reason: 'it landed level and stayed');
  });

  test('a ring of hulls lies on the floor, and a ray through its hole misses it', () {
    final ring = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -2, 0)),
      _Ring(),
      Collider3D(shape: ColliderShape3D.matchShape),
      RigidBody3D(),
    ]);
    run(300);
    final t = ring.getComponent<TransformComponent>()!;
    expect(t.position.y, closeTo(-0.2, 0.04), reason: 'its tube is 0.2 m thick each way');
    final queries = Physics3DQueries(system);
    final rim = queries.raycast(Vector3(t.position.x + 1, -5, t.position.z), Vector3(0, 1, 0), maxDistance: 10);
    expect(rim?.entity, ring, reason: 'its rim is hit');
    final hole = queries.raycast(Vector3(t.position.x, -5, t.position.z), Vector3(0, 1, 0), maxDistance: 10);
    expect(hole?.entity, isNot(ring), reason: 'its hole is empty');
  });
}
