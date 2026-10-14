// What PhysicsSystem3D itself costs with 500 bodies: the ECS side of a
// step (sync in, read back, events) on a backend that does almost nothing.
// Prints the number; fails only when something is badly wrong.

@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

void main() {
  test('500 bodies through PhysicsSystem3D', () {
    final physics = FakePhysicsWorld3D(
      PhysicsWorldSettings3D(gravity: Vector3(0, 0.5, 0)),
      collisions: false,
    );
    final world = World()..initialize();
    world.addSystem(PhysicsSystem3D(physics));
    addTearDown(() {
      world.dispose();
      physics.dispose();
    });
    for (var i = 0; i < 500; i++) {
      world.createEntityWithComponents([
        TransformComponent(
          position: Vector3((i % 25) * 2.0, -(i ~/ 25) * 2.0, 0),
        ),
        Collider3D(
          shape: i.isEven ? ColliderShape3D.box : ColliderShape3D.sphere,
        ),
        RigidBody3D(canSleep: false),
      ]);
    }
    for (var i = 0; i < 30; i++) {
      world.update(1 / 60);
    }
    const steps = 240;
    final watch = Stopwatch()..start();
    for (var i = 0; i < steps; i++) {
      world.update(1 / 60);
    }
    watch.stop();
    final ms = watch.elapsedMicroseconds / 1000 / steps;
    // ignore: avoid_print
    print(
      '3D physics perf, 500 bodies on the fake backend: ${ms.toStringAsFixed(3)} ms per update',
    );
    expect(physics.bodies, hasLength(500));
    expect(ms, lessThan(16));
  });
}
