# Upgrading from 1.6 to 2.0

just_game_engine 2.0.0 is a breaking release. The engine is now an object you create, initialize and dispose yourself. Levels are JSON scenes that the game loads at run time. Cameras, input, sprites, tile maps and the transform hierarchy were rebuilt, and several built-in parts moved to packages of their own.

This guide lists what you have to change, area by area, with code from 1.6 ("before") and 2.0 ("after"). The [CHANGELOG](CHANGELOG.md) summarizes the release, including the additions.

Scene files saved by earlier versions still load: they are migrated in memory when they are read (see [Saved data](#saved-data)).

## Checklist

- [ ] Raise the constraints: `just_game_engine: ^2.0.0-dev.4`, Flutter 3.47.1 or newer ([Dependencies](#dependencies)).
- [ ] Create the engine with `Engine(config: ...)`, `await initialize()` before `runApp`, and dispose it once. Replace `Engine.instance` with a reference you pass around ([Engine setup](#engine-setup-and-lifecycle)).
- [ ] Add the standard systems through `EngineConfig.defaultSystems`, or give `Physics2DSystem` the engine's physics ([Systems](#systems)).
- [ ] Physics bodies: `PhysicsBodyComponent` becomes a `RigidBody2DComponent` and a `Collider2DComponent`, with 3-D's names and defaults; `bodyType` instead of `isStatic`, a layer number instead of a layer bit, colliders that follow scale, and the `...2D` events ([Physics bodies](#physics-bodies)).
- [ ] If you used achievements, sign-in, leaderboards, currency, inventory or ads: add `just_game_services` ([Game services](#game-services)).
- [ ] `transform.rotation` becomes `transform.angle` ([Transforms](#transforms)).
- [ ] Drop `HierarchySystem` (removed) and rename `localOffset` to `localPosition` ([The transform hierarchy](#the-transform-hierarchy)).
- [ ] Replace camera behaviours and `CameraFollowComponent` with virtual cameras ([Cameras](#cameras)).
- [ ] Read input as actions from `just_inputs` ([Input](#input)).
- [ ] Move text, buttons and progress bars to `just_ui_editor` or to Flutter widgets ([In-game UI](#in-game-ui)).
- [ ] Replace the Tiled components with `LevelMapComponent` ([Tile maps](#tile-maps-and-level-maps)).
- [ ] Replace `engine.animation`, tweens and `AnimationStateComponent` ([Sprites and animation](#sprites-and-animation)).
- [ ] Read tags with `hasTag` / `tags` ([Tags and targets](#tags-and-targets)).
- [ ] Move render hooks to the hook chains; draw collider outlines with a `Collider2DDebuggerSystem` given a camera ([Rendering](#rendering)).
- [ ] Fix imports: `package:just_game_engine/widgets.dart` for the widgets, and the source package for names no longer re-exported ([Imports](#imports)).
- [ ] Check the lists of [removed](#removed-apis) and [renamed](#renamed-apis) APIs. Coming from an earlier 2.0 dev release, check [Renamed in 2.0.0-dev.4](#renamed-in-200-dev4) and [Removed in 2.0.0-dev.4](#removed-in-200-dev4) too.
- [ ] Re-test what [behaves differently](#behaviour-you-may-notice).
- [ ] Using joints or audio streams? Read the [known limitations](#known-limitations-in-200).

## Dependencies

```yaml
environment:
  sdk: ^3.11.0
  flutter: ">=3.47.1"

dependencies:
  just_game_engine: ^2.0.0-dev.4
```

`just_game_services` (achievements, auth, leaderboards, currency, inventory, ads) is not yet on pub.dev; see [Game services](#game-services).

2.0 is out as dev releases, now 2.0.0-dev.4; a `^2.0.0` constraint does not pick them up.

2.0 needs Flutter 3.47.1 or newer: `just_graphics_engine` needs the first stable where Flutter GPU can be switched on in Windows and Linux release builds, and `just_inputs` and `just_audio_engine` build their Android code with Flutter's built-in Kotlin. The engine now depends on `just_inputs`, `just_deflate`, `just_game_engine_formats` (0.3.0, for scene format 11), `just_graphics_engine` and `path_provider`, and on `just_physics_engine` 1.4.1, `just_audio_engine` 1.1.0, `just_tiled` 0.4 and `just_dart` 0.2.0. It no longer depends on `web`.

## Engine setup and lifecycle

### Engine() makes a new engine

In 1.6, `Engine()` returned one process-wide engine, also reachable as `Engine.instance`. In 2.0, `Engine()` is an ordinary constructor: every call makes a new, independent engine. `Engine.instance` and `Engine.resetInstance()` are gone. Keep the engine you made and pass it to the code that needs it.

Before (1.6):

```dart
// 1.6
class _GamePageState extends State<GamePage> {
  final engine = Engine(); // the shared engine

  @override
  void initState() {
    super.initState();
    engine.initialize().then((ok) {
      engine.world.addSystem(RenderSystem());
      engine.start();
    });
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GameWidget(engine: engine);
}
```

After (2.0) — build and initialize the engine before `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize();
  engine.start();

  runApp(MaterialApp(home: Scaffold(body: GameWidget(engine: engine))));
}
```

A widget that owns its engine disposes it when it goes. `dispose()` returns a `Future`, but it tears the engine down before its first `await`, so not awaiting it in `State.dispose` is safe:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  late final Future<void> ready = engine.initialize().then(
    (_) => engine.start(),
  );

  @override
  void dispose() {
    unawaited(engine.dispose()); // final: this engine cannot start again
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) =>
        snapshot.connectionState == ConnectionState.done
        ? GameWidget(engine: engine)
        : const SizedBox.shrink(),
  );
}
```

The `FutureBuilder` is optional: a `GameWidget` given an engine that is still initializing starts drawing and ticking it once it is ready, with no rebuild. Your own code can follow the engine the same way through `engine.stateListenable`, a `ValueListenable<EngineState>` notified on every change of `engine.state`.

### What changed in the lifecycle

| 1.6 | 2.0 |
|---|---|
| `Engine()` returns the shared engine; `Engine.instance`, `Engine.resetInstance()` | `Engine({config, context})` makes a new engine each time; keep a reference |
| `Future<bool> initialize()` printed errors and returned `false` | `Future<void> initialize()` throws `EngineInitException(stage, cause, stackTrace)`, undoes what it built, and may be called again; `engine.lastError` keeps the failure |
| `EngineState.error` | `EngineState.failed`; new `disposing` and `disposed` |
| `isInitialized` was true in every state after `uninitialized` | true only while initialized, running or paused; new `isDisposed` |
| `start()` before `initialize()` printed a message | throws a `StateError` unless the engine is `initialized` |
| `void dispose()`; the singleton could be reset and reused | `Future<void> dispose()`, and it is final: make a new `Engine()` to start over |
| `rendering`, `physics`, `world`, … were `late final` fields (a `LateInitializationError` before `initialize`) | getters that throw `EngineNotReadyError` naming the member, before `initialize` and after `dispose` |
| `getSystem<T>()` | `subsystem<T>()` (`getSystem` is removed) |

A failed start can be reported and retried:

```dart
try {
  await engine.initialize();
} on EngineInitException catch (e) {
  debugPrint('The engine failed at ${e.stage}: ${e.cause}');
}
```

`plugins`, `layers`, `terminal`, `context`, `assets` and `services` exist for the whole life of the engine, so they can be set up before `initialize()`.

### EngineConfig

Everything that shapes an engine is in one `EngineConfig`, given to the constructor:

| Field | What it does |
|---|---|
| `defaultSystems` | The standard ECS systems to add (below). Empty by default. |
| `extensions` | `ContextExtension`s to install: a package's component definitions, migrations and registries. |
| `services` | `EngineService`s started with the engine, in the order listed (see [Game services](#game-services)). 3-D is two services from `package:just_game_engine/just_game_engine_3d.dart`: `services: [Graphics3D(), Physics3D()]`. `Graphics3D` draws 3-D on Flutter GPU (list it before any service that loads models as it starts); `Physics3D` gives the engine 3-D bodies on Jolt, and the app's pubspec must build Jolt (`hooks: user_defines: just_jolt: build: true`). Without them a game is 2-D only: no GPU device, no shaders loaded and no 3-D code. |
| `createRendering` | Builds your own `RenderingEngine`. |
| `createAudio` | Builds the `AudioEngine`, for example `AudioEngine.withBackend(...)`. |
| `createPhysics` | Builds the 2-D `Physics2DEngine` (`engine.physics`). Null makes the standard one: native Box2D, pure Dart on the web. |
| `deferAudioUntilInput` | Start audio at the first key or pointer press. `null` (the default) means on the web only, where browsers keep audio made before a user gesture suspended. |

`initialize(config: ...)` still takes a config and replaces the constructor's; prefer `Engine(config: ...)`.

### Your own components in scenes

`SceneLoader` refuses a scene that names a component type nobody has described: it throws `UnknownComponentTypeException` naming the type and the entity. A game with its own components gives them a `ComponentDefinition` and installs it through an extension:

```dart
class SpeedBoostComponent extends Component {
  SpeedBoostComponent({this.factor = 1.5});

  double factor;
}

final speedBoostDefinition = ComponentDefinition<SpeedBoostComponent>(
  type: 'SpeedBoostComponent',
  create: SpeedBoostComponent.new,
  fields: [
    FieldDefinition(
      name: 'factor',
      kind: FieldTypes.decimal,
      read: (c) => (c as SpeedBoostComponent).factor,
      write: (c, v) =>
          (c as SpeedBoostComponent).factor = (v as num).toDouble(),
    ),
  ],
);

final class MyGameExtension implements ContextExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) {
    context.definitions.register(speedBoostDefinition);
  }
}

final engine = Engine(
  config: const EngineConfig(
    extensions: [MyGameExtension()],
    defaultSystems: DefaultSystems.all,
  ),
);
```

Every engine has its own `EngineContext` (`engine.context`): the definitions, loaders, registries and localization it uses. Two engines in one process no longer share any of it. A `World()` made on its own gets a fresh context with only the ECS core's components (`World(extensions: [BuiltInComponents.extension])` adds the engine's); pass `World(context: engine.context)` for a second world that must read the engine's scenes.

## Systems

### Default systems

1.6 added no ECS systems; every game added `RenderSystem` and the rest itself. 2.0 can add the standard set for you:

```dart
final engine = Engine(
  config: const EngineConfig(defaultSystems: DefaultSystems.all),
);
```

`DefaultSystems.all` adds `InputSystem`, `Physics2DSystem` (which also makes the 2-D joints and moves the characters), `MovementSystem`, `AudioSystem`, `RenderSystem` and `ParallaxRenderSystem`, the sprite systems (`DefaultSystem.sprites`), the animator (`DefaultSystem.animation`), the timeline systems (`DefaultSystem.timelines`), `LevelMapSystem`, `MapCollisionSystem` and the camera systems. `DefaultSystems.headless` leaves out rendering and audio. Pick single ones with a set of `DefaultSystem` values; a set written for 2.0.0-dev.3 or earlier that names `DefaultSystem.sprites` adds `animation` and `timelines` to keep its animators and timelines. Nothing is added twice: a system you added yourself, configured your way, is kept. The same function is public as `registerDefaultSystems(world, engine)`.

`ParticleSystem` (1.6's `ParticleSystemECS`), `HealthSystem`, `LifetimeSystem`, `CheckpointSystem`, `EffectSystem` (1.6's `EffectSystemECS`) and the rest are not defaults: add the ones you use.

A game that keeps adding its systems itself needs no change here, apart from the constructors below.

### Constructors that changed

| 1.6 | 2.0 |
|---|---|
| `PhysicsSystem()` — its own simple solver, with `gravity` and `broadPhaseCellSize` | `Physics2DSystem(engine.physics)` steps and syncs the engine's physics (Box2D on native, pure Dart on the web); set gravity with `engine.physics.setGravity(x, y)` |
| `PhysicsBridgeSystem` next to it | removed: `Physics2DSystem` syncs bodies itself |
| `InputSystem(engine.input)..buttonMappings = {...}` | `InputSystem(engine.input, maps: ['player'])` (see [Input](#input)) |
| `CheckpointSystem(playerTag: ...)` | also takes `camera:` for its debug drawing |

Before (1.6):

```dart
// 1.6
engine.world
  ..addSystem(RenderSystem(camera: engine.cameraSystem.mainCamera))
  ..addSystem(PhysicsSystem()..gravity = Vector3(0, 980, 0));
```

After (2.0):

```dart
final camera = engine.camera.mainCamera;
engine.physics.setGravity(0, 980);
engine.world
  ..addSystem(RenderSystem(camera: camera))
  ..addSystem(Physics2DSystem(engine.physics));
```

`PhysicsBodyComponent` is now two components; see [Physics bodies](#physics-bodies).

## Physics bodies

**Two components, as in 3-D.** 1.6's `PhysicsBodyComponent` is split the way 3-D physics (and most engines) split a body: `RigidBody2DComponent` says how it moves, `Collider2DComponent` gives it its shape. The two dimensions use the same names, so what you learn in one carries over. A `Collider2DComponent` alone is a static body: walls and floors need nothing else.

```dart
// 1.6
PhysicsBodyComponent(
  shape: RectangleShape(32, 48),
  restitution: 0,
);

// 2.0
RigidBody2DComponent(friction: 0.2),
Collider2DComponent(size: Vector2(32, 48)),
```

Rows marked "pre-release 2.0" are fields that 1.6 did not have: they were added to `PhysicsBodyComponent` while 2.0 was being built, and only matter if you built on a pre-release.

| `PhysicsBodyComponent` | 2.0 |
|---|---|
| `shape: RectangleShape(w, h)` | `Collider2DComponent(size: Vector2(w, h))` (`box`, the default shape) |
| `shape: CircleShape(r)` | `Collider2DComponent(shape: Collider2DShape.circle, radius: r)` |
| `CapsuleShape`, `PolygonShape`, `SegmentShape`, `ChainShape` | `capsule` (`radius`, `height`), `polygon` (`points`), `segment`, `chain` (`points`, `loop`) |
| a shape sized to match the sprite or rectangle | `Collider2DShape.matchShape`: whatever the entity draws, kept in step as it changes |
| `isOneWay` | `Collider2DComponent.oneWay` (and `oneWayDirection`) |
| `offset`, `oneWayDirection`, `showDebugOutline` (pre-release 2.0) | `Collider2DComponent.offset`, `oneWayDirection`, `showDebugOutline` |
| `isStatic`; `effectiveBodyType` (pre-release 2.0) | `RigidBody2DComponent.bodyType` (`isStatic` stays as a read-only getter) |
| `drag` | `linearDamping` |
| `fixedRotation`, `isBullet` (pre-release 2.0) | `lockRotation`, `continuousCollision` |
| `collisionMask`, `canCollideWith`, `layer` as a bit | `layer` as a layer number, `collidesWith`, `PhysicsLayers.collides` |
| `categoryBits`, `maskBits` | `layer` (a number) and `collidesWith` |
| `mass`, `restitution`, `isSensor`, `groupIndex` | the same names, on `RigidBody2DComponent` |
| `friction`, `gravityScale`, `angularDamping`, `canSleep`, `initialVelocity`, `initialAngularVelocity` (pre-release 2.0) | the same names, on `RigidBody2DComponent` |
| `isGrounded`; `groundEntity`, `groundNormal` (pre-release 2.0) | the same names, on `RigidBody2DComponent`, with `linearVelocity`, `angularVelocity` and `isAwake` |

Code that read the body for its shape reads the collider: `entity.getComponent<Collider2DComponent>()`. Code that steered it reads the rigid body: `entity.getComponent<RigidBody2DComponent>()`.

**The defaults are 3-D's:** `friction` 0.5 (1.6 used the physics engine's 0.2 for every body), `restitution` 0 (1.6: 0.8, so everything bounced), `linearDamping` and `angularDamping` 0.05 (1.6's `drag` was 0.98: a body lost about 60% of its speed every second in the air) and `mass` 0, which works the mass out from the collider's area as 3-D does from its volume (a 100 × 100 box weighs 1000 kg; 1.6's default was 1). Set the old values where you relied on them. Scenes saved by 1.6 keep them: the migration writes each one out. Damping slows only a dynamic body: a kinematic one keeps the velocity it is given.

**Push from code** with `addForce`, `addImpulse`, `addTorque`, `addAngularImpulse`, `setVelocity`, `setAngularVelocity` and `wakeUp` on `RigidBody2DComponent`; each applies at the next physics step.

**Named collision layers.** A body is on one of sixteen layers, `layer: 0` to `15`, and collides with what the project's grid says for that layer — or, given `collidesWith` (a mask, bit `n` for layer `n`), only with those. The names and the grid are a `PhysicsLayers`, kept in `assets/project/physics.json`; `Engine.initialize` reads it when the app bundles it, so list the file under `flutter: assets:`. Without it every body collides with every other, as before. Two bodies collide only when each collides with the other's layer.

1.6's `layer` was a bit (1, 2, 4, …); 2.0's is the layer's number:

```dart
// 1.6
PhysicsBodyComponent(shape: s, layer: 4, collisionMask: 1 | 4);
if (a.canCollideWith(b.layer)) { ... }

// 2.0
RigidBody2DComponent(layer: 2, collidesWith: 1 << 0 | 1 << 2);
final layers = engine.context.physicsLayers;
if (layers.collides(a.layer, b.layer)) { ... }
```

To make a body collide with nothing for a while — a platform that crumbles — set `collidesWith = 0`, and back to what it was (`null` for the grid) to bring it back.

**Colliders follow scale.** A collider is its shape moved by its `offset`, turned and stretched by its own `rotation` and `scale`, and then by its entity's `TransformComponent`, as a sprite is: scale an entity ×2 and its collider grows with it, while the game runs too. Code that sized a shape for an entity it also scaled now sizes it unscaled. Saved scenes are migrated so nothing changes size ([saved data](#saved-data)). A negative scale on a box, circle or upright capsule does not rebuild the body, so turning a character round by its scale stays cheap.

**Events** carry the same names and fields as 3-D's:

| 1.6 | 2.0 |
|---|---|
| `CollisionEvent` | `CollisionEnter2DEvent`: `entityA`, `entityB`, `normal`, and `point`, `depth` |
| `ContactExitEvent` | `CollisionExit2DEvent` |
| `SensorEnterEvent` (`sensor`, `visitor`) | `SensorEnter2DEvent` (`sensor`, `other`) |
| `SensorExitEvent` (`sensor`, `visitor`) | `SensorExit2DEvent` (`sensor`, `other`) |

`CollisionStay2DEvent` is new: every step two bodies keep touching, once `Physics2DSystem.reportContactStay` is on (it is off, so nothing pays for it unasked).

**Queries.** `physicsSystem.queries` (a `Physics2DQueries`) casts rays (`raycast`, `raycastAll`) and circles (`circleCast`) and finds overlaps (`overlapCircle`, `overlapBox`), filtered by layer, answering with entities (`Physics2DHit`).

**Rays hit the physics colliders.** 1.6's `RaycastSystem` and `RaycastColliderComponent` were a second collision model beside the bodies; they are gone, with `RaycastHit`. Give what a ray should hit a `Collider2DComponent` (a sensor, if nothing should bump into it, found with `includeSensors: true`) and ask `physicsSystem.queries`; a `tag` filter becomes a layer (`layerMask`). `hasLineOfSight(from, to)` is a ray from `from` to `to` that hits nothing, or the target. `RayTracer`'s bounces are `RayTracer2D`'s, built on the same ray: a collider's `reflectivity` (saved, set in the inspector, 0 to absorb) replaces the ray collider's `isReflective` and `reflectivity`.

```dart
// 1.6
final rays = RaycastSystem();
engine.world.addSystem(rays);
final seen = rays.hasLineOfSight(eyes, target);
final beam = RayTracer(raycastSystem: rays).trace(Ray(origin: eyes, direction: aim));

// 2.0
final queries = engine.world.getSystem<Physics2DSystem>()!.queries;
final blocker = queries.raycast(
  eyes,
  target - eyes,
  maxDistance: (target - eyes).distance,
  ignore: guard,
);
final seen = blocker == null || blocker.entity == player;
final beam = RayTracer2D(queries).trace(eyes, aim, ignore: guard);
```

**Joints** are 3-D's names with a `2D` suffix, and point at the other body with an `EntityTarget` (a name, a tag or `self`) instead of a name string. 1.6 had no joint components; these rows are for code built on a pre-release 2.0:

| pre-release 2.0 | 2.0 |
|---|---|
| `DistanceJointComponent` | `DistanceJoint2DComponent` |
| `WeldJointComponent` | `FixedJoint2DComponent` |
| `PrismaticJointComponent` | `SliderJoint2DComponent` |
| `WheelJointComponent` | `WheelJoint2DComponent` |
| `targetEntityName` | `connectedBody` |
| `localAnchorA`, `localAnchorB` | `anchor`, `connectedAnchor` |
| `enableLimit`, `lowerTranslation`, `upperTranslation` | `useLimits`, `minPosition`, `maxPosition` |
| `maxMotorForce`, `maxMotorTorque` | `motorMaxForce`, `motorMaxTorque` |
| `suspensionAxis` | `axis` |

Every joint also has `enabled`; off, the joint is not made.

**New: `CharacterBody2DComponent`**, 3-D's `CharacterBody3DComponent` in 2-D: a character gameplay moves (`moveVelocity`, `jump`) instead of the simulation, walking slopes and steps and riding platforms. A platformer hero that fought its rigid body's physics — sliding down slopes, catching on seams — can move to it; it needs no rigid body or collider.

## Game services

Achievements, sign-in, leaderboards, currency, inventory and ads moved to the package `just_game_services`. In 1.6 every engine built all six; in 2.0 a game lists the ones it uses, and the engine starts them in `initialize()` and stops them in `dispose()`. `engine.achievements` and the others are extension getters from that package; they throw a `StateError` naming the fix when the engine has no such service.

`just_game_services` is not on pub.dev yet, so a hosted dependency on it does not resolve until it is published; watch the [engine repository](https://github.com/just-unknown-dev/just-game-engine) for its release.

Before (1.6):

```dart
// 1.6
await engine.initialize();
engine.achievements.define(
  Achievement(id: 'first_win', name: 'First Win', description: 'Beat level 1'),
);
engine.achievements.unlock('first_win');
```

After (2.0):

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_services/just_game_services.dart';

Future<Engine> startGame() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      services: [
        AchievementManager()..define(
          Achievement(
            id: 'first_win',
            name: 'First Win',
            description: 'Beat level 1',
          ),
        ),
        CurrencyManager(),
      ],
    ),
  );
  await engine.initialize(); // starts both services
  engine.achievements.unlock('first_win');
  engine.currency.add('coins', 10);
  return engine;
}
```

`EngineConfig(services: GameServices.all())` gives all six, as 1.6 had them. Saved progress carries over: achievements, currency and inventory still save to the `jge_engine` database. The managers' `bindWorld`, `initialize` and `dispose` are now `start` and `stop`, called by the engine. `AdsManager.initialize(consent: ...)` is still yours to call.

The Steam and Epic auth and leaderboard providers are gone; they did nothing. Write an `AuthProvider` or `LeaderboardProvider` for a real backend.

## Transforms

`TransformComponent.position` and `scale` were already `Vector3`. The rotation changed: the 2-D angle is `angle`, and the full rotation is three Euler angles.

| 1.6 | 2.0 |
|---|---|
| `transform.rotation` | `transform.angle` (radians about Z, clockwise on screen) |
| `transform.rotationX`, `rotationY` | `transform.eulerX`, `eulerY` |
| `TransformComponent(rotation: a)` | `TransformComponent(angle: a)` |
| `TransformComponent(rotationX: x, rotationY: y, rotation: a)` | `TransformComponent(euler: Vector3(x, y, a))` |
| `transform.prevRotation` (a `double`) | `transform.prevAngle`; `prevRotation` is now a `Quaternion` |
| writing `prevPosition`, `prevRotation`, then the pose | `transform.capturePrevious()`, then `transform.setPlanarPose(x, y, angle)` |
| `TransformSignals.rotation` | `TransformSignals.angle` |

Before (1.6):

```dart
// 1.6
final t = TransformComponent(position: Vector3(100, 50, 0), rotation: 0.5);
t.rotation += 0.1;
```

After (2.0):

```dart
final t = TransformComponent(position: Vector3(100, 50, 0), angle: 0.5);
t.angle += 0.1; // or t.rotate(0.1)

// A 3-D rotation, as Euler angles (x, y, z = angle), or as a quaternion:
final tilted = TransformComponent(euler: Vector3(0.2, 0, 0.5));
final q = Quaternion.identity();
tilted.rotationInto(q);
```

Setting `angle` is a plain field write; a 2-D game does no more work than before.

## The transform hierarchy

In 1.6 a child followed its parent only if the game added `HierarchySystem`, which copied the parent's position plus `localOffset` and added the angles. In 2.0 every `World` keeps its hierarchy itself (`world.transformHierarchy`), each frame after gameplay and physics: a child moves, turns and scales with its parent. `TransformComponent` is still the world transform. Where the child sits in its parent's space is in its `ParentComponent`.

What to change:

- Remove `HierarchySystem`: it is gone, since the world keeps the hierarchy itself.
- `ParentComponent(localOffset:, localRotation:)` becomes `ParentComponent(localPosition:, localRotation:, localScale:)`, with `localRotation` an `EulerRotation`. A link made with any of them places the child at them on the next update, whatever its `TransformComponent` says. Unlike `localOffset`, which was added to the parent's position, the offset turns and scales with the parent. Leave them all out and the child stays where its `TransformComponent` puts it; its offset is worked out from that. Scenes load their links this way.
- Nothing else. A `ParentComponent` is the whole link: the world lists the child in the parent's `ChildrenComponent` (making one when the parent has none), moves it when `parentId` changes, and takes it off when the link is removed or the child is destroyed. Code that added a `ChildrenComponent` by hand can go; replacing the parent's `ChildrenComponent` with a new one drops the children it does not list.
- Something that writes a child's world transform itself (physics, a timeline, your code) is noticed, and the child stays where it was put. `ParentComponent(inheritTransform: false)` keeps a link that should not move the child at all.

Before (1.6):

```dart
// 1.6
world.addSystem(HierarchySystem());
world.createEntityWithComponents([
  TransformComponent(),
  ParentComponent(parentId: ship.id, localOffset: Vector3(0, -20, 0)),
]);
```

After (2.0):

```dart
final ship = world.createEntityWithComponents([
  TransformComponent(position: Vector3(300, 200, 0)),
], name: 'Ship');
world.createEntityWithComponents([
  TransformComponent(),
  // Placed 20 units above the ship on the next update, and listed in the
  // ship's ChildrenComponent by the world.
  ParentComponent(parentId: ship.id, localPosition: Vector3(0, -20, 0)),
], name: 'Turret');
```

Destroying an entity now destroys its children too; see [Behaviour you may notice](#behaviour-you-may-notice).

## Cameras

The 1.6 camera followed through behaviours added to `CameraSystem` (`SpringFollowBehavior`, `LookaheadBehavior`, …) or a `CameraFollowComponent` on the target. All of that is gone. In 2.0 a shot is an entity with a `VirtualCameraComponent`; the camera brain (`engine.camera.brain`) picks the enabled shot with the highest priority and blends the output camera (`engine.camera.mainCamera`) to it. How the shot moves is decided by stage components on the same entity. The output camera, 1.6's `Camera`, is `OutputCamera`, and only the output: position, zoom, rotation, lens, screen/world conversion, visible bounds and screen effects.

The camera systems are in `DefaultSystems.all`, or add them with `registerCameraSystems(world, engine.camera)`. With no virtual camera in the world the brain leaves the output camera alone, so a game that moves `mainCamera` itself keeps working.

| 1.6 | 2.0 |
|---|---|
| `CameraFollowComponent` on the player, `CameraFollowSystem` | a camera entity: `VirtualCameraComponent(follow: EntityTarget.name('Player'))` + `CameraFramingComponent` |
| `SpringFollowBehavior`, `camera.follow(target)`, springs, `smoothing` | `CameraFramingComponent`: `dampingX` / `dampingY`, dead zone and soft zone (fractions of the screen) |
| `LookaheadBehavior`, `CameraFollowComponent.lookaheadDistance` | `CameraFramingComponent.lookaheadTime` |
| `MultiTargetBehavior` | `CameraTargetGroupComponent` + `CameraGroupFramingComponent` |
| `RoomBehavior`, `CameraRoom` | one virtual camera per room, a `CameraTriggerComponent` to switch, a `CameraConfinerComponent` to keep it inside |
| `PathBehavior`, `CameraPath`, `CameraKeyframe` | `CameraDollyComponent` |
| `CinematicBehavior`, `CinematicSequence`, `CinematicKeyframe` | `CameraBlendListComponent`, or a timeline with a `CameraShotTrack` |
| `camera.shake(...)`, `addTrauma`, `trauma` | `CameraImpulseListenerComponent` on the shot and `brain.emitImpulse(CameraImpulse(...))`; `CameraNoiseComponent` for continuous handheld motion |
| `worldBounds` | a `CameraBoundsComponent` entity and `CameraConfinerComponent(boundsName: ...)` |
| `setPosition(p, smooth: true)`, `setZoom(z, smooth: true)` | `setPosition` and `setZoom` are immediate; smoothing belongs to the shot's framing |
| `CameraFollowComponent.priority` | `VirtualCameraComponent.priority` |
| `cameraSystem.update(dt)` / `camera.update(dt)` | `CameraBrainSystem`, inside the ECS frame, after physics and before rendering |

Before (1.6):

```dart
// 1.6
engine.cameraSystem.addBehavior(SpringFollowBehavior(target: playerPosition));
engine.cameraSystem.mainCamera.worldBounds = const Rect.fromLTWH(0, 0, 4000, 800);
engine.cameraSystem.mainCamera.shake(12, 0.4);
```

After (2.0):

```dart
// The level's edges: a rectangle centred on its entity.
world.createEntityWithComponents([
  TransformComponent(position: Vector3(2000, 400, 0)),
  CameraBoundsComponent(width: 4000, height: 800),
], name: 'Level Bounds');

// The shot: follows the entity named Player, damped, inside the bounds.
world.createEntityWithComponents([
  TransformComponent(),
  VirtualCameraComponent(follow: const EntityTarget.name('Player')),
  CameraFramingComponent(dampingX: 0.3, dampingY: 0.5, lookaheadTime: 0.2),
  CameraConfinerComponent(boundsName: 'Level Bounds'),
  CameraImpulseListenerComponent(),
], name: 'Main Camera');

// A shake: every listening shot feels it, by distance.
engine.camera.brain.emitImpulse(
  CameraImpulse(position: const Offset(640, 360), amplitude: 12),
);
```

The dead zone and soft zone are fractions of the screen, not pixels. A `CameraFollowComponent` saved in a 1.x-era scene becomes a virtual camera when the scene loads (format 2).

## Input

`engine.input` was an `InputManager` that you polled for keys (`engine.input.keyboard.isKeyDown(...)`). In 2.0 it is a `just_inputs` `InputService`: named actions (`jump`, `move`) bound to keyboard, mouse, gamepads and touch, read the same way whatever the device, with local multiplayer and rebinding. The bindings live in an input asset (`.input.json`), which the game loads after `initialize()`; until then no action is bound.

Before (1.6):

```dart
// 1.6
engine.world.addSystem(
  InputSystem(engine.input)
    ..buttonMappings = {'jump': LogicalKeyboardKey.space},
);

final input = player.getComponent<InputComponent>()!;
final move = input.moveDirection;
if (input.isButtonPressed('jump')) jump();
if (engine.input.keyboard.isKeyDown(LogicalKeyboardKey.escape)) pause();
```

After (2.0):

```dart
Future<void> loadInput(Engine engine) async {
  final text = await rootBundle.loadString('assets/input/game.input.json');
  engine.input.loadAsset(InputActionAsset.parse(text));
  await engine.input.attachGamepads(); // optional: starts platform channels
}

void readInput(Engine engine, Entity player) {
  // InputSystem (a default system) copies the actions of the 'player' map
  // into each InputComponent, for the player it belongs to.
  final input = player.getComponent<InputComponent>()!;
  final Offset move = input.vector('move');
  final bool jump = input.wasPressed('jump');

  // Or read an action directly, anywhere:
  final pause = engine.input.actions.action('ui/pause');
  if (pause.wasPressedThisFrame()) engine.pause();
  debugPrint('move $move, jump $jump');
}
```

An asset can also be built in code. The asset model is not re-exported by the engine; import `just_inputs` for it:

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_inputs/just_inputs.dart'
    show
        ActionMapDef,
        CompositeBindingDef,
        CompositeKinds,
        CompositePartDef,
        ControlBindingDef,
        InputActionDef;

const gameInput = InputActionAsset(
  name: 'game',
  nextId: 10, // ids are numbered below this
  maps: [
    ActionMapDef(
      id: 'm1',
      name: 'player',
      actions: [
        InputActionDef(
          id: 'a2',
          name: 'jump',
          bindings: [ControlBindingDef(id: 'b3', path: '<Keyboard>/space')],
        ),
        InputActionDef(
          id: 'a4',
          name: 'move',
          type: ActionValueType.vector2,
          bindings: [
            CompositeBindingDef(
              id: 'b5',
              composite: CompositeKinds.vector2,
              parts: [
                CompositePartDef(id: 'p6', part: 'up', path: '<Keyboard>/w'),
                CompositePartDef(id: 'p7', part: 'down', path: '<Keyboard>/s'),
                CompositePartDef(id: 'p8', part: 'left', path: '<Keyboard>/a'),
                CompositePartDef(id: 'p9', part: 'right', path: '<Keyboard>/d'),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
```

| 1.6 | 2.0 |
|---|---|
| `engine.input.keyboard.isKeyDown(key)` | an action: `engine.input.actions.action('map/name').isPressed()` |
| `InputComponent.moveDirection` | `input.vector('move')` (any vector action, by name) |
| `InputComponent.isButtonPressed('jump')` | `input.isDown('jump')`; also `wasPressed`, `wasReleased`, `wasPerformed`, `axis` |
| `InputSystem.buttonMappings` | bindings in the input asset |
| `InputComponent()` | `InputComponent(playerIndex: 0)`: whose input it reads (`-1` for every device) |
| `VirtualJoystick`, `JoystickInputComponent` | on-screen controls in the asset, drawn by `OnScreenControls` (from `widgets.dart`) |
| `KeyboardInput`, `MouseInput`, `TouchInput`, `ControllerInput` | `engine.input.keyboard`, `mouse`, `touchscreen`, `gamepads` (devices) |

Input keeps running while the engine is paused, so menus and rebinding work. Players' own bindings are saved in the engine's cache (`CacheInputOverrideStore`).

## In-game UI

The engine no longer draws HUDs or menus. `TextComponent`, `ButtonComponent` and `UIComponent` moved to the package `just_ui_editor`, with the same names; `LinearProgressComponent` and `CircularProgressComponent` were dropped (`just_ui_editor` has `UiProgressComponent`). `just_ui_editor` also has screens saved as `.ui.json` assets and drawn as real Flutter widgets, themes, bindings and an editor. It is not published on pub.dev: install it from the editor's Asset Store, or depend on it by path or git.

For a simple HUD, a Flutter widget over the game is enough — `GameWidget.overlay` sits above the game and below the FPS counter and terminal:

```dart
Widget gameWithHud(Engine engine, ValueNotifier<int> score) => GameWidget(
  engine: engine,
  overlay: Align(
    alignment: Alignment.topLeft,
    child: ValueListenableBuilder<int>(
      valueListenable: score,
      builder: (context, value, _) => Text('Score: $value'),
    ),
  ),
);
```

Before (1.6):

```dart
// 1.6
world.createEntityWithComponents([
  TransformComponent(position: Vector3(20, 20, 0)),
  TextComponent(text: 'Score: 0'),
]);
```

After (2.0), with `just_ui_editor`:

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

Future<Engine> startWithUi() async {
  final engine = Engine(
    config: const EngineConfig(
      extensions: [JustGameUi.extension], // scenes may hold text and buttons
      defaultSystems: DefaultSystems.all,
    ),
  );
  await engine.initialize();
  await JustGameUi.install(engine); // reads assets/ui/screens.json

  engine.world.createEntityWithComponents([
    TransformComponent(position: Vector3(20, 20, 0)),
    TextComponent(text: 'Score: 0'),
  ]);
  return engine;
}
```

## Tile maps and level maps

The 1.6 Tiled support made one entity per layer (`TileMapLayerComponent`) and per object (`TiledObjectComponent`), drew them with `TileMapRenderSystem` and built collision with `TiledCollisionSystem`. None of it was saved in a scene, and the collision bodies had no entity. 2.0 replaces all of it with level maps: one `LevelMapComponent` holds a whole map — saved in the scene, or in its own `.map.json`, or a Tiled `.tmx` / `.tmj` read directly.

| 1.6 | 2.0 |
|---|---|
| `TiledMapFactory.spawnMap(world, map, atlases)` | an entity with `LevelMapComponent(mapPath: 'assets/maps/level.tmx')` |
| `TileMapLayerComponent` (one entity per layer) | the layers of one `LevelMapComponent` (`LevelMapData`, `MapLayerData`) |
| `TiledObjectComponent`, `ComponentMapper` | `TiledInterop.importMap` returns the objects (`TiledImport.objects`) for you to turn into entities |
| `TileMapRenderSystem(camera: ...)` | `LevelMapSystem`: each layer sorts among the sprites by its own layer and z-order |
| `TiledCollisionSystem(physicsEngine: ...)` | `MapCollisionSystem`: static bodies on generated entities, merged along runs of tiles |
| `SystemPriorities.tileMap` | `SystemPriorities.levelMap` (and `mapCollision`) |

Both systems are in `DefaultSystems.all`, or add them with `registerLevelMapSystems(world)`.

Before (1.6):

```dart
// 1.6
TiledMapFactory.spawnMap(world, map, atlases);
world
  ..addSystem(TileMapRenderSystem(camera: camera))
  ..addSystem(TiledCollisionSystem(physicsEngine: engine.physics));
```

After (2.0):

```dart
Future<void> loadLevelMap(World world) async {
  world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(mapPath: 'assets/maps/level_1.tmx'),
  ], name: 'Level Map');

  // Optional: load the map and its tilesets before the first frame.
  final failures = await LevelMaps.preload(world);
  for (final failure in failures) {
    debugPrint('$failure');
  }
}

// Change the map while the game runs (the scene's copy is untouched):
void breakBlock(World world, Offset worldPoint) {
  final map = LevelMaps.primary(world);
  final ground = map?.layer('Ground');
  if (map == null || ground == null) return;
  map.setTile(ground, map.cellAt(ground, worldPoint), TileCell.empty);
}
```

If you built on a pre-release 2.0, two level-map details changed:

- `MapBodySpec` is no longer `const`, and takes exactly one of `size` (a box) and `polygon`; both or neither throw an `ArgumentError`. Both used to mean the box.
- `LevelMapRuntime.hiddenCells` is read-only, and so is `hiddenRevision`. Hide and show cells with `LevelMapHandle.setCellsHidden` or `setBodyHidden`, which also redraw them; `LevelMapRuntime.hiddenCellsOf(layerId)` reads one layer's hidden cells.

## Sprites and animation

The legacy animation system is gone: `engine.animation` (`AnimationSystem`), `Animation`, `SpriteAnimation`, the tweens (`TweenAnimation`, `PositionTween`, `RotationTween`, `ScaleTween`, `OpacityTween`, `ColorTween`), `AnimationSequence`, `AnimationGroup`, `AtlasSpriteAnimation` and `SpriteAtlas.createAnimation`. So are the ECS frame counter (`AnimationStateComponent`, `AnimationSystemECS`) and `SpriteComponent.frame`.

| 1.6 | 2.0 |
|---|---|
| `SpriteComponent(frame:)` + `AnimationStateComponent` + `AnimationSystemECS` | `SpriteAnimationComponent(atlasPath:, clip:)` |
| `SpriteAnimation` / `AtlasSpriteAnimation` in `engine.animation` | `SpriteAnimationComponent` on an entity |
| `animationState.play('run')` | `spriteAnimation.switchClip('run')`, or an `AnimatorComponent` graph |
| a frame of a sprite sheet | `SpriteComponent(spritePath:, atlasPath:, region:)` |
| `PositionTween`, `RotationTween`, `ScaleTween`, `OpacityTween`, `ColorTween` | `MoveEffect`, `RotateEffect`, `ScaleEffect`, `FadeEffect`, `ColorTintEffect` through `EffectSystem`, or a timeline |
| `AnimationSequence`, `AnimationGroup` | `SequenceEffect`, `ParallelEffect`, or one timeline |
| top-level `linear`, `easeInQuad`, … | `Easings.linear`, `Easings.easeInQuad`, … |
| `typedef Easing` | `EasingFunction` |
| `EffectEasings.resolve(type, t)` | `type.transform(t)` (the `EasingType` values are unchanged) |

Before (1.6):

```dart
// 1.6
world.addSystem(AnimationSystemECS());
world.createEntityWithComponents([
  TransformComponent(position: Vector3(120, 300, 0)),
  SpriteComponent(spritePath: 'assets/hero_run.png'),
  AnimationStateComponent(currentAnimation: 'run', frameCount: 6),
]);
engine.animation.addAnimation(PositionTween(
  start: Vector3(0, 0, 0),
  end: Vector3(200, 0, 0),
  target: doorSprite,
  duration: 1.0,
  easing: Easings.easeInOutQuad,
));
```

After (2.0):

```dart
Entity spawnHero(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(120, 300, 0)),
  // Plays the 'run' tag of a TexturePacker or Aseprite atlas.
  SpriteAnimationComponent(atlasPath: 'assets/sprites/hero.json', clip: 'run'),
  // Optional: a state machine that picks the clip from the entity's speed.
  AnimatorComponent(
    graphPath: 'assets/sprites/hero.animator.json',
    faceVelocity: true,
  ),
], name: 'Hero');

void slideDoor(World world, Entity door) {
  final effects = world.getSystem<EffectSystem>() ?? EffectSystem();
  if (!world.hasSystem<EffectSystem>()) world.addSystem(effects);
  effects.scheduleEffect(
    entity: door,
    effect: MoveEffect(
      to: Vector3(200, 0, 0),
      durationTicks: 60, // effects count fixed steps, not seconds
      easing: EasingType.easeInOutQuad,
    ),
  );
}
```

The sprite, animator and timeline systems are in `DefaultSystems.all` (`DefaultSystem.sprites`), or add them with `registerSpriteSystems(world)`. A motion authored once and reused — a door opening, a coin bobbing — is a timeline asset played by `TimelinePlayerComponent(timelinePath: ...)`.

Scenes saved by pre-release 2.0 builds with an `AnimatedSpriteComponent` load as `SpriteAnimationComponent` (format 3).

## Tags and targets

`TagComponent` held one string; it now holds a set, and the world keeps an index of them.

| 1.6 | 2.0 |
|---|---|
| `TagComponent('enemy')` | the same, or `TagComponent.of(['enemy', 'flying'])` |
| `tagComponent.tag` | `tagComponent.tags`, `has(tag)`, `add`, `remove` (`tag` is removed) |
| `entity.getComponent<TagComponent>()?.tag == 'enemy'` | `entity.hasTag('enemy')` |
| scanning `world.entities` for a tag | `world.allTagged('enemy')`, `world.findTagged('player')` |
| `CheckpointSystem(playerTag: 'player')`, `DialogueSystem(playerTag: ...)` | unchanged; the default is `EngineTags.player` (`'player'`) |

```dart
final enemy = world.createEntityWithComponents([
  TransformComponent(),
  TagComponent.of(['enemy', 'flying']),
]);
enemy.addTag('boss');
final bosses = world.allTagged('boss'); // active entities with the tag
final player = world.findTagged(EngineTags.player);
debugPrint('${bosses.length} bosses; player: ${player?.name}');
```

Components that point at another entity take an `EntityTarget`: `EntityTarget.name('Player')`, `EntityTarget.tag('player')` (every entity with the tag, where several make sense) or `EntityTarget.self()`.

## Rendering

### Render hooks

`RenderingEngine.onRenderOverlay` and `onRenderBackground` held one function each, and the first writer won. They are now chains (`overlayHooks`, `backgroundHooks`), so a game, a plugin and the world can all draw. The old names are removed.

In 1.6, `GameWidget` drew the world only when `onRenderOverlay` was unset, so a game that set it called `engine.world.render` from its own hook. In 2.0 `GameWidget` always adds the world's hook itself: remove that call, or the world draws twice.

Before (1.6):

```dart
// 1.6
engine.rendering.onRenderOverlay = drawMinimap;
```

After (2.0):

```dart
void drawMinimap(Canvas canvas, Size size) {
  // ...
}

void addMinimap(Engine engine) {
  // Lower order draws first. Remove it with overlayHooks.remove(drawMinimap).
  engine.rendering.overlayHooks.add(drawMinimap, order: 50);
}
```

`backgroundHooks` works the same way, behind the world. Both chains draw in screen space, outside the camera transform.

### Debug drawing takes a camera

`Collider2DDebuggerSystem` (1.6's `ColliderDebuggerSystem`) and `CheckpointSystem` draw collider outlines and checkpoint radii. Without the camera the `RenderSystem` uses, they land at their world coordinates read as screen pixels. Pass it:

```dart
final camera = engine.camera.mainCamera;
engine.world
  ..addSystem(Collider2DDebuggerSystem(camera: camera))
  ..addSystem(CheckpointSystem(camera: camera));
```

Checkpoint radii are drawn in debug builds only. `Physics2DSystem` draws nothing: collider outlines come from a `Collider2DDebuggerSystem` in the world, and only while it is there. `GameWidget(showDebug: true)` adds one through the main camera; the editor adds its own while it shows colliders. It outlines every collider as simulated, coloured by body kind, every 2-D character and every body made outside the ECS, above everything else; `outlineFilter` picks the entities, and a collider's `showDebugOutline: false` hides its own.

### The legacy render path

Drawing outside the ECS is gone in 2.0:

| Removed | Use instead |
|---|---|
| `engine.rendering.addRenderable(r)` / `removeRenderable(r)` | an entity with `RenderableComponent(renderable: r)`; `RenderSystem` draws it in layer order |
| `addManagedEmitter(e)` / `removeManagedEmitter` / `updateManagedEmitters` | an entity with `ParticleEmitterComponent(emitter: e, removeEntityWhenComplete: true)`, and `ParticleSystem` in the world |
| `engine.parallax`, `ParallaxSystem` | an entity with `ParallaxComponent(background: ...)`; `ParallaxRenderSystem` (a default system) scrolls and draws it |
| `useSpatialIndex`, `markSpatialIndexDirty`, `markLayerOrderDirty`, `renderables`, `renderableCount`, `layerCount` | `RenderSystem(cullOffscreen: true)`; nothing else is needed |
| `RectangleRenderable`, `CircleRenderable`, `LineRenderable` | an entity with `Rectangle2DComponent`, `Circle2DComponent` or `Line2DComponent`, or a `CustomRenderable` in a `RenderableComponent` |
| `engine.rendering.spriteBatchFactory` | `RenderSystem(spriteBatchFactory: ...)` |

```dart
void addBackgroundAndSparks(World world, ParallaxBackground sky) {
  world.createEntityWithComponents([ParallaxComponent(background: sky)]);
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(200, 300, 0)),
    ParticleEmitterComponent(
      emitter: ParticleEmitter(
        maxParticles: 64,
        forces: [const GravityForce(Offset(0, 300))],
      ),
      removeEntityWhenComplete: true,
    ),
  ]);
  if (!world.hasSystem<ParticleSystem>()) {
    world.addSystem(ParticleSystem()); // not a default system
  }
}
```

`RenderSystem` now draws `ParticleEmitterComponent` emitters itself (1.6 drew none): an emitter goes on an entity.

`ParticleEmitter.shape`, `ParticleEmitter.gravity` and `ParticleShape` (deprecated in 1.6) are removed: pass `renderer:` (for example `SquareParticleRenderer()`) and `forces: [GravityForce(...)]`.

### Draw order

`RenderSystem` sorts ECS entities by their `LayerComponent` (layer, then z-order); an entity without one sorts by its renderable's own `layer` and `zOrder` (layer 0, z-order 0 when it has no renderable). Ties go by the order the entities were made in, so they do not swap from frame to frame, nor when another entity is destroyed. 1.6 drew them in archetype order, which shifted as components were added and removed. Give entities a `LayerComponent` where order matters.

## Scenes and saving

The 1.6 scene graph — `SceneEditor`, `Scene`, `SceneNode`, `GameObject`, `SceneGraph` and `engine.sceneEditor` — is removed. A scene's hierarchy is its entities (`ParentComponent` / `ChildrenComponent`). Levels are JSON scene files, read with `SceneLoader`:

```dart
Future<List<Entity>> loadLevel(Engine engine) =>
    SceneLoader.loadAsset(engine.world, 'assets/scenes/level_01.scene.json');
```

Nothing is created until the whole scene decodes, and a scene written by a newer engine is refused with an `UnsupportedFormatVersionException`. `SceneEditor` files held a node tree and no entities; there is nothing in them to load.

## Localization

`LocalizationManager.instance` is gone. Each engine holds its manager in `engine.context.localization`; `GameWidget` puts a `LocalizationScope` for it around everything it draws, so widgets under it read it with `LocalizationScope.of(context)` or `context.t(...)`.

Before (1.6):

```dart
// 1.6
LocalizationManager.instance = l10n;
final label = LocalizationManager.instance!.t('ui.back');
```

After (2.0):

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart'; // context.t, LocalizedText

Future<void> setUpLocalization(Engine engine) async {
  final l10n = LocalizationManager();
  await l10n.loadAll(const [
    Locale('en'),
    Locale('fr'),
  ], 'assets/l10n/ui_{locale}.json', ns: 'ui');
  engine.context.localization = l10n; // before building the GameWidget
}

class BackLabel extends StatelessWidget {
  const BackLabel({super.key});

  @override
  Widget build(BuildContext context) => Text(context.t('ui.back'));
}
```

## Assets

The asset manager belongs to the engine's context (`engine.assets`, there before `initialize()`). Loaders that used the shared one take it as a parameter:

| 1.6 | 2.0 |
|---|---|
| `Sprite.fromAsset(path)` | `Sprite.fromAsset(path, assets: engine.assets)` |
| `Sprite.loadImageFromAsset(path)` | `Sprite.loadImageFromAsset(path, assets: engine.assets)`; the caller owns the returned image |
| `SpriteAtlas.fromAsset(jsonPath)` | `SpriteAtlas.fromAsset(jsonPath, assets: engine.assets)` |
| `SpriteAtlasPage.loadImage()` | `SpriteAtlasPage.loadImage(engine.assets)` |
| `AssetBundle` (the engine's) | `GameAssetBundle` |

```dart
Future<Sprite> loadHero(Engine engine) =>
    Sprite.fromAsset('assets/sprites/hero.png', assets: engine.assets);
```

## Imports

`package:just_game_engine/just_game_engine.dart` is still the one import for the engine. Two things changed.

**Widgets moved to their own library.** Add `import 'package:just_game_engine/widgets.dart';` for `DialogueBox`, `DialogueChoices`, `SubtitleOverlay`, `LocalizedText`, `LocaleSelector`, `LocalizationBuilder`, the `BuildContextLocalization` extension (`context.t` / `context.tr`), `GameCameraControls`, and the `just_inputs` widgets (`OnScreenControls`, `OnScreenVisibility`, `OnScreenButtonFace`, `OnScreenStickPainter`, `RebindList`, `RebindButton`, `RebindRow`, `rebindRows`, `BindingLabel`). `GameWidget`, `GameLayers`, `LocalizationScope` and `GameTerminal` stay in the main library.

**Re-exports are lists.** 1.6 re-exported all of `just_dart`, `just_memory` and `just_audio_engine`. 2.0 re-exports only what the engine's own API uses:

| Package | Still re-exported | Import the package for |
|---|---|---|
| `just_inputs` | `InputService`, `InputActionAsset`, `InputActions`, `InputActionMap`, `InputAction`, the devices, players, rebinding and control-path names, the look input and the pointer lock (43 in all) | the asset model (`ActionMapDef`, `InputActionDef`, `ControlBindingDef`, …), `validateAsset`, `findBindingConflicts`, the interaction, processor and composite registries |
| `just_dart` | `Vector2`, `Vector3`, `Matrix4`, `JustMatrix4`, `Quaternion`, `Aabb3`, `Ray3`, `Plane`, `Frustum` | `Quadtree` |
| `just_memory` | `MemoryScope`, `DisposeCallback`, `MemoryProfiler`, `MemoryProfileSnapshot`, `MemoryStats`, `CacheBudgetStats`, `PoolManager`, `PoolStats`, `ArenaStats`, `MemoryCleanupResult`, `SystemMemorySnapshot` | `ObjectPool`, `PriorityPool`, `RoundRobinPool`, `Recyclable`, `MemoryArena`, `TypedBuffer`, `BudgetedCache`, `RefCountedRegistry`, `LeakTracker`, … |
| `just_audio_engine` | `AudioEngine`, `MusicManager`, `SoundEffectManager`, `AudioChannel`, `AudioClip`, `AudioBus`, `AudioBusGraph`, `AudioEffect`, `AudioEffectType`, `AudioState`, `AudioStream`, `AudioBackend`, `Audio3DListener`, `Audio3DPosition`, `AudioSpatial`, `AudioRolloff`, `AudioSpatialMix` | `createAudioBackend` |
| `just_physics_engine` | `Physics2DEngine`, `Box2DPhysicsEngine`, `Physics2DBody`, the shapes (`Circle2DShape` … `RoundedPolygon2DShape`), the joints (`DistanceJoint2D`, `MouseJoint2D`, `WeldJoint2D`, `RevoluteJoint2D`, `Box2DJoint`), `Ray2D`, `Ray2DHit`, `CircleCast2DHit`, `Body2DType`, `OneWayDirection`, `Ground2DState`, `Mover2DShape` and a few more (25 in all) | the 3-D side (through `package:just_game_engine/just_game_engine_3d.dart`), `CharacterMover2D`, `PhysicsEngineFactory`, the testing engines, the pure-Dart engine's insides (`CollisionDetector`, `CollisionManifold`, `ForceManager`, `SpatialGrid`, `BodyPair`) |
| `just_game_engine_formats` | `SceneFormat`, `SceneManifest`, `SceneNames`, `SceneStarters`, `SceneMigrationResult`, `TimelineFormat`, `AnimatorGraph` and its parts, the migration hook types, the prefab and 2-D material file types and `UnsupportedFormatVersionException` (40 in all; the 3-D library adds `Material3DFile` and its enums) | the migration steps themselves (`V0ToV1` … `V10ToV11`, `SceneMigrations`, `TimelineV1ToV2`, `TimelineV2ToV3`); `SceneFormat` and `TimelineFormat` run them |
| `just_signals` | `Signal`, `Computed` (new in 2.0: the reactive wrappers return them) | `Effect`, `SignalBuilder`, `SignalScope`, … |

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_memory/just_memory.dart' show ObjectPool;

final bullets = ObjectPool<Vector2>(create: Vector2.zero, maxSize: 256);
```

Add the package to your `pubspec.yaml` as well. A file that imported `package:just_game_engine/src/...` directly must follow files that moved; import the library instead.

## Storage and the cache

- **The engine keeps its own file.** Its key-value store was the same `just_storage.json` as the app's; two writers on one file could drop each other's keys. It is now `<application support>/just_game_engine/just_storage.json` (on the web, keys under `just_game_engine/`). The engine's keys move there once, on the first launch of 2.0. A `CacheManager` you build yourself chooses both stores with `openStorage` and `openSharedStorage`. An app store instance that had already read the shared file before the move may write the engine's old keys back when it next saves; they are inert and can be deleted.
- **Cache keys have a prefix.** Strings and JSON live under `just_game_engine.cache/`, and `CacheManager.clearAll()` clears only those, so the app's keys and the players' key bindings (under `just_game_engine.settings/`) survive it. Any string is a valid key. Entries written with `setString` / `setJson` before 2.0 are left in place but no longer read: write them again, or read them from your own store.
- **Bundle assets are no longer copied into the cache.** An app update's new images and JSON show at once. The copies 1.x wrote are removed on the first launch of 2.0.
- `ImageAsset.data` is null once the image is decoded.

## Behaviour you may notice

- **Destroying an entity destroys its children.** `destroyEntity(entity, withChildren: false)` keeps them and clears their parent link. `CommandBuffer.destroy`, `HealthSystem` and `LifetimeSystem` do the same. The destroyed entity also leaves its parent's `ChildrenComponent`.
- **Entity ids are never reused**, not even after `destroyAllEntities`, so state kept by id cannot attach to a newer entity. A stale handle passed to `destroyEntity` is ignored.
- **`Component.onDetach` always runs**: on destroy, on `destroyAllEntities`, on `World.dispose`, and when a component is replaced by another of its type.
- **Switching `isActive` takes effect at once**: cached queries refresh, and `MovementSystem` skips inactive entities.
- **A switched-off parent switches off its subtree.** Queries, tag lookups and the engine's systems go by `Entity.isActiveInHierarchy`; each child keeps its own `isActive`. Code walking `queryArchetypes` checks `archetype.entityAt(row).isActiveInHierarchy`.
- **Parenting an entity under itself or its own descendant throws an `ArgumentError`**; a scene whose parents loop loads with the closing link cut.
- **Systems** of equal priority run in the order they were added; adding a system twice does nothing; systems and plugins may be added or removed while they run.
- **`Entity.components`** is an unmodifiable `List`. `Archetype.getColumn` and `entityIds` are `@internal`.
- **Interpolation**: `RenderSystem` draws between the last two poses every transform whose previous pose was captured in the last step (`captureCount`) — physics bodies and their children — instead of every entity with a `Physics2DBodyRefComponent`; call `capturePrevious()` before moving something in a step to have it drawn smoothly.
- **While paused**, `engine.time.totalTime` and `deltaTime` stand still (`unscaledDeltaTime` and `unscaledTotalTime` go on), audio still updates, and camera effects (`ScreenFadeEffect`, `LetterboxEffect`) run on real time.
- **In the background** `GameWidget` pauses the music and the world's sounds and mutes the rest, and restores exactly that when the app returns (`Engine.suspendAudio` / `resumeAudio`).
- **Profiling timings** (`systemTimesMs`, `lastUpdateMs`) are taken only while `World.profiling` / `SystemManager.profiling` are on — not in release builds.
- **`CommandBuffer.flush`** runs every command, then rethrows the first error. An `EventBus` listener cancelled during a dispatch is not called for that event.
- **Physics events** are per pair of entities: a chain or compound collider sends one enter and one exit, an end and a begin in the same update cancel, and a body rebuilt because its collider, scale or sensor flag changed keeps its contacts (no second enter; an exit only if it no longer touches). A destroyed or switched-off entity still ends its contacts with no exit. Scale changes smaller than `BodyRebuild.scaleTolerance` (1e-4, relative) do not rebuild a body. A static sensor no longer reports static colliders on native Box2D.
- **2-D joints**: `DistanceJoint2DComponent` and `WheelJoint2DComponent` `stiffness` is in hertz and `damping` a damping ratio on every backend; slider and wheel axes are in the joint entity's space; with `collideConnected` off, jointed bodies send no contact events between them.
- **2-D bodies**: a kinematic `RigidBody2DComponent` moved through its transform carries what stands on it (it is driven by velocity, like 3-D, instead of teleported); torque and angular impulses turn a body by its rotational inertia; view culling freezes bodies on native Box2D too, and 2-D characters; a capsule stretches with the entity's scale; an angle read back from native Box2D no longer wraps at ±π.
- **3-D animation**: `AnimationPlayerComponent.speed` / `loop` are what was authored and saved; to change how a new clip plays, set `playingSpeed` / `playingLoop` after `play()`, not before. The clip fading out keeps the values it had. `CameraState.lerp` extrapolates for t outside 0..1, so blends with overshooting curves overshoot. `ParticleEmitter.isComplete` is false while sub-emitters live.
- **Sprites**: a tint colour with alpha below 1 now fades the sprite (use an opaque tint for the old look). The built-in shapes' renderables are on layer 0 (they were on 8, which the ECS never read); an entity without a `LayerComponent` is ordered by its renderable's `layer` and `zOrder`.
- **Timelines**: activation and sprite-clip blocks that run to the very end of a `once` timeline hold there, as the timeline left them. A camera shot block that runs to the end is the exception: it is released when the timeline finishes, so the camera goes back to gameplay (a ping-pong timeline turning there keeps it).
- **Dialogue**: `!` binds tighter than comparisons (`!$a == $b` is `(!$a) == $b`); bare words in conditions are errors (false, logged) instead of strings; selecting an unavailable choice leaves the choices up, and a set of choices with none available is skipped, as if it were not there, instead of stopping the dialogue.
- **Localization**: files for a locale with a script code load from `<name>_zh_Hans.json`; tables for the same locale and namespace merge.
- **Scenes with a value of the wrong type** fail with a `FormatException` naming the entity, component and field. `AssetManager` keeps assets by path and type; `unload(path)` unloads every type at the path, and `get<T>(path)` returns the `T` loaded there.
- **`CommandBuffer` applies commands in the order they were queued** (it used to run every destroy first).
- **`World.dispose()`** calls each system's `onRemovedFromWorld()` before its `dispose()`, highest priority first.
- **`findEntityByName`** is indexed and takes `includeInactive`.
- **A collider grows and shrinks with its entity's scale**, a body built without `drag` is not slowed by the air, and damping never slows a kinematic body ([physics bodies](#physics-bodies)).
- **Bounciness, damping and friction changed while the game runs take effect on desktop and mobile too**; before, the native Box2D body kept what it was made with.
- **The collider outline turns with its body**, and colours it by its type: static blue, kinematic orange, dynamic green, sensor yellow.
- **Collider outlines are off unless asked for**: they are drawn only while a `Collider2DDebuggerSystem` is in the world — `GameWidget(showDebug: true)` adds one, or `engine.world.addSystem(Collider2DDebuggerSystem(camera: engine.camera.mainCamera))`. `outlineFilter` picks the entities, and a collider's `showDebugOutline: false` hides its own.
- **`World.entities`** is a snapshot, cached until the next create or destroy.
- **Draw order** follows `LayerComponent` (see [Rendering](#draw-order)).
- **Sprite batches** sample with each sprite's own `filterQuality`; a mirrored, non-uniformly scaled or stretched sprite draws unbatched and correctly.
- **A `ParentComponent` is the whole hierarchy link**: the world keeps the parent's `ChildrenComponent` in step, and a link made with local values places the child at them (see [The transform hierarchy](#the-transform-hierarchy)).
- **Particles**: wind and noise forces give the same values on every platform, which differ from 1.x, and move their time on once per frame (1.x moved it once per particle, so turbulence sped up with the particle count). A force of your own whose field changes over time keeps its clock in the new `ParticleForce.advance(dt)`, which the emitter calls once per update before any particle, not in `apply`. Lifetime sub-emitters fire for every particle; an emitter's `shader` is applied.
- **`CollisionEnter2DEvent.depth`** is always 0, and its `point` is worked out from where the two bodies' bounds meet: 1.x's own solver filled them in, and no physics backend reports them with a contact.
- **`ShakeEffect`** ends exactly where it started; it used to leave the entity `amplitude` units up, and a looping shake drifted.
- **Shader effects** (`ShaderComponent`, post-process passes, emitter shaders) are skipped, with one log line, where `ImageFilter.shader` is not supported (the web, Skia) instead of throwing every frame.
- **`GameWidget`** resumes on returning to the foreground only if the app lifecycle paused the game, never a pause the player chose. Given an engine that is still initializing, it starts drawing it once it is ready; it does nothing with an engine that was disposed under it.
- **`GameLoop`** is driven by the ticker's timestamps, and `interpolation` stays between 0 and 1.
- **Audio on the web** starts at the first key or pointer press (see `EngineConfig.deferAudioUntilInput`).
- **Dialogue**: a repeating trigger fires once per entry, not every frame. `DialogueComponent.isInDialogue` follows the entity's runner, so `autoAdvance` works, and a `DialogueTriggerComponent`'s `autoAdvance` / `autoAdvanceDelay` are honoured.
- **Audio**: a source placed in 3-D (`is3D`) is no longer panned as well, and `AudioStreamComponent.fadeInDuration` fades in from silence. A sound effect plays on its component's `channel` (1.x played every one on sfx). `AudioSystem` stops a source's sound when the component or its entity goes, and plays nothing before the audio engine has started: a one-shot asked for before then is dropped. Where the listener and 3-D sources are is read once per rendered frame: the `audio` task is a frame task, run last, and is no longer in `engine.performanceStats['systemTimesMs']`.
- **Log lines**: the engine's lifecycle lines (initialized, started, a system registered, disposed, …) print only in debug builds; warnings and errors print in every build.
- **Malformed** localization and dialogue files are logged instead of being treated as missing.

The [CHANGELOG](CHANGELOG.md) lists every other fix.

## Removed APIs

| Removed | Use instead |
|---|---|
| `RigidBody`, just_physics_engine's shapeless point mass (gone in its 2.0.0) | a `RigidBody2DComponent` on an entity, or a `Physics2DBody` |
| `Engine.instance`, `Engine.resetInstance()` | the `Engine` you made |
| `engine.sceneEditor`, `SceneEditor`, `Scene`, `SceneNode`, `GameObject`, `SceneGraph` | entities, `SceneLoader` |
| `engine.animation`, `AnimationSystem`, `Animation`, `SpriteAnimation`, `TweenAnimation` and the five tweens, `AnimationSequence`, `AnimationGroup`, `AtlasSpriteAnimation`, `SpriteAtlas.createAnimation` | `SpriteAnimationComponent`, effects, timelines |
| `AnimationStateComponent`, `AnimationSystemECS`, `SpriteComponent.frame` | `SpriteAnimationComponent`; `SpriteComponent(atlasPath:, region:)` |
| top-level `linear`, `easeInQuad`, …, `EffectEasings` | `Easings.*`, `EasingType.transform` |
| `engine.network`, `NetworkManager`, `NetworkServer`, `NetworkClient`, `NetworkSync`, `NetworkProtocol`, `SessionManager` | none; they were stubs |
| `engine.achievements`, `auth`, `leaderboard`, `currency`, `inventory`, `ads` as engine fields, and their classes | `just_game_services` |
| `SteamAuthProvider`, `EpicGamesAuthProvider`, `SteamLeaderboardProvider`, `EpicGamesLeaderboardProvider` | your own `AuthProvider` / `LeaderboardProvider` |
| `InputManager`, `KeyboardInput`, `MouseInput`, `TouchInput`, `TouchPoint`, `ControllerInput`, `GamepadButton`, `GamepadAxis`, `MouseButton`, `ButtonMapping` | `engine.input` (`InputService`) |
| `VirtualJoystick`, `JoystickInputComponent`, `JoystickAxis`, `JoystickInputAxis`, `JoystickInputLayout`, `JoystickVariant` | on-screen controls in the input asset, `OnScreenControls` |
| `InputComponent.moveDirection`, `buttons`, `isButtonPressed`, `setButton`; `InputSystem.buttonMappings` | `InputComponent.vector`, `isDown`, `wasPressed`, …; the input asset |
| `Camera.follow`, `shake`, `addTrauma`, `trauma`, `worldBounds`, `useSpring`, `springStiffness`, `springDamping`, `smoothing`, `smoothingFactor`, `maxShakeOffset`, `maxShakeAngle`, `traumaDecayRate`, `velocity`, `update`, the `smooth:` parameters | [Cameras](#cameras) |
| `CameraSystem.addBehavior`, `removeBehavior`, `clearBehaviors`, `getBehavior`; `CameraBehavior`, `SpringFollowBehavior`, `LookaheadBehavior`, `MultiTargetBehavior`, `RoomBehavior`, `CameraRoom`, `PathBehavior`, `CameraPath`, `CameraKeyframe`, `CinematicBehavior`, `CinematicSequence`, `CinematicKeyframe` | [Cameras](#cameras) |
| `CameraFollowComponent`, `CameraFollowSystem` | `VirtualCameraComponent`, `CameraFramingComponent` |
| `RaycastSystem` (`castRay`, `castRayAll`, `hasLineOfSight`), `RaycastColliderComponent`, `RaycastHit`, `RayTracer`, `RayTrace`, `RayTraceSegment` | rays through the physics: `physicsSystem.queries` (`Physics2DQueries`: `raycast`, `raycastAll`; `Physics2DHit`), and `RayTracer2D`, `RayTrace2D`, `RayTrace2DSegment` for bounces off `Collider2DComponent.reflectivity` ([Physics bodies](#physics-bodies)) |
| `TileMapLayerComponent`, `TiledObjectComponent`, `TileMapRenderSystem`, `TiledCollisionSystem`, `TiledMapFactory`, `ComponentMapper` | `LevelMapComponent`, `LevelMapSystem`, `MapCollisionSystem`, `TiledInterop` |
| `TextComponent`, `ButtonComponent`, `UIComponent` | `just_ui_editor` |
| `LinearProgressComponent`, `CircularProgressComponent` | `just_ui_editor`'s `UiProgressComponent`, or a Flutter widget |
| `PhysicsBridgeSystem` | `Physics2DSystem(engine.physics)` |
| `PhysicsSystem.gravity`, `broadPhaseCellSize` | `engine.physics.setGravity(x, y)` |
| `PhysicsBodyComponent` | `RigidBody2DComponent` and `Collider2DComponent` ([physics bodies](#physics-bodies)) |
| `CollisionEvent`, `ContactExitEvent`, `SensorEnterEvent`, `SensorExitEvent` | `CollisionEnter2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent`, `SensorExit2DEvent` ([physics bodies](#physics-bodies)) |
| `ReactiveTransformComponent`, `ReactiveVelocityComponent`, `ReactiveHealthComponent` | `TransformSignals`, `ComponentSignal`, or the `ReactiveComponent` mixin on your own component |
| `ParticleEmitter.shape`, `ParticleEmitter.gravity`, `ParticleShape` | `renderer:`, `forces: [GravityForce(...)]` |
| `LocalizationManager.instance` | `engine.context.localization`, `LocalizationScope.of(context)` |
| `EffectSerializer.registerFactory` | `engine.context.effectTypes.register` |
| `Archetype.addEntity`, `Archetype.removeEntity` (now internal) | add and remove components on the entity |
| `entity.addComponent(AudioPlayComponent(clipPath: c, …))` | `world.getSystem<AudioSystem>()?.playOneShot(c, position: …, …)` |
| `AudioPauseComponent`, `AudioResumeComponent`, `AudioStopComponent` | `source.pause()`, `source.resume()`, `source.stop()` on the `AudioSourceComponent` or `AudioStreamComponent`; `source.play()` plays it again from the start (setting `playOnAdd` no longer does: the system never changes that field) |
| `TimelineAudio.viaComponent` | `TimelineAudio.viaAudioSystem` |
| `World.structureVersion` | `world.queryVersion(types)` for the queries your system reads (the largest of several) |
| `PlayerScratch`, `samplePlayer` (from `just_game_engine_3d.dart`) | nothing: they were the renderer's helpers |
| `AudioListenerComponent.forwardX`, `forwardY`, `forwardZ`, `upX`, `upY`, `upZ` | the entity's rotation; `atCamera` and `faceCamera` to hear from the camera, or face like it |
| `RenderingEngine.addRenderable`, `removeRenderable`, `renderables`, `renderableCount`, `layerCount`, `markLayerOrderDirty`, `markSpatialIndexDirty`, `useSpatialIndex` | entities with a `RenderableComponent`; `RenderSystem(cullOffscreen: true)` for culling ([The legacy render path](#the-legacy-render-path)) |
| `RenderingEngine.addManagedEmitter`, `removeManagedEmitter`, `updateManagedEmitters` | an entity with `ParticleEmitterComponent(emitter: e, removeEntityWhenComplete: true)`, and `ParticleSystem` in the world |
| `RenderingEngine.onRenderOverlay`, `onRenderBackground` | `overlayHooks`, `backgroundHooks` ([Render hooks](#render-hooks)) |
| `Engine.parallax`, `ParallaxSystem` | an entity with a `ParallaxComponent`, drawn by `ParallaxRenderSystem` |
| `TagComponent.tag` | `tags`, `has`, `add`, `remove`; `entity.hasTag` ([Tags and targets](#tags-and-targets)) |
| `HierarchySystem` | nothing: every world keeps its hierarchy itself ([The transform hierarchy](#the-transform-hierarchy)) |
| `Entity.generation`, `Entity(generation:)` | nothing: ids are never reused; `world.isEntityAlive(entity)` checks a held handle |
| `ILifecycle`, `IUpdatable`, `IRenderable`, `IPausable`, `IEnableable`, `LifecycleStateMixin` | nothing: the engine never used them |
| `ViewCullingSystem(gridCellSize:)` | leave the argument out |
| `RectangleRenderable`, `CircleRenderable`, `LineRenderable` | `Rectangle2DComponent`, `Circle2DComponent`, `Line2DComponent`, or a `CustomRenderable` ([The legacy render path](#the-legacy-render-path)) |
| `RenderingEngine.spriteBatchFactory` | `RenderSystem(spriteBatchFactory: ...)` |
| `SpriteSheet`, `SpriteSheet.fromAsset` | an atlas: `SpriteAtlas.fromAsset(jsonPath, assets: engine.assets)` (TexturePacker, Aseprite, or a grid sheet's JSON, read by `GridSheetAtlasParser`) and `SpriteAnimationComponent` |
| `ParallaxLayer.repeat` | `repeatX`, `repeatY` |
| `offload`, `offloadUnit` | Flutter's `compute` |
| `typedef UpdateCallback`, `RenderCallback` | `void Function(double)`, `VoidCallback` |
| `VelocitySignals`, `HealthSignals` | `ComponentSignal` over the field you show |
| `YarnTokenizer`, `YarnToken`, `TokenType`, `ExpressionEvaluator` (now internal) | `YarnParser` |

### Removed in 2.0.0-dev.4

For code built on an earlier 2.0 dev release; 1.6 had none of these.

| Removed | Use instead |
|---|---|
| `PhysicsJointBindingSystem` | nothing: `Physics2DSystem` makes the 2-D joints itself, in the step their bodies are in (`DefaultSystem.physics` adds only it) |
| `Physics2DSystem(camera:)`, `.camera`, `.drawsOutlines`, `.outlineFilter`, `.render`, `Physics2DSystem.debugPaintFor` | a `Collider2DDebuggerSystem(camera:, outlineFilter:)` in the world; its `paintFor(rigid, [body])` |
| `Physics2DSystem.contactPoint`, `jointedPair`; `ColliderGeometry.visualKeyOf` | nothing (internal); compare `SolidShape2DSource.solidShape2D` |
| `typedef FrameCallback` | `FrameTask` |
| `TrackBindingKind` | `EntityTargetKind` |
| `RaycastSystem` (`castRay`, `castRayAll`, `hasLineOfSight`), `RaycastColliderComponent`, `RaycastHit`, `RayTracer`, `RayTrace`, `RayTraceSegment` | `physicsSystem.queries` (`Physics2DQueries`) against the physics colliders; `RayTracer2D(queries).trace(origin, direction, …)` for bounces, off a collider's saved `reflectivity` ([Physics bodies](#physics-bodies)) |
| `ColliderDebuggerSystem(color:, includeRaycastColliders:)`, the ray colliders' colour and switch | nothing: there are no ray colliders, and `Collider2DDebuggerSystem` colours bodies by kind |
| `RenderingEngine.debugSpriteBatchCount` | `RenderSystem.stats['batchedSprites']` |
| `MaterialOverridesFieldType.all` | `Material2DDefinitions.overridesType` and `Material3DDefinitions.overridesType` |
| the migration steps (`V0ToV1` … `V10ToV11`, `SceneMigration`, `SceneMigrations`, `TimelineV1ToV2`, `TimelineV2ToV3`, `TimelineMigration`) from the engine's library | `SceneFormat` and `TimelineFormat` run them; import `package:just_game_engine_formats/just_game_engine_formats.dart` to name one |
| `UnknownFieldType`, `PropertyTrackRunner`, `ShapePaintCache`, `Material2DBatch`, `ShapeSheet`, `ShapeSheets`, `ShapeValues`, `Primitive3DComponent.writeShapeValues` / `writeMaterialValues`, `cameraForward`, `cameraAnglesOf` (now internal) | `FieldTypes.unknown`; `CameraState.forward` |
| from `just_game_engine_3d.dart`: `RenderView`, `GpuSurface` and the rest of the GPU plumbing, `NullGpuDevice` and the test doubles, `gltfToEngine` and model cooking; `PhysicsEngineFactory`, `Body3DPoses` | `package:just_graphics_engine/just_graphics_engine.dart` and `package:just_physics_engine/physics_3d.dart` directly (`RenderView` clashed with Flutter's) |

## Renamed APIs

| 1.6 | 2.0 |
|---|---|
| `AssetBundle` (the engine's) | `GameAssetBundle` (it clashed with Flutter's) |
| `typedef Easing` | `EasingFunction` (it clashed with Flutter's) |
| `TransformComponent.rotation` | `angle` |
| `TransformComponent.rotationX`, `rotationY` | `eulerX`, `eulerY` |
| `TransformComponent.prevRotation` (`double`) | `prevAngle` |
| `TransformSignals.rotation` | `TransformSignals.angle` |
| `ParentComponent.localOffset` | `localPosition` |
| `EngineState.error` | `EngineState.failed` |
| `Engine.getSystem<T>()` | `Engine.subsystem<T>()` |
| `SystemPriorities.tileMap` | `SystemPriorities.levelMap` |
| `PhysicsSystem` | `Physics2DSystem`: 2-D and 3-D twins are named `X2DSystem` and `X3DSystem` (its constructor changed too: see [Systems](#systems)) |
| just_physics_engine 1.x's types, re-exported by the engine: `PhysicsEngine`, `PhysicsBody`, `CollisionShape`, `CircleShape` … `RoundedPolygonShape`, `BodyType`, `Ray`, `RayBodyHit`, `JointConstraint`, `DistanceJoint`, …; `engine.physics.castRay`, `castRayAll`, `castCircle` | just_physics_engine 2.0's: `Physics2DEngine`, `Physics2DBody`, `Shape2D`, `Circle2DShape` … `RoundedPolygon2DShape`, `Body2DType`, `Ray2D`, `Ray2DHit`, `Joint2D`, `DistanceJoint2D`, …; `raycast`, `raycastAll`, `circleCast` (the rows of [Renamed in 2.0.0-dev.4](#renamed-in-200-dev4), and just_physics_engine's CHANGELOG, list them all). Saved body types and one-way directions are unchanged |
| `ParticleSystemECS` | `ParticleSystem` |
| `EffectSystemECS` | `EffectSystem` |
| `CameraSystem`, `engine.cameraSystem` | `CameraEngine`, `engine.camera` (it is not an ECS system) |
| `Camera` (the output camera) | `OutputCamera` (`engine.camera.mainCamera`; `GameCamera` is still the interface systems draw through) |
| `ColliderDebuggerSystem` | `Collider2DDebuggerSystem` |
| `AudioSourceComponent.is3d` | `is3D`; saved scenes are renamed as they load (format 11) |
| `DialogueBoxWidget`, `DialogueChoicesWidget` | `DialogueBox`, `DialogueChoices` |
| the extensions `ReactiveEntityExtension`, `ReactiveWorldExtension`, `L10nContext` | `EntityReactive`, `WorldReactive`, `BuildContextLocalization` |
| `Renderable.getBounds()`, `Asset.getMemoryUsage()`, `Camera.getVisibleBounds()`, `AssetManager.getCacheStats()`, `SystemManager.getSystemNames()`, `getSystems()` | the getters `bounds`, `memoryUsage`, `visibleBounds`, `cacheStats`, `systemNames`, `systems` |
| `CustomRenderable(getBoundsCallback: …)`, `MotionBlurEffect(velocityFn: …)` | `boundsOf:`, `velocity:` |
| `CircleComponent`, `RectangleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent` | `Circle2DComponent`, `Rectangle2DComponent`, `Polygon2DComponent`, `Line2DComponent`, `Capsule2DComponent`; saved scenes are renamed as they load (format 11) |
| `DistanceJointComponent`, `WeldJointComponent`, `PrismaticJointComponent`, `WheelJointComponent` (pre-release 2.0, not in 1.6) | `DistanceJoint2DComponent`, `FixedJoint2DComponent`, `SliderJoint2DComponent`, `WheelJoint2DComponent` ([physics bodies](#physics-bodies)) |

### Renamed in 2.0.0-dev.4

For code built on 2.0.0-dev.1 to dev.3; the names on the left were never in 1.6, except just_physics_engine's. Saved scenes, prefabs and timelines are renamed as they load (scene format 11, timeline format 3), so only code changes.

| 2.0.0-dev.3 | 2.0.0-dev.4 |
|---|---|
| `RigidBody2D`, `Collider2D`, `CharacterBody2D`, `Joint2D`, `DistanceJoint2D`, `FixedJoint2D`, `SliderJoint2D`, `WheelJoint2D`, the same with `3D`, `CameraCollision3D` | the same with `Component` at the end (`RigidBody2DComponent`, …, `CameraCollision3DComponent`) |
| `Light2D`, `Lighting2D`, `ShadowCaster2D`, `Material2D`, `ScreenMaterial`, `MaterialOverrides3D`, `PrefabLink`; the 3-D `LightComponent` | `Light2DComponent`, `Lighting2DComponent`, `ShadowCaster2DComponent`, `Material2DComponent`, `ScreenMaterialComponent`, `MaterialOverrides3DComponent`, `PrefabLinkComponent`; `Light3DComponent` |
| `Primitive3D`, `Cube3D`, `Sphere3D`, … `Polygon3D` | `Primitive3DComponent`, `Cube3DComponent`, `Sphere3DComponent`, … `Polygon3DComponent` |
| `PhysicsSystem3D`, `AnimationSystem3D` | `Physics3DSystem`, `Animation3DSystem` |
| `PhysicsDefinitions2D`, `ShapeDefinitions2D`, `PhysicsCharacters2D`, `PhysicsHit2D`, `PhysicsHit3D` | `Physics2DDefinitions`, `Shape2DDefinitions`, `Physics2DCharacters`, `Physics2DHit`, `Physics3DHit` |
| `ColliderShapes3D`, `ColliderGeometry3D`, `AssetColliderGeometry3D`, `ColliderGeometry` | `Collider3DShapes`, `Collider3DGeometry`, `AssetCollider3DGeometry`, `Collider2DGeometry` |
| `GraphicsSchemas`, `ShapeSchemas`, `Physics3DSchemas`; `Graphics3D.registerSchemas`, `Physics3D.registerSchemas` | `Graphics3DDefinitions`, `Shape3DDefinitions`, `Physics3DDefinitions`; `registerDefinitions` |
| `CoreDefinitions`, `CoreComponentSchemas`, `registerCoreCodecs`, `refreshCoreCodecs`; `ComponentDefinitionRegistry.core()` | each feature's own (`EcsDefinitions`, `Shape2DDefinitions`, `GameplayDefinitions`, …), listed by `BuiltInComponents.all` and installed by `BuiltInComponents.extension`; `BuiltInComponents.registry()` |
| `ComponentSchema<T>(…, id: …)`, `SchemaField` | `ComponentDefinition<T>(…, id: …)`, `FieldDefinition` |
| `ColliderShape2D`, `CharacterShape2D`, `ColliderShape3D`, `LightKind` | `Collider2DShape`, `CharacterBody2DShape`, `Collider3DShape`, `Light3DKind` (the saved values are unchanged) |
| `MaterialLibrary`, `MaterialFile`, `MaterialKind`, `MaterialAlpha`, `MaterialUv` | `Material3DLibrary`, `Material3DFile`, `Material3DKind`, `Material3DAlpha`, `Material3DUv` |
| `MigrationResult` | `SceneMigrationResult` |
| `MapOrientation` | `LevelMapOrientation` |
| `FrameSystem` | `PerFrame` |
| `TimelineContext` (a track's view of its playback) | `TrackContext` |
| `CameraBrainSystem(cameraSystem:)` | `CameraBrainSystem(cameraEngine:)` |
| `Light2DComponent.colour`, `castsShadows`; `MapLayerData.castsShadows` | `color`, `castShadows`; `castShadows` |
| `Physics2DSystem.entityForBody` | `entityOf` |
| `Material2DShader.isColour`, `colour(…)`; `MapLayerPainter.casterColour`; `Material2DValue.colour`, `Material2DFile.colour(key)` | `isColor`, `color(…)`; `casterColor`; `color`, `color(key)` |
| `TimelineTriggerComponent.onEnter`, `onExit` | `enterAction`, `exitAction` |
| `SpriteAnimationComponent.initialized`, `TimelinePlayerComponent.initialized`, `CameraRigMemory.initialized` | `isInitialized` |
| `PrefabLibrary.of(context)`, `Material2DLibrary.of(context)`, `RenderProviders.of(context)`, `CameraRegistries.of(context)` | `context.prefabLibrary`, `context.material2DLibrary`, `context.renderProviders`, `context.cameraRegistries` |
| `Physics2DSystem.massOf`, `autoMassPerSquareUnit` | `Collider2DGeometry.massOf`, `autoMassPerSquareUnit` |
| `Physics2DSystem.scaleTolerance`, `Physics3DSystem.scaleTolerance` | `BodyRebuild.scaleTolerance` |
| `PhysicsJointBindingSystem.dartSpring` | `Physics2DJoints.dartSpring` |
| `Physics2DDefinitions.bodyTypeDescription`, `layerDescription`, `frictionDescription`, … | `PhysicsDefinitions.bodyTypeDescription`, … (shared with 3-D) |
| `Physics2DQueries(engine.physics, physicsSystem)` | `physicsSystem.queries`, or `Physics2DQueries(physicsSystem)` |
| `ColliderDebuggerSystem` | `Collider2DDebuggerSystem` |
| `GraphicsSceneRenderer(engine: …)` | `Graphics3DSceneRenderer(world: () => world, …)` |
| `FieldTypes.physicsLayer`, `physicsLayerMask`, `physicsShape` | `PhysicsDefinitions.layerType`, `layerMaskType`, `shapeType` |
| `MaterialOverridesFieldType.material2D`, `.material3D` | `Material2DOverridesFieldType` (`Material2DDefinitions.overridesType`), `Material3DOverridesFieldType` (`Material3DDefinitions.overridesType`) |
| `UnknownComponentTypeException.builtInHint(type)` | the exception's `hint`, from `ComponentDefinitionRegistry.unknownTypeHint(type)` |
| `CameraDefinitions.framing`, `confiner`, `bounds`, `noise`, `targetGroup`, `trigger`, `dolly`, `orbitFollow`, … | `CameraFramingDefinitions`, `CameraNoiseDefinitions`, `CameraTargetDefinitions`, `CameraManagerDefinitions`, `CameraRig3DDefinitions` (`CameraDefinitions` keeps `virtualCamera` and `all`) |
| `AssetManager.release(path)`, `refCount(path)` | `release(path, type)`, `refCount(path, type)` |
| `ReactiveComponent.propertySignal(name, initialValue)` | `propertySignal(name, () => value)` |
| `DefaultSystem.sprites` (sprites, animators and timelines) | `DefaultSystem.sprites`, `DefaultSystem.animation`, `DefaultSystem.timelines` |
| `EngineConfig(graphics3D: …, physics3D: …)`; `package:just_game_engine/graphics_3d.dart`, `physics_3d.dart` | `EngineConfig(services: [Graphics3D(), Physics3D()])`; `package:just_game_engine/just_game_engine_3d.dart` |
| `GraphicsShapes.linear` | `LinearColor.of` |
| `Camera` | `OutputCamera` (`CameraEngine.mainCamera`, `engine.camera` and the `GameCamera` interface keep their names) |
| `GraphicsModels`, `GraphicsModelAsset`, `GraphicsModelLoader`, `GraphicsSceneRenderer`, `GraphicsShapes`; `ContextGraphicsModels.graphicsModels` | `Graphics3DModels`, `Graphics3DModelAsset`, `Graphics3DModelLoader`, `Graphics3DSceneRenderer`, `Graphics3DShapes`; `ContextGraphics3DModels.graphics3DModels` (`graphics3D.models` and `graphics3D.sceneRenderer` keep their names) |
| `CameraCollisionStage` | `CameraCollision3DStage` |
| just_physics_engine 1.x (1.6 used these too): `PhysicsEngine`, `PhysicsBody`, `CollisionShape`, `CircleShape`, `PolygonShape`, `RectangleShape`, `CapsuleShape`, `SegmentShape`, `ChainShape`, `RoundedPolygonShape`, `BodyType`, `Ray`, `RayBodyHit`, `ShapeCastResult`, `GroundState2D`, `MoverShape` | just_physics_engine 2.0.0: `Physics2DEngine`, `Physics2DBody`, `Shape2D`, `Circle2DShape`, `Polygon2DShape`, `Rectangle2DShape`, `Capsule2DShape`, `Segment2DShape`, `Chain2DShape`, `RoundedPolygon2DShape`, `Body2DType`, `Ray2D`, `Ray2DHit`, `CircleCast2DHit`, `Ground2DState`, `Mover2DShape` |
| `JointConstraint`, `JointType`, `DistanceJoint`, `MouseJoint`, `WeldJoint`, `RevoluteJoint`; a joint's `type` | `Joint2D`, `Joint2DKind`, `DistanceJoint2D`, `MouseJoint2D`, `WeldJoint2D`, `RevoluteJoint2D` (just_physics_engine's joints, which the components in the first row drive); its `kind` |
| `engine.physics.castRay`, `castRayAll`, `castCircle` | `raycast`, `raycastAll`, `circleCast` |
| 3-D, from just_physics_engine: `PhysicsEngine3D`, `PhysicsWorld3D`, `PhysicsWorldSettings3D`, `PhysicsEvent3D`, `BodyType3D`, `BodySettings3D`, `JointKind3D`, `JointSettings3D`, `MotorState3D`, `SixDofAxisMode3D`, `MotionQuality3D`, `CharacterSettings3D`, `CharacterState3D`, `GroundState3D`, `QueryFilter3D`, `QueryHit3D`, `BoxShape3D` … `CompoundShape3D`; `FakePhysicsEngine3D`, `FakePhysicsWorld3D` | `Physics3DEngine`, `Physics3DWorld`, `Physics3DWorldSettings`, `Physics3DEvent`, `Body3DType`, `Body3DSettings`, `Joint3DKind`, `Joint3DSettings`, `Motor3DState`, `SixDofAxis3DMode`, `Motion3DQuality`, `Character3DSettings`, `Character3DState`, `Ground3DState`, `Query3DFilter`, `Query3DHit`, `Box3DShape` … `Compound3DShape`; `FakePhysics3DEngine`, `FakePhysics3DWorld` (saved values unchanged) |
| `PhysicsBodyRefComponent` | `Physics2DBodyRefComponent` (never saved) |
| `PhysicsShapeFieldType` | `Shape2DFieldType` (its id is still `physicsShape`) |

## Deprecated APIs

None. The members earlier 2.0 dev releases kept as deprecated were removed before 2.0.0: they are in [Removed APIs](#removed-apis).

## Known limitations in 2.0.0

These wait on `just_physics_engine` and `just_audio_engine`. The fields involved are saved as usual, so scenes need no change when the limits lift.

- **Joint anchors.** `anchor` / `connectedAnchor` of `DistanceJoint2DComponent` and `FixedJoint2DComponent` (and a slider's) are not passed to the physics engine: a distance joint holds the bodies by their centres, and a fixed joint holds them as they were when joined. A wheel joint's axle anchor is honoured on native Box2D only. The editor's inspector hides the anchors the backends ignore; their saved values are kept.
- **`collideConnected`.** Jointed bodies with `collideConnected` off send no contact events between them, but on the pure-Dart backend (the web) they still push each other apart.
- **Queries on native Box2D** skip bodies whose collision mask is 0; the Dart backend finds them.
- **3-D collision layers.** Which layers a 3-D world keeps apart is fixed when the world is made (with the first 3-D body): a collision grid changed while a 3-D scene plays reaches the next world made, not this one. A body's own `layer` can change at any time.
- **Stream channels.** `AudioStreamComponent.channel` is handed to the stream, but the channel's volume does not apply to it. A playing sound's pitch, pan, speed and loop cannot change, and a stream that plays to its end still reports `isPlaying`.

## Saved data

- **Scenes** carry a `version`; the current format is 11 (`SceneFormat.current`; it was 9 in 2.0.0-dev.1 and 10 in dev.2 and dev.3). `SceneLoader` migrates an older file in memory, one step at a time from format 0 (files with no `version`) to 11, before creating anything. Format 8 is the physics body's: `isStatic` becomes `bodyType`, category and mask bits a layer and its list, and the shape of a scaled entity is divided by its scale so its collider, which now follows the scale, stays the size it was — a note names each one. Format 9 splits each body into a rigid body and a collider (saved then as `RigidBody2D` / `Collider2D`), writing out every setting the old defaults gave it (so it plays the same under the new ones), and renames the joints and their fields. Format 10 lets a scene entry place a prefab file. Format 11 gives every component type a name ending in `Component`, with `2D` / `3D` where a type has a twin (`RigidBody2D` → `RigidBody2DComponent`, `CircleComponent` → `Circle2DComponent`), and renames the fields whose 2-D and 3-D twins were named differently: a 2-D light's `colour` and `castsShadows` (`color`, `castShadows`), a sound's `is3d` (`is3D`), a timeline trigger's `onEnter` and `onExit` (`enterAction`, `exitAction`) and a 2-D material's override keys (`tint.colour` → `tint.color`), in prefab instances too (`V10ToV11.renames` and `renamedFields`, in just_game_engine_formats, list them). Nothing on disk changes until the file is saved again, or until `just game scene migrate` rewrites it. `SceneFormat.migrateWithReport` runs the same migration and says what it changed (`SceneMigrationResult.notes`) and which sprites need an atlas (`SceneMigrationResult.needsAtlas`).
- **Timelines** carry `formatVersion` 3 and are migrated the same way (`TimelineFormat.migrate`); format 3 keys a renamed component and a renamed field under its new name, as scene format 11 does (a 2-D light's `colour` is `color`, its `castsShadows` `castShadows`; a sound's `is3d` is `is3D`). A track `binding` saved as a bare string reads the way `EntityTarget.parse` reads one: `"#door"` is a tag, `"Door"` a name and `"self"` the timeline's own entity. Pre-release 2.0 builds bound every bare string to the timeline's own entity. What the engine writes (`"self"`, `{"name": ...}`, `{"tag": ...}`) reads as before.
- **Animator graphs** (`.animator.json`) carry `version` 2, written as 1 when a graph uses nothing version 2 added (crossfading transitions, blend trees). A graph saved by a newer engine is refused with an `UnsupportedFormatVersionException`; a file without `version` reads as version 1.
- **Level maps, tilesets, the tag library, the physics layers (`assets/project/physics.json`), prefab files and 2-D and 3-D material files** have format numbers too. Level maps are format 3, where a layer's `castsShadows` is `castShadows`, and 2-D material files format 2, where a colour value is keyed `color` (`tint.color`, `dissolve.edgeColor`); older ones read, and are written in the new form. A file from a newer engine is refused with an `UnsupportedFormatVersionException` rather than loaded with data dropped.
- **Game services** data stays in the `jge_engine` database, as in 1.x.
- **The engine's own keys** move to its own storage file on the first launch (see [Storage and the cache](#storage-and-the-cache)).

To rewrite a project's files in the current formats, run the migration and save the result. The platformer template ships this as `tool/migrate_assets.dart` (run it with `flutter test tool/migrate_assets.dart`); the core of it is:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart';

void migrateScene(File file, EngineContext context) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (SceneFormat.versionOf(json) >= SceneFormat.current) return;
  final result = SceneFormat.migrateWithReport(
    json,
    hooks: context.migrations, // a package's own migration rules
  );
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(result.scene),
  );
  for (final note in result.notes) {
    stdout.writeln('${file.path}: $note');
  }
}
```

Make the `EngineContext` with the extensions your game installs, so their migrations run too: `EngineContext(extensions: const [MyGameExtension()])`. Review the diff before committing it.
