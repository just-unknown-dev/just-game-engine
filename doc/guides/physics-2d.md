# 2D physics

_Gameplay_ · Give entities bodies and shapes with RigidBody2D and Collider2D, move them with forces or a CharacterBody2D, and react to collisions, sensors and queries.

`RigidBody2D` says how a body moves and `Collider2D` gives it a shape. Put them on an entity that has a `TransformComponent` and the engine simulates it. The 3D components use the same names with a `3D` suffix, so what you learn here carries over to [3D physics](/docs/physics-3d).

## How it fits together

`PhysicsSystem` is one of the default systems (`DefaultSystem.physics`, part of `DefaultSystems.all`). Each fixed step it makes a body for every entity with a `Collider2D`, applies the forces and velocities you asked for, steps `engine.physics`, writes the results back to `TransformComponent` and `VelocityComponent`, and fires collision and sensor events on `world.events`. It runs at `SystemPriorities.physics` (90), after input (100) and player control (95), so a velocity you set in a step moves the body in that same step. See [ECS](/docs/ecs) for how priorities work.

Units are world units (pixels in a 2D game) and +Y is down: gravity points along +Y and a jump is −Y. The default gravity is 981 units/s², real gravity at 1 unit = 1 cm. Platformers usually want more, for example `engine.physics.setGravity(0, 2000)`.

## Bodies and colliders

A `Collider2D` on its own is a static body, so floors and walls need nothing else. It behaves like `RigidBody2D(bodyType: BodyType.static)` with the default settings. Add a `RigidBody2D` when the body should move, or when a static body needs its own friction, bounce or layer.

```dart lib/playground.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void buildPlayground(Engine engine) {
  engine.physics.setGravity(0, 2000);
  final world = engine.world;

  // Static ground: a collider alone. matchShape follows the rectangle.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 200, 0)),
    RectangleComponent(
      width: 900,
      height: 40,
      fillStyle: const ShapePaintStyle(color: Colors.brown),
    ),
    Collider2D(shape: ColliderShape2D.matchShape),
  ], name: 'Ground');

  // A dynamic ball.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-100, -200, 0)),
    VelocityComponent(),
    CircleComponent(
      radius: 20,
      fillStyle: const ShapePaintStyle(color: Colors.red),
    ),
    RigidBody2D(restitution: 0.7),
    Collider2D(shape: ColliderShape2D.circle, radius: 20),
    TagComponent('ball'),
  ], name: 'Ball');

  // A sensor reports overlaps and blocks nothing.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(300, 140, 0)),
    RigidBody2D(bodyType: BodyType.static, isSensor: true),
    Collider2D(size: Vector2(80, 80)),
  ], name: 'Goal');

  world.events.on<CollisionEnter2DEvent>((e) {
    debugPrint('${e.entityA.name} touched ${e.entityB.name}');
  });
  world.events.on<SensorEnter2DEvent>((e) {
    if (e.other.hasTag('ball')) debugPrint('Goal!');
  });
}
```

> **Note:** A contact bounces as much as the less bouncy of its two bodies, and a collider-only body has no bounce. For a bouncy floor, give it `RigidBody2D(bodyType: BodyType.static, restitution: 1)`.

## Body types

| `bodyType` | Moves | Use it for |
|---|---|---|
| `BodyType.dynamic` (default) | by gravity, forces and collisions | crates, balls, debris |
| `BodyType.kinematic` | only by the velocity you give it, and cannot be pushed | moving platforms, lifts |
| `BodyType.static` | never | level geometry |

`isStatic`, `isKinematic` and `isDynamic` read the type back. A kinematic body you move by writing its transform carries what stands on it.

## Rigid body settings

| Field | Default | What it does |
|---|---|---|
| `mass` | 0 | Mass in kg. 0 works it out from the collider's area: a 100 × 100 box weighs 1000 kg (`PhysicsSystem.autoMassPerSquareUnit`). |
| `friction` | 0.5 | Grip, from 0 (ice) up. A contact uses both bodies' friction. |
| `restitution` | 0 | Bounce, 0 to 1. |
| `linearDamping` | 0.05 | Speed a dynamic body loses on its own each second. |
| `angularDamping` | 0.05 | The same, for spin. |
| `gravityScale` | 1 | 0 floats, 2 falls hard. Handy for variable jump height. |
| `isSensor` | false | Report overlaps and stop nothing: triggers, pickups, zones. |
| `lockRotation` | false | Never turn. |
| `continuousCollision` | false | Sweep a small, fast body so it cannot pass through thin walls. Native backend only. |
| `canSleep` | true | Let a body at rest fall asleep until something touches it. |
| `initialVelocity`, `initialAngularVelocity` | zero | What the body starts with. A `VelocityComponent` wins. |
| `layer`, `collidesWith`, `groupIndex` | 0, null, 0 | Collision filtering; see below. |

A platformer character usually wants `friction: 0`, so it slides down walls instead of sticking to them, and `lockRotation: true`. Friction, bounce and damping you change while the game runs take effect on every platform.

After each step `PhysicsSystem` fills in `linearVelocity`, `angularVelocity`, `isAwake`, `isGrounded`, `groundEntity` and `groundNormal`. `isGrounded` stays true for as long as a contact from below lasts.

## Collider shapes

| `shape` | Sized by |
|---|---|
| `ColliderShape2D.box` (default) | `size`, the full width and height (64 × 64 by default); `cornerRadius` rounds the corners |
| `ColliderShape2D.circle` | `radius` |
| `ColliderShape2D.capsule` | `radius` and `height`, the whole height along Y, ends included |
| `ColliderShape2D.polygon` | `points`, a convex polygon of at most 8 points; `cornerRadius` |
| `ColliderShape2D.segment` | the first two `points`, `thickness` thick |
| `ColliderShape2D.chain` | every one of `points`, closed with `loop`, `thickness` thick: terrain |
| `ColliderShape2D.matchShape` | whatever the entity draws: a rectangle, circle, capsule, polygon or line component, else its sprite's box |

A match shape follows the drawing as it changes. Every shape is centred on the entity unless `offset` moves it, and `rotation` and `scale` turn and stretch the collider itself. The collider also grows and shrinks with the entity's scale, as its sprite does; a negative scale on a box, circle or upright capsule does not rebuild the body, so flipping a character to face the other way stays cheap.

`oneWay: true` makes a platform you can jump up through. `oneWayDirection` picks the solid side: `fromAbove` (the default), `fromBelow`, `fromLeft` or `fromRight`. `showDebugOutline: false` leaves a collider out of the debug outlines (see [Debugging](/docs/debugging)).

## Moving bodies from code

Push a `RigidBody2D` with `addForce`, `addImpulse`, `addTorque`, `addAngularImpulse`, `setVelocity`, `setAngularVelocity` and `wakeUp`. Each applies at the next physics step. You can also write the entity's `VelocityComponent`, which the physics system picks up, and teleport a body by writing its `TransformComponent`.

A simple platformer controller is a system at `SystemPriorities.playerControl` that sets `velocity.x` from the `move` action and, when `body.isGrounded` and `jump` was pressed, sets `velocity.y = -800` (up is −Y). Reading actions is covered in [Input](/docs/input).

## Character bodies

A `CharacterBody2D` is a character that gameplay moves rather than the simulation. It walks slopes up to `maxSlopeAngle` (50° by default), climbs steps up to `stepHeight`, keeps to the floor going down (`stickToFloor`), rides moving platforms, stands on one-way platforms and jumps up through them, and pushes dynamic bodies. It needs no `RigidBody2D` or `Collider2D`: its shape is its own, a capsule or a box (`CharacterShape2D`), centred on the entity plus `offset`.

```dart lib/hero.dart
Entity addHero(World world) => world.createEntityWithComponents([
  TransformComponent(),
  InputComponent(),
  RectangleComponent(width: 32, height: 48),
  CharacterBody2D(shape: CharacterShape2D.box, width: 32, height: 48),
  TagComponent('player'),
], name: 'Hero');

class HeroControlSystem extends System {
  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [InputComponent, CharacterBody2D];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final input = entity.getComponent<InputComponent>()!;
      final body = entity.getComponent<CharacterBody2D>()!;
      body.moveVelocity = Offset(input.vector('move').dx * 260, 0);
      if (body.isGrounded && input.wasPressed('jump')) body.jump(800);
    });
  }
}
```

While `useGravity` is on (the default) only the sideways part of `moveVelocity` counts; the system adds gravity and the ground's own velocity. After each step read `velocity`, `groundState` (a `GroundState2D`), `isGrounded`, `groundNormal`, `groundVelocity` and `groundEntity`. The character's own body is kinematic, so sensors see it and dynamic bodies bump into it, but it touches static ground through its mover rather than through contacts: read `groundEntity` to know what it stands on. Set `detectable: false` to hide it from sensors and rays.

## Joints

Put a joint on an entity that has a body and point `connectedBody` at the other one with an [EntityTarget](/docs/tags-spawners), such as `EntityTarget.name('Anchor')`. `PhysicsJointBindingSystem`, part of the default physics systems, makes the joint once both bodies exist and remakes it when a setting changes.

| Joint | What it does | Main fields |
|---|---|---|
| `DistanceJoint2D` | keeps two bodies a set distance apart, springily | `length`, `stiffness` (Hz; 0 holds the length rigidly), `damping` (a damping ratio) |
| `FixedJoint2D` | holds two bodies rigidly together | none |
| `SliderJoint2D` | lets the bodies slide along one axis | `axis`, `useLimits`, `minPosition`, `maxPosition`, `enableMotor`, `motorSpeed`, `motorMaxForce` |
| `WheelJoint2D` | a wheel on a suspension | `axis`, `stiffness`, `damping`, `enableMotor`, `motorSpeed`, `motorMaxTorque` |

Every joint also has `anchor`, `connectedAnchor`, `collideConnected` (false: the two bodies do not collide with each other) and `enabled`. Axes are in the joint entity's own space.

## Layers and filtering

Each body sits on one of 16 collision layers, `layer: 0` to `15`. The project names the layers and says which ones collide in `assets/project/physics.json`, a `PhysicsLayers` that the editor's Physics Layers dock writes. `Engine.initialize` reads it when the app bundles it, so list the file under `flutter: assets:`. Without it every body collides with every other.

The file lists each layer by number, for example `{"version": 1, "layers": [{"index": 1, "name": "Player"}, {"index": 2, "name": "Enemy", "ignores": [2]}]}`, where enemies pass through each other. Read the grid in code with `engine.context.physicsLayers`, for example `engine.context.physicsLayers.collides(1, 2)`.

- `collidesWith` is a mask (bit `n` for layer `n`) that overrides the grid for one body: `RigidBody2D(layer: 2, collidesWith: (1 << 0) | (1 << 2))`. Two bodies collide only when each collides with the other's layer.
- Set `collidesWith = 0` to make a body collide with nothing for a while, such as a crumbling platform, and set it back to `null` to follow the grid again.
- `groupIndex` overrides layers for a group: a positive group always collides with itself, a negative one never does, and 0 leaves it to the layers.

## Collision and sensor events

Listen on `world.events`. Events are per pair of entities, so a chain collider sends one enter and one exit.

| Event | When | Fields |
|---|---|---|
| `CollisionEnter2DEvent` | two bodies begin touching | `entityA`, `entityB`, `point`, `normal` (from A towards B), `depth` |
| `CollisionStay2DEvent` | every step they keep touching, once you turn it on | the same |
| `CollisionExit2DEvent` | they stop touching | `entityA`, `entityB` |
| `SensorEnter2DEvent` | something enters a sensor | `sensor`, `other` |
| `SensorExit2DEvent` | something leaves a sensor | `sensor`, `other` |

Stay events are off so that nothing pays for them unasked. Turn them on with `engine.world.getSystem<PhysicsSystem>()?.reportContactStay = true`.

## Queries

`Physics2DQueries` casts rays and circles and finds overlaps, answering with entities. Every query takes a `layerMask` (all layers by default), an entity to `ignore` (usually the one asking) and `includeSensors` (false by default).

```dart lib/vision.dart
/// Whether [guard] can see the player straight ahead.
bool canSeePlayer(Engine engine, Entity guard) {
  final queries = Physics2DQueries(
    engine.physics,
    engine.world.getSystem<PhysicsSystem>()!,
  );
  final eyes = guard.getComponent<TransformComponent>()!.position;
  final hit = queries.raycast(
    Offset(eyes.x, eyes.y),
    const Offset(1, 0),
    maxDistance: 300,
    ignore: guard,
  );
  return hit?.entity?.hasTag('player') ?? false;
}
```

`raycastAll` returns every hit, nearest first, and `circleCast` sweeps a circle. `overlapCircle` and `overlapBox` (a `Rect`) return the entities they touch. A hit (`PhysicsHit2D`) carries `entity`, `body`, `point`, `normal`, `distance` and `fraction`.

## Two backends

`engine.physics` is a `PhysicsEngine` from `just_physics_engine`. On native platforms it is Box2D v3 through FFI; on the web (JavaScript and WebAssembly), or wherever the native library does not load, it is a pure-Dart engine with the same API. Your components, events and queries are the same on both. To choose the engine yourself, pass `EngineConfig(createPhysics: ...)`: for example `createPhysics: PhysicsEngine.pureDart` runs the pure-Dart engine on every platform.

## Known limitations

These wait on `just_physics_engine`. The fields involved are saved as usual, so scenes need no change when the limits lift.

- `anchor` and `connectedAnchor` of `DistanceJoint2D` and `FixedJoint2D` are not passed to the physics engine: a distance joint holds the bodies by their centres, and a fixed joint holds them as they were when joined. A wheel joint's axle anchor is honoured on native Box2D only.
- Jointed bodies with `collideConnected` off send no contact events between them, but on the pure-Dart backend they still push each other apart.
- On native Box2D, queries skip bodies whose collision mask is 0 (such as `collidesWith: 0`); the pure-Dart backend finds them.
- `continuousCollision` works on the native backend only.
- `CollisionEnter2DEvent.depth` is always 0, and its `point` is worked out from where the two bodies' bounds meet, because neither backend reports them in 2D.
- On native Box2D a static sensor does not report static colliders.
