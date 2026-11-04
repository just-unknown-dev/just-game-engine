# Engine & lifecycle

_Core_ · Create an Engine, configure it with EngineConfig, take it through initialize, start and dispose, and reach its subsystems, game loop and context.

An `Engine` is an ordinary Dart object. You make one per game session, give it an `EngineConfig`, await `initialize()`, call `start()`, and dispose it when the game is over. It owns the world, the subsystems (rendering, physics, input, audio, storage, cameras) and the game loop.

## Create an engine

Build and initialize the engine before `runApp`, so the first frame already has a game to draw:

```dart lib/main.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize(); // builds the subsystems and the world
  engine.start(); // starts the game loop

  runApp(MaterialApp(home: Scaffold(body: GameWidget(engine: engine))));
}
```

When the game is one screen of a larger app, let that screen's `State` own the engine. `dispose()` returns a `Future`, but it tears the engine down before its first `await`, so not awaiting it in `State.dispose` is safe:

```dart lib/game_page.dart
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

  @override
  void initState() {
    super.initState();
    engine.initialize().then((_) => engine.start());
  }

  @override
  void dispose() {
    unawaited(engine.dispose()); // final: this engine cannot start again
    super.dispose();
  }

  // GameWidget may be built before initialize() finishes: it starts
  // drawing and ticking the engine as soon as it is ready.
  @override
  Widget build(BuildContext context) => GameWidget(engine: engine);
}
```

## EngineConfig

Everything that shapes an engine is set once, in the `EngineConfig` you pass to the constructor.

| Field | What it does |
|---|---|
| `defaultSystems` | The engine's standard systems to add while it initializes. Empty by default, so a world starts with no systems. |
| `extensions` | `ContextExtension`s to install: a package's component definitions, migrations and registries. |
| `services` | `EngineService`s started with the engine, in the order listed, and stopped with it. 3-D is two of them: `services: [Graphics3D(), Physics3D()]` from `package:just_game_engine/just_game_engine_3d.dart` (see [3D graphics](/docs/graphics-3d) and [3D physics](/docs/physics-3d); Physics3D also needs `hooks: user_defines: just_jolt: build: true`). Without them a game is 2-D only. |
| `createRendering` | Builds your own `RenderingEngine` subclass instead of the standard one. |
| `createAudio` | Builds the `AudioEngine`, for example with `AudioEngine.withBackend(...)`. |
| `createPhysics` | Builds the 2-D `Physics2DEngine`. Null gives Box2D on native platforms and the pure-Dart engine on the web. |
| `deferAudioUntilInput` | Starts audio at the first key or pointer press. Null means on the web only. |

`initialize(config: ...)` still accepts a config and replaces the constructor's, for code written for 1.x. Prefer `Engine(config: ...)`.

## The lifecycle

`engine.state` is an `EngineState`: `uninitialized`, `initializing`, `initialized`, `running`, `paused`, `failed`, `disposing` or `disposed`. `engine.stateListenable` notifies on every change, and `isInitialized` (true while initialized, running or paused), `isRunning`, `isPaused` and `isDisposed` answer the common questions.

| Call | Works in | Anywhere else |
|---|---|---|
| `initialize()` | `uninitialized`, `failed` | Returns the running Future while `initializing`; throws a `StateError` on a ready or disposed engine. |
| `start()` | `initialized` | Throws a `StateError`. |
| `pause()` | `running` | Does nothing. |
| `resume()` | `paused` | Does nothing. |
| `stop()` | `running`, `paused` (back to `initialized`) | Does nothing. |
| `dispose()` | any state | A second call returns the same Future. |

`initialize()` builds the engine in stages: core, cache, input, audio, physics, rendering, world, subsystems and services. If a stage throws, everything built so far is undone, the state becomes `failed`, and an `EngineInitException` is thrown and kept in `engine.lastError`. Its `stage` names the stage (`service:<Type>` for a service) and `cause` holds the original error. You may then call `initialize()` again.

```dart
try {
  await engine.initialize();
} on EngineInitException catch (e) {
  debugPrint('The engine failed at ${e.stage}: ${e.cause}');
}
```

The subsystem getters throw `EngineNotReadyError` (a `StateError` naming the member and the state) before `initialize()` has built them and after `dispose()`. Disposal is final: to play again, make a new `Engine()`.

> **Note:** An audio failure during initialization is logged, not fatal: the game runs without sound. This is what happens in tests and on platforms without the audio plugin.

## Default systems

`EngineConfig.defaultSystems` takes a set of `DefaultSystem` values. Each adds:

| `DefaultSystem` | Systems |
|---|---|
| `input` | `InputSystem` (the `player` map's actions onto each `InputComponent`) |
| `physics` | `Physics2DSystem` (bodies, the joints between them, characters) |
| `movement` | `MovementSystem` |
| `audio` | `AudioSystem` |
| `rendering` | `RenderSystem`, `ParallaxRenderSystem` |
| `sprites` | `SpriteLoadSystem`, `SpriteAnimationSystem` |
| `animation` | `AnimatorSystem` |
| `timelines` | `TimelineTriggerSystem`, `TimelineSystem` |
| `levelMaps` | `LevelMapSystem` |
| `mapCollision` | `MapCollisionSystem` |
| `cameras` | `CameraTargetGroupSystem`, `CameraTriggerSystem`, `CameraBrainSystem` |

`DefaultSystems.all` is every one. `DefaultSystems.headless` leaves out `rendering` and `audio`, for a server, a simulation or a test.

`registerDefaultSystems(world, engine, include: ...)` adds the same systems to any world. It skips a system type the world already has, so you can add your own configured instance first. Add these yourself when you use them: `ParticleSystem`, `EffectSystem`, `PostProcessSystem`, `HealthSystem`, `LifetimeSystem`, `CheckpointSystem`, `DialogueSystem`, `ViewCullingSystem`, `BoundarySystem`, `SimpleMovementSystem` and `FlowFieldSystem`. The 3-D services add their own systems as they start: `Graphics3D` adds `Animation3DSystem`, and `Physics3D` adds `Physics3DSystem` unless it is made with `addSystem: false`.

## Subsystems

These exist between `initialize()` and `dispose()`:

| Getter | Type | What it is |
|---|---|---|
| `engine.world` | `World` | Entities, components and systems; see [World, entities & systems](/docs/ecs). |
| `engine.rendering` | `RenderingEngine` | Draws the frame: background colour, render hooks, post-processing, `stats`. |
| `engine.physics` | `Physics2DEngine` | 2-D physics, stepped by `Physics2DSystem`; see [2D physics](/docs/physics-2d). |
| `engine.input` | `InputService` | Actions, devices and players; see [Input](/docs/input). |
| `engine.audio`, `engine.music`, `engine.sfx` | `AudioEngine`, `MusicManager`, `SoundEffectManager` | Sound; see [Audio](/docs/audio). |
| `engine.cache` | `CacheManager` | Strings, JSON and binary data kept between runs. |
| `engine.camera` | `CameraEngine` | The `mainCamera` and the camera `brain`; see [Cameras](/docs/cameras). |
| `engine.time` | `TimeManager` | Frame time, total time and `timeScale`. |
| `engine.gameLoop` | `GameLoop` | The fixed-step loop: `currentFPS`, `interpolation`, `fixedDeltaTime`. |
| `engine.systemManager` | `SystemManager` | Update tasks and their timings. |

These never throw `EngineNotReadyError`: `engine.config`, `engine.context`, `engine.assets` (the `AssetManager`), `engine.services`, `engine.plugins`, `engine.layers`, `engine.terminal`, `engine.cursor` and `engine.performanceStats`. After `dispose()`, read them but don't use them: the layers, the terminal and a context the engine made itself (with its `assets`) are disposed with the engine. `engine.graphics3D` and `engine.physics3D` (extensions in `just_game_engine_3d.dart`) return the `Graphics3D` and `Physics3D` services given in `EngineConfig.services`, or null for a 2-D game. `engine.subsystem<T>()` finds a subsystem by type, and returns null when there is none.

## The game loop

`GameWidget` calls `engine.gameLoop.tick()` once per display frame. The world then updates in fixed steps of 1/60 s (`engine.gameLoop.fixedDeltaTime`): none, one or several per frame. At most three steps' worth of time is carried over, so a stall does not snowball. The rate is fixed at 60 steps a second; `EngineConfig` has no setting for it.

- Every `System.update(deltaTime)` receives the fixed step times `engine.time.timeScale`. At a time scale of 0 the steps still run, with a `deltaTime` of 0. `engine.time.slowMotion()` and `fastForward()` set the scale for you.
- Move things by `deltaTime` in `update`. Don't read the wall clock.
- `engine.pause()` stops the steps. The screen still draws and input still updates every frame, so a pause menu keeps working. `resume()` drops the time that passed while paused instead of catching up.
- Drawing happens once per display frame, between steps. Moving physics bodies are drawn between their last two steps (`engine.gameLoop.interpolation`), so they stay smooth on a 120 Hz screen.

Each step runs the engine's update tasks in order: `input` and `ecs`. Particles update inside `ecs` (`ParticleSystem`). The `ecs` task is `world.update(deltaTime)`, and `Physics2DSystem` steps the physics inside it, so a velocity your system sets reaches the same step's simulation. Add a task of your own with `engine.systemManager.registerUpdateTask('autosave', (dt) { ... })`; it runs after the engine's, task names must be unique, and `unregisterUpdateTask` removes it.

After a frame's steps, systems that also implement `PerFrame` run their `frame(deltaTime, alpha)` once per rendered frame, for things that must move at the display's rate rather than the simulation's.

## EngineContext and extensions

`engine.context` is an `EngineContext`: everything one engine knows that is not a subsystem. It holds the component `definitions` and `fieldTypes` scenes are read with, the scene `migrations`, the asset `bundle` and the `assets` manager. Each feature adds its per-engine state as an extension on the context, kept in a slot:

- `animatorBindings` (`ContextAnimation`)
- `trackKinds`, `easings` and the timeline `signals` (`ContextTimeline`)
- `collisionKinds` and `tiles` (`ContextLevelMap`)
- `effectTypes` (`ContextEffects`)
- the project's `physicsLayers` (`ContextPhysics`)
- the game's `localization` (`ContextLocalization`)
- the `sprites` loader (`ContextSprites`), the `prefabs` loader and the `prefabLibrary` (`ContextPrefabs`), and the 2-D materials' `material2DText` loader and `material2DLibrary` (`ContextMaterials2D`)
- the camera stages and managers every brain runs, `cameraRegistries` (`ContextCameraRegistries`)
- with 3-D, `renderProviders` (`ContextRenderProviders`) and `graphics3DModels` (`ContextGraphics3DModels`), from `package:just_game_engine/just_game_engine_3d.dart`
- `overrideLoaders` and `useBundle` (`ContextLoaders`)

The engine makes the context in its constructor and installs `BuiltInComponents.extension` into it first, so you can fill it before `initialize()`.

`engine.world.context` is the same object. A second world that must read the engine's scenes is made with `World(context: engine.context)`; a bare `World()` makes a fresh context of its own, with only the ECS core's components (`World(extensions: [BuiltInComponents.extension])` adds the engine's).

A package, or your game, teaches an engine through a `ContextExtension`:

```dart
final class MyGameExtension implements ContextExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) {
    // An animator parameter can now be bound to "grounded".
    context.animatorBindings.register(
      'grounded',
      (entity) => entity.getComponent<RigidBody2DComponent>()?.isGrounded,
    );
  }
}

final engine = Engine(
  config: const EngineConfig(
    extensions: [MyGameExtension()],
    defaultSystems: DefaultSystems.all,
  ),
);
```

Extensions in the config are installed in the engine's constructor, after `BuiltInComponents.extension`, then every service that is also a `ContextExtension` (the 3-D services are). `install` runs once per context for each `id`; a second install of the same id is ignored. `context.install(extension)` and `context.isInstalled(id)` work at any time. To register your own components for scenes, see [Scenes & saving](/docs/scenes).

State a package keeps per engine goes in a slot: `context.slot<T>(key, create)` makes it on first use, and a value that implements `ContextResource` is disposed with the context. Nothing is process-wide, so two engines in one process never see each other's registrations.

## Services and plugins

An `EngineService` is something that starts as the engine initializes and stops when it is disposed: achievements, a wallet, your own telemetry. An `EnginePlugin` attaches to a running engine to observe it, like an editor or a profiler, and is called every frame even while the game is paused. Both are covered in [Services & plugins](/docs/services).
