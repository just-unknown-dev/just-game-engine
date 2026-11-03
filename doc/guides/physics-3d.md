# 3D physics

_Gameplay_ · Opt into Jolt-based 3D physics with Physics3D, then use RigidBody3D, Collider3D and CharacterBody3D, which mirror the 2D components.

3D physics runs on Jolt Physics and is opt-in. A game without it is 2D only, and its release build carries no 3D code and no Jolt. The components mirror [2D physics](/docs/physics-2d): `RigidBody3D` says how a body moves, `Collider3D` gives it a shape, and the events and queries have the same names with `3D` for `2D`.

## Turn it on

Import `package:just_game_engine/physics_3d.dart` and give the engine a `Physics3D`. Jolt is native code, so the app's own `pubspec.yaml` must also ask for it to be built. An app that gets Jolt only through another package builds nothing.

```yaml pubspec.yaml
hooks:
  user_defines:
    just_jolt:
      build: true
```

```dart lib/main.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

Future<Engine> createEngine() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      // Null where Jolt cannot run, such as the web.
      physics3D: Physics3D.isSupported ? Physics3D() : null,
    ),
  );
  await engine.initialize();
  if (engine.physics3D == null) {
    debugPrint('No 3D physics here: ${Physics3D.unsupportedReason}');
  }
  return engine;
}
```

As the engine is made, `Physics3D` registers the 3D components, so scenes holding them load and save, and adds a camera stage that keeps cameras out of walls. As the engine initializes, it starts Jolt and adds `PhysicsSystem3D` to the world. The physics world itself is made only when the first 3D body or character appears, so a game whose 3D scenes come later pays nothing until then. `engine.physics3D` is the `Physics3D` you passed, or null.

## Where it runs

Where 3D physics cannot run, `initialize()` fails with an `EngineInitException` whose `cause` is a `Physics3DUnsupportedError`. That happens on the web, on 32-bit Android ABIs, and in an app whose pubspec did not ask for Jolt. Ask first with `Physics3D.isSupported`, and read why with `Physics3D.unsupportedReason`, as the sample above does.

| Platform | Jolt (`just_jolt` 0.1.0) |
|---|---|
| Windows x64 | built and tested |
| Android arm64-v8a, x86_64 | built by the hook (NDK r26 or newer) |
| Linux, macOS, iOS | should build; untested |
| Web | not available |

The component classes are plain data with no native code. Where Jolt cannot run, `Physics3D.registerSchemas(engine.context)` registers them without simulating them, which is what a tool that reads and writes 3D scenes uses.

> **Tip:** On Windows, Jolt builds inside the app's `.dart_tool` folder, so keep the app's folder path under about 175 characters.

## Units and settings

Units are metres, seconds and radians, and +Y is down, so gravity is (0, 9.81, 0) unless you pass `Physics3D(gravity: ...)`. The other options are `workerThreads` (below 0: cores minus one, the default), `maxBodies` (10240), `reportContactStay`, `reportActivation`, `addSystem` (true; false leaves adding `system` to the game) and `engine`, a `PhysicsEngine3D` of your own.

## Bodies and colliders

As in 2D, a `Collider3D` alone is a static body, and a `RigidBody3D` beside it says how it moves. `RigidBody3D` has the 2D fields: `bodyType` (`BodyType3D.static`, `kinematic` or `dynamic`, the default), `mass` (0 works it out from the collider's volume), `friction` (0.5), `restitution` (0), `linearDamping` and `angularDamping` (0.05), `gravityScale`, `isSensor`, `lockRotation`, `continuousCollision`, `canSleep`, `layer`, `initialVelocity` and `initialAngularVelocity`. Changing `bodyType`, damping, `isSensor`, `canSleep` or `lockRotation` rebuilds the body.

Push a body with `addForce` (N), `addTorque`, `addImpulse` (N·s), `addAngularImpulse`, `setVelocity`, `setAngularVelocity` and `wakeUp`, all applied before the next step. After each step it holds `linearVelocity`, `angularVelocity` and `isAwake`. Move a kinematic or static body by writing its transform. A 3D body has only a `layer`: there is no `collidesWith` or `groupIndex`, so the project's layer grid decides what collides.

| `ColliderShape3D` | Sized by |
|---|---|
| `box` (default) | `size`, the full size along X, Y and Z (1 m) |
| `sphere` | `radius` (0.5 m) |
| `capsule` | `radius` and `height`, along Y, caps included |
| `cylinder` | `radius` and `height`, along Y |
| `convexHull` | the convex hull of a model's vertices: `model` (a `.glb` or `.gltf`) and optionally `meshName` |
| `mesh` | a model's triangles; static and kinematic bodies only |
| `heightField` | terrain from `heights`, `heightFieldSize` samples a side (at least 4) and `cellSize`; static bodies only |
| `matchShape` | the 3D shape the entity is drawn as, such as `Cube3D` or `Stairs3D`; concave ones are made of convex parts, so they work on dynamic bodies too |

Each shape has its own `offset`, `rotation` (Euler angles) and `scale`, and follows the entity's scale. Models load through the engine's assets. Bodies have no look of their own: draw them with [3D graphics](/docs/graphics-3d).

```dart lib/room.dart
void buildRoom(World world) {
  // A floor: a collider alone is static. +Y is down, so -2 is above it.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 0.5, 0)),
    Collider3D(size: Vector3(20, 1, 20)),
  ], name: 'Floor');

  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -2, 0)),
    Collider3D(),
    RigidBody3D(),
  ], name: 'Crate');

  // A coin: a static sensor.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(4, -1.2, 0)),
    Collider3D(shape: ColliderShape3D.sphere, radius: 0.3),
    RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
  ], name: 'Coin');

  // A door on a hinge that swings to 1 radian. Jointed bodies still
  // collide, so the frame stands clear of the door.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-0.5, -1, 0)),
    Collider3D(size: Vector3(0.2, 2, 0.2)),
  ], name: 'Frame');
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0.6, -1, 0)),
    Collider3D(size: Vector3(1, 2, 0.1)),
    RigidBody3D(gravityScale: 0),
    HingeJoint3D(
      connectedBody: const EntityTarget.name('Frame'),
      anchor: Vector3(-0.5, 0, 0),
      motor: MotorState3D.position,
      motorTarget: 1,
    ),
  ], name: 'Door');
}
```

## Characters

A `CharacterBody3D` is a capsule that gameplay moves rather than forces (Jolt's `CharacterVirtual`). It walks on ground, slides along walls, climbs steps and slopes, and rides moving platforms. Its entity's position is its feet, and it needs no `RigidBody3D` or `Collider3D`. The defaults are a character 1.8 m tall with a 0.3 m radius, `maxSlopeAngle` 50°, `stepHeight` 0.4 m, `stickToFloor` 0.5 m, `mass` 70 kg and `pushStrength` 100 N.

```dart lib/hero_3d.dart
class Hero3DControlSystem extends System {
  static const double speed = 4; // m/s

  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [InputComponent, CharacterBody3D];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final input = entity.getComponent<InputComponent>()!;
      final body = entity.getComponent<CharacterBody3D>()!;
      final move = input.vector('move'); // y is down: "up" is -1
      body.moveVelocity.setValues(move.dx * speed, 0, -move.dy * speed);
      if (body.isGrounded && input.wasPressed('jump')) body.jump(5);
    });
  }
}
```

With `useGravity` on, the system adds gravity and the ground's velocity to `moveVelocity`. Turn it off and `moveVelocity` is the whole velocity, for flying, swimming or ladders. After each step read `velocity`, `groundState` (a `GroundState3D`), `isGrounded`, `groundNormal`, `groundVelocity` and `groundEntity`. A `detectable` character is seen by sensors and hit by rays.

## Joints

Every joint sits on one entity and names the other with `connectedBody`, an `EntityTarget`; leave it as `EntityTarget.none` to join the body to the world. `anchor` is in the joint entity's own space, and `enabled` switches the joint off. The joint is made where the bodies are when both exist, and made again when a setting changes. Jointed bodies still collide with each other: leave a gap between them, or put them on layers that do not collide.

| Joint | What it does |
|---|---|
| `FixedJoint3D` | holds two bodies rigidly together |
| `PointJoint3D` | holds them at one point, free to turn (a ball joint) |
| `HingeJoint3D` | turns about `axis`, with optional limits (`useLimits`, `minAngle`, `maxAngle`), `friction` and a motor; reports `angle` |
| `SliderJoint3D` | slides along `axis`, with optional limits, `friction` and a motor; reports `position` |
| `DistanceJoint3D` | keeps `anchor` and `connectedAnchor` between `minDistance` and `maxDistance`, with `springFrequency` and `springDamping` |
| `SixDofJoint3D` | each of the six axes `SixDofAxisMode3D.free`, `limited` or `fixed` |

A motor is `MotorState3D.off`, `velocity` (a target speed) or `position` (a target angle or position), set by `motorTarget` and capped by `motorMaxTorque` or `motorMaxForce`.

## Events and queries

The events fire on `world.events` after the step, with the 2D fields: `CollisionEnter3DEvent` and `CollisionStay3DEvent` (`entityA`, `entityB`, `point`, `normal`, `depth`), `CollisionExit3DEvent`, and `SensorEnter3DEvent` and `SensorExit3DEvent` (`sensor`, `other`). Stay events fire only with `Physics3D(reportContactStay: true)`.

`engine.physics3D!.queries` is a `Physics3DQueries`: `raycast`, `raycastAll`, `sphereCast`, `shapeCast`, `overlapSphere`, `overlapBox` and `overlap`. Like the 2D queries, each takes `layerMask`, `ignore` and `includeSensors`, and a hit (`PhysicsHit3D`) names its `entity`, `point`, `normal` and `distance`. For example, `queries.raycast(Vector3(0, -10, 0), Vector3(0, 1, 0), maxDistance: 50)` looks straight down (+Y is down). Until the first 3D body exists every query finds nothing.

To keep a third-person camera out of walls, add `CameraCollision3D` to the camera entity beside its `OrbitFollowComponent`; see [Cameras](/docs/cameras).
