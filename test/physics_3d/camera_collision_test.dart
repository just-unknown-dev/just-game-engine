// A camera kept out of walls: pulled in front of one between it and its
// target, eased back out once the wall goes, its target's own body never
// in the way.
@Tags(['physics3d'])
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late CameraBrain brain;
  late Entity camera;

  setUp(() {
    final physics = FakePhysicsWorld3D(PhysicsWorldSettings3D());
    world = World()..initialize();
    world.addSystem(PhysicsSystem3D(physics));
    addTearDown(() {
      world.dispose();
      physics.dispose();
    });
    world.createEntityWithComponents([
      TransformComponent(position: Vector3.zero()),
      Collider3D(shape: ColliderShape3D.capsule, radius: 0.3, height: 1.8),
      RigidBody3D(bodyType: BodyType3D.kinematic),
    ], name: 'Player');
    camera = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -3, -8)),
      VirtualCameraComponent(
        follow: const EntityTarget.name('Player'),
        projection: CameraProjection.perspective,
      ),
      OrbitFollowComponent(distance: 8, pitch: 0, yaw: 0, pivot: Vector3(0, -1.5, 0)),
      CameraCollision3D(radius: 0.2, recover: 0.5),
    ], name: 'Cam');
    brain = CameraBrain(Camera(position: Offset.zero, viewportSize: const Size(800, 600)));
    brain.stages.register(const CameraCollisionStage());
  });

  double cameraZ({double dt = 1 / 60, bool snap = false}) {
    world.update(1 / 60);
    brain.evaluate(world, dt, snap: snap);
    return brain.stateOf(camera)!.z;
  }

  test('clear, the camera stays where the orbit puts it', () {
    expect(cameraZ(snap: true), closeTo(-8, 1e-6));
  });

  test('a wall between pulls it in front of the wall, and it eases back out', () {
    final wall = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -1.5, -4)),
      Collider3D(size: Vector3(6, 6, 0.5)),
    ], name: 'Wall');
    final z = cameraZ(snap: true);
    expect(z, greaterThan(-3.75), reason: 'in front of the wall face at -3.75');
    expect(z, lessThan(-3), reason: 'but not on top of the player');

    world.destroyEntity(wall);
    final first = cameraZ();
    expect(first, lessThan(z), reason: 'moving back out');
    expect(first, greaterThan(-8), reason: 'gently, not at once');
    var last = first;
    for (var i = 0; i < 120; i++) {
      last = cameraZ();
    }
    expect(last, closeTo(-8, 0.01));
  });

  test("its target's own body is not in the way", () {
    // The orbit circles a point inside the player's capsule.
    camera.getComponent<OrbitFollowComponent>()!.pivot.setValues(0, -0.9, 0);
    expect(cameraZ(snap: true), closeTo(-8, 1e-6));
  });

  test('registered for every brain of an engine by the extension', () {
    final context = EngineContext();
    Physics3D().install(context);
    expect(CameraRegistries.of(context).stages.stageFor(CameraCollision3D()), isA<CameraCollisionStage>());
    expect(context.definitions.definitionFor(CameraCollision3D()), isNotNull);
  });
}
