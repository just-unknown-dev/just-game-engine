# Your first game

_Getting started_ · Draw shapes, move one, load a level from scene JSON, and learn the five things that trip people up.

This page takes you from an empty Flutter app to shapes on screen, a box that moves by itself, and a level loaded from JSON. It assumes the engine is in your `pubspec.yaml` ([Installation](/docs/installation)).

## The first game

Put this in `lib/main.dart` and run it:

```dart lib/main.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The engine's standard systems: input, physics, movement, audio,
  // rendering, sprites, level maps, map collision and cameras.
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize();

  // The camera's position is the world point in the middle of the screen.
  engine.camera.mainCamera
    ..lookAt(Offset.zero)
    ..zoom = 1.0;

  final world = engine.world;
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-150, 0, 0)),
    Circle2DComponent(
      radius: 40,
      fillStyle: const ShapePaintStyle(color: Colors.lightBlue),
    ),
  ], name: 'Sun');

  // +Y is down: this box drifts towards the bottom of the screen.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(150, -100, 0), angle: 0.3),
    VelocityComponent(velocity: Vector3(0, 40, 0)),
    Rectangle2DComponent(
      width: 120,
      height: 60,
      cornerRadius: 8,
      fillStyle: const ShapePaintStyle(color: Colors.orange),
    ),
  ], name: 'Box');

  engine.start();
  runApp(
    MaterialApp(
      home: Scaffold(body: GameWidget(engine: engine)),
    ),
  );
}
```

## What each part does

- **`EngineConfig(defaultSystems: DefaultSystems.all)`** adds the standard systems while the engine initializes. Without it the world starts with no systems, and nothing moves or draws. `DefaultSystems.headless` is the same set without rendering and audio, for servers and tests.
- **`await engine.initialize()`** comes before anything touches `engine.world`, `engine.physics`, `engine.input` or the other subsystems. Before that they throw `EngineNotReadyError`. If a stage fails, `initialize()` throws `EngineInitException` and undoes what it built.
- **An entity** is an id with components. `createEntityWithComponents` adds them in one go. The shape components (`Circle2DComponent`, `Rectangle2DComponent`, `Polygon2DComponent`, `Line2DComponent`, `Capsule2DComponent`) draw themselves.
- **`engine.start()`** starts the game loop. `GameWidget` drives it from Flutter's frame ticker, draws the world, and sends keys and pointers to `engine.input`. It shows an FPS counter unless you pass `showFPS: false`.
- **`Engine` is an ordinary object.** Make one per game session. When the game is one screen of a larger app, create it in a `State` and call `engine.dispose()` from `dispose()`. Disposal is final: to play again, make a new `Engine`.

## Five things that trip people up

### The world updates in fixed steps

`GameWidget` calls `engine.gameLoop.tick()` once per display frame. The world then updates in fixed steps of 1/60 s (`engine.gameLoop.fixedDeltaTime`): none, one or several per frame, with at most three steps' worth of time carried over, so a stall does not snowball. Every `System.update(deltaTime)` receives that fixed step times `engine.time.timeScale`.

- Move things in `update`, by `deltaTime`. Do not read the wall clock.
- Drawing happens once per display frame, between steps. Physics bodies and their children are drawn between their last two steps (`engine.gameLoop.interpolation`), so they stay smooth on a 120 Hz screen. Entities your own code moves are drawn where they are.
- `engine.pause()` stops the steps. The screen still draws and input still updates, so a pause menu keeps working.

### +Y is down

The axes are `WorldAxes`: +X right, +Y down, +Z into the screen. Gravity is +Y and a jump is -Y. A positive `angle` turns clockwise.

### TransformComponent is the world transform

Physics, cameras, timelines and your code all read and write `TransformComponent` in world space. A child's offset from its parent lives in its `ParentComponent` (`localPosition`, `localRotation`, `localScale`), and the world keeps the two in step every update. If you write a child's transform directly, its local offset is worked out again from where you put it.

```dart lib/turret.dart
import 'package:just_game_engine/just_game_engine.dart';

/// Hangs a turret on [tank], 30 units above its centre. From the next
/// update on it moves and turns with the tank.
Entity addTurret(World world, Entity tank) => world.createEntityWithComponents([
  TransformComponent(),
  // Where the turret sits in the tank's space. The next update places
  // it there, whatever its TransformComponent says now.
  ParentComponent(parentId: tank.id, localPosition: Vector3(0, -30, 0)),
  Rectangle2DComponent(width: 50, height: 12),
], name: 'Turret');
```

- The world keeps the other end of the link: the tank gets a `ChildrenComponent` listing the turret.
- Give a `ParentComponent` no local values and the child stays where its `TransformComponent` puts it. Scenes load their links this way.
- To move the turret on the tank later, change `localPosition` (for example `localPosition.y = -40`).
- Destroying the tank destroys the turret. Pass `withChildren: false` to `world.destroyEntity` to keep the children.

### Systems run by priority, highest first

Systems run in priority order, not in the order you add them. Set a system's priority before you add it; overriding the `priority` getter is simplest, for example `int get priority => SystemPriorities.playerControl;`. Systems of equal priority run in the order they were added. The main constants (all of them are in `SystemPriorities`):

| Priority | Constant | What runs |
|---|---|---|
| 110 | `levelMap` | Level maps load and update. |
| 108 | `mapCollision` | Bodies for map tiles. |
| 105 | `parallax` | `ParallaxRenderSystem` scrolls parallax backgrounds. |
| 100 | `input` | Actions copied onto `InputComponent`s. |
| 95 | `playerControl` | Your character controller: reads input, sets velocity. |
| 90 | `physics` | The physics step. |
| 80 | `movement` | Velocity onto transform, for entities without a body. |
| 70 | `animation` | Animators, sprite clips, timelines. |
| 65 | `effects` | `EffectSystem`: moves, fades, shakes. |
| 60 | `gameplay` | Health, lifetime, your game rules. |
| 50 | `hierarchy` | Children follow their parents. |
| 48 | `particles` | `ParticleSystem` advances the emitters. |
| 45 | `camera` | The camera brain frames the finished positions. |
| 40 | `render` | `RenderSystem`, which draws once per display frame. |
| -10 | `audio` | Sounds follow their entities. |

### One component of each type per entity

Adding a second component of a type replaces the first. Every shape and every sprite is stored as a `RenderableComponent`, so one entity draws one thing: put a second drawing on a child entity. Read a shape back with `entity.getComponent<RenderableComponent>()`; `getComponent<Circle2DComponent>()` finds nothing.

## Load a level from scene JSON

Levels are scene files: `assets/scenes/<name>.scene.json`, listed in play order in `assets/scenes/scenes.json` (for example `{ "scenes": ["level_01"] }`). Declare the folder under `flutter: assets:` in `pubspec.yaml`. The [level editor](/docs/editor) writes these files, but they are plain JSON, so you can write one by hand:

```json assets/scenes/level_01.scene.json
{
  "version": 11,
  "name": "level_01",
  "mode": "2d",
  "entities": [
    {
      "name": "Ground",
      "components": [
        { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 300, "z": 0 } } },
        { "type": "Rectangle2DComponent", "fields": { "width": 1200, "height": 40 } },
        { "type": "Collider2DComponent", "fields": { "shape": "matchShape" } }
      ]
    },
    {
      "name": "PlayerSpawn",
      "components": [
        { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 200, "z": 0 } } },
        { "type": "SpawnComponent", "fields": { "spawner": "player" } }
      ]
    },
    {
      "name": "MainCamera",
      "components": [
        { "type": "TransformComponent", "fields": {} },
        { "type": "VirtualCameraComponent", "fields": { "follow": { "tag": "player" } } },
        { "type": "CameraFramingComponent", "fields": { "screenY": 0.1 } }
      ]
    }
  ]
}
```

A spawn point names what to create; the game says how, with a `Spawner`. Load the level after `initialize()` and before `start()`:

```dart lib/level.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// What the level's spawn points can create.
final spawners = [
  Spawner(
    id: 'player',
    label: 'Player',
    tags: const {'player'}, // the tags the spawned entity carries
    spawn: (world, point) => world.createEntityWithComponents([
      // The spawn point's position; TransformComponent copies it.
      TransformComponent(
        position: point.getComponent<TransformComponent>()?.position,
      ),
      Rectangle2DComponent(
        width: 32,
        height: 48,
        fillStyle: const ShapePaintStyle(color: Colors.lightBlue),
      ),
      TagComponent('player'), // the scene's camera follows this tag
    ], name: 'Player'),
  ),
];

/// Loads the first scene in scenes.json into the engine's world.
Future<void> loadFirstLevel(Engine engine) async {
  final world = engine.world;
  final names = await SceneLoader.loadManifest(); // assets/scenes/scenes.json
  await SceneLoader.loadAsset(world, SceneAssets.pathFor(names.first));
  // Maps and their tile collision before the first frame, so nothing
  // falls through ground that is still loading.
  await LevelMaps.preload(world);
  SpawnPoints.spawnAll(world, spawners);
}
```

- **A field left out** keeps the component's default. A child names its parent with `"parentName"`, and `"enabled": false` loads an entity switched off.
- **Each component** is read through its `ComponentDefinition` in `engine.context`. The engine's own components always load. A package's components load once its `ContextExtension` is listed in `EngineConfig(extensions: [...])`; otherwise the load stops with an `UnknownComponentTypeException` naming the type and the entity.
- **Versions.** The current scene format is 11, where every component's name ends in `Component`; it was 10 in 2.0.0-dev.2 and dev.3, and 9 in 2.0.0-dev.1 (`SceneFormat.current`). Older files are migrated in memory as they load; a file from a newer engine throws `UnsupportedFormatVersionException`.
- **Without the asset bundle**, `SceneLoader.loadString` and `SceneLoader.load` take JSON text or a decoded map, which is handy in tests.

[Scenes](/docs/scenes) covers changing levels, your own components and migrations.
