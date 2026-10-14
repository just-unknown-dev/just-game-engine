# Just Game Engine — Quick Start

This guide takes a Flutter developer from an empty app to a small game: shapes on screen, a player you steer, physics, sprites, levels loaded from JSON, cameras, timelines, particles, sound and UI. Most steps have one complete Dart file: paste it into your project and call its functions from the `main` of step 2, after `await engine.initialize()`.

It is written for **just_game_engine 2.0.0** (Dart 3.12 and Flutter 3.44 or newer). Coming from 1.x? Read [MIGRATION.md](MIGRATION.md) first.

1. [Install](#1-install)
2. [Your first game](#2-your-first-game)
3. [Five things that trip people up](#3-five-things-that-trip-people-up)
4. [Input](#4-input)
5. [Physics](#5-physics)
6. [Sprites and animation](#6-sprites-and-animation)
7. [Levels](#7-levels)
8. [Cameras](#8-cameras)
9. [Timelines](#9-timelines)
10. [Tags, targets and spawn points](#10-tags-targets-and-spawn-points)
11. [Particles and effects](#11-particles-and-effects)
12. [Audio](#12-audio)
13. [UI over the game](#13-ui-over-the-game)
14. [Services](#14-services)
15. [Testing](#15-testing)
16. [When something does not work](#16-when-something-does-not-work)
17. [Where next](#17-where-next)

---

## 1. Install

Add the engine to `pubspec.yaml`, and list the folders your game loads assets from. The engine reads input actions, scenes, atlases, maps, timelines and sounds through the Flutter asset bundle, so each file must be listed, by itself or through its folder. A folder entry does not include its subfolders.

```yaml
dependencies:
  flutter:
    sdk: flutter
  just_game_engine: ^2.0.0

flutter:
  assets:
    - assets/input/
    - assets/scenes/
    - assets/sprites/
    - assets/maps/
    - assets/tilesets/
    - assets/timelines/
    - assets/audio/
```

```bash
flutter pub get
```

One import gives you the engine: `package:just_game_engine/just_game_engine.dart`. Optional ready-made widgets (on-screen controls, rebinding lists, dialogue boxes) are in `package:just_game_engine/widgets.dart` — see [step 13](#13-ui-over-the-game).

---

## 2. Your first game

```dart
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
  engine.cameraSystem.mainCamera
    ..lookAt(Offset.zero)
    ..zoom = 1.0;

  final world = engine.world;
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-150, 0, 0)),
    CircleComponent(
      radius: 40,
      fillStyle: const ShapePaintStyle(color: Colors.lightBlue),
    ),
  ], name: 'Sun');

  // +Y is down: this box drifts towards the bottom of the screen.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(150, -100, 0), angle: 0.3),
    VelocityComponent(velocity: Vector3(0, 40, 0)),
    RectangleComponent(
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

What each part does:

- **`EngineConfig(defaultSystems: DefaultSystems.all)`** adds the standard systems while the engine initializes. Without it the world starts with no systems, and nothing moves or draws. `DefaultSystems.headless` is the same set without rendering and audio (servers, tests).
- **`await engine.initialize()`** comes before anything touches `engine.world`, `engine.physics`, `engine.input` or the other subsystems. Before that they throw `EngineNotReadyError`. If a stage fails, `initialize()` throws `EngineInitException` and undoes what it built.
- **An entity** is an id with components. `createEntityWithComponents` adds them in one go. The shape components — `CircleComponent`, `RectangleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent` — draw themselves.
- **`engine.start()`** starts the game loop. **`GameWidget`** drives it from Flutter's frame ticker, draws the world, and sends keys and pointers to `engine.input`. It shows an FPS counter unless you pass `showFPS: false`.
- **`Engine` is an ordinary object.** Make one per game session. When the game is one screen of a larger app, create it in a `State` and call `engine.dispose()` from `dispose()`. Disposal is final: to play again, make a new `Engine`.

---

## 3. Five things that trip people up

**The world updates in fixed steps.** `GameWidget` calls `engine.gameLoop.tick()` once per display frame. The world then updates in fixed steps of 1/60 s (`engine.gameLoop.fixedDeltaTime`): none, one or several per frame, with at most three steps' worth of time carried over, so a stall does not snowball. Every `System.update(deltaTime)` receives that fixed step times `engine.time.timeScale`.

- Move things in `update`, by `deltaTime`. Do not read the wall clock.
- Drawing happens once per display frame, between steps. `RenderSystem` draws physics bodies interpolated between their last two steps (`engine.gameLoop.interpolation`), so they stay smooth on a 120 Hz screen. Entities your own code moves are drawn where they are.
- `engine.pause()` stops the steps. The screen still draws and input still updates, so a pause menu keeps working.

**+Y is down.** The axes are `WorldAxes`: +X right, +Y down, +Z into the screen. Gravity is +Y and a jump is −Y. A positive `angle` turns clockwise.

**`TransformComponent` is the world transform.** Physics, cameras, timelines and your code all read and write it in world space. A child's offset from its parent lives in `ParentComponent` (`localPosition`, `localRotation`, `localScale`). The world's transform hierarchy keeps the two in step every update. If you write a child's transform directly, its local offset is worked out again from where you put it.

```dart
import 'package:just_game_engine/just_game_engine.dart';

/// Hangs a turret on [tank], 30 units above its centre. From the next
/// update on it moves and turns with the tank.
Entity addTurret(World world, Entity tank) => world.createEntityWithComponents([
  TransformComponent(),
  // Where the turret sits in the tank's space. The next update places
  // it there, whatever its TransformComponent says now.
  ParentComponent(parentId: tank.id, localPosition: Vector3(0, -30, 0)),
  RectangleComponent(width: 50, height: 12),
], name: 'Turret');
```

The world keeps the other end of the link: the tank gets a `ChildrenComponent` listing the turret, made for it if it has none.

Give a `ParentComponent` no local values and the child stays where its `TransformComponent` puts it; its offset is worked out from that. Scenes load their links this way.

To move the turret on the tank later, change its `ParentComponent.localPosition` (for example `localPosition.y = -40`). Destroying the tank destroys the turret; pass `withChildren: false` to `world.destroyEntity` to keep the children.

**Systems run by priority, highest first** — not in the order you add them. The world sorts its systems each time one is added, so set a system's priority before adding it (overriding the `priority` getter is simplest). The constants are in `SystemPriorities`:

| Priority | Constant | What runs |
|---:|---|---|
| 110 | `levelMap` | level maps load and update |
| 108 | `mapCollision` | bodies for map tiles |
| 100 | `input` | actions copied onto `InputComponent`s |
| 95 | `playerControl` | your character controller: reads input, sets velocity |
| 90 | `physics` | the physics step |
| 80 | `movement` | velocity onto transform (entities without a body) |
| 70 | `animation` | animators, sprite clips, timelines |
| 65 | `effects` | deterministic effects |
| 60 | `gameplay` | health, lifetime, your game rules |
| 50 | `hierarchy` | children follow their parents |
| 48 | `particles` | particle emitters |
| 45 | `camera` | the camera brain frames the finished positions |
| 40 | `render` | `RenderSystem`, which draws in `render()`, once per display frame |
| −10 | `audio` | sounds follow their entities |

**One component of each type per entity.** Adding a second component of a type replaces the first. Every shape and every sprite is stored as a `RenderableComponent`, so one entity draws one thing: put a second drawing on a child entity. Read a shape back with `entity.getComponent<RenderableComponent>()`; `getComponent<CircleComponent>()` finds nothing.

---

## 4. Input

Actions and their bindings live in an input asset (a `just_inputs` file), not in code. This one has a `player` map with `move` and `jump`, and a `ui` map with `pause`.

`assets/input/game.input.json`:

```json
{
  "format": "just_inputs",
  "version": 3,
  "name": "game",
  "maps": [
    {
      "id": "m1",
      "name": "player",
      "actions": [
        {
          "id": "a1",
          "name": "move",
          "type": "vector2",
          "bindings": [
            {
              "id": "b1",
              "composite": "2DVector",
              "parts": [
                { "id": "b2", "part": "up", "path": "<Keyboard>/w" },
                { "id": "b3", "part": "down", "path": "<Keyboard>/s" },
                { "id": "b4", "part": "left", "path": "<Keyboard>/a" },
                { "id": "b5", "part": "right", "path": "<Keyboard>/d" }
              ]
            },
            { "id": "b6", "path": "<Gamepad>/leftStick" }
          ]
        },
        {
          "id": "a2",
          "name": "jump",
          "type": "button",
          "bindings": [
            { "id": "b7", "path": "<Keyboard>/space" },
            { "id": "b8", "path": "<Gamepad>/buttonSouth" }
          ]
        }
      ]
    },
    {
      "id": "m2",
      "name": "ui",
      "actions": [
        {
          "id": "a3",
          "name": "pause",
          "type": "button",
          "bindings": [
            { "id": "b9", "path": "<Keyboard>/escape" },
            { "id": "b10", "path": "<Gamepad>/start" }
          ]
        }
      ]
    }
  ]
}
```

`InputSystem` (a default system) copies each player's `player`-map actions onto every entity with an `InputComponent`, by action name. Gameplay code reads names and never asks which device was used:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_game_engine/just_game_engine.dart';

/// Loads the actions. Call after `engine.initialize()`.
Future<void> loadInput(Engine engine) async {
  final text = await rootBundle.loadString('assets/input/game.input.json');
  engine.input.loadAsset(InputActionAsset.parse(text));
  // Gamepads are opt-in: attaching them opens platform channels.
  await engine.input.attachGamepads();

  // Actions outside the player map are read from the service. Input keeps
  // updating while the engine is paused, so this can also resume it.
  engine.input.actions.action('ui/pause').onPerformed((_) {
    engine.isPaused ? engine.resume() : engine.pause();
  });
}

/// Moves every entity that has an InputComponent, top-down style.
class WalkSystem extends System {
  static const double speed = 240;

  // After InputSystem (100) has copied the actions in.
  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [InputComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final input = entity.getComponent<InputComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>()!.velocity;
      final move = input.vector('move'); // y is down, like the world
      velocity.x = move.dx * speed;
      velocity.y = move.dy * speed;
      if (input.wasPressed('jump')) debugPrint('${entity.name} jumps');
    });
  }
}

Entity addPlayer(World world) => world.createEntityWithComponents([
  TransformComponent(),
  VelocityComponent(),
  InputComponent(), // player 1
  RectangleComponent(width: 32, height: 48),
], name: 'Player');
```

In `main`, after `initialize()`: `await loadInput(engine);`, `engine.world.addSystem(WalkSystem());`, `addPlayer(engine.world);`.

- `InputComponent` has `vector`, `axis`, `isDown`, `wasPressed`, `wasReleased` and `wasPerformed`. `wasPressed` is true for one step only.
- Local co-op: `engine.input.players.start()` lets players join, and `InputComponent(playerIndex: 1)` reads player 2.
- Rebinding (`rebindPlayer`, or the ready-made `RebindList` in `widgets.dart`) saves a player's own bindings in the engine's cache. To read them back at the next start, call `await engine.input.players.preloadOverrides()` after `loadAsset`.

---

## 5. Physics

Physics in 2-D is the same model as in 3-D, with a `2D` suffix: a `RigidBody2D` says how a body moves, a `Collider2D` gives it its shape. A collider alone is a static body. `PhysicsSystem` (a default system) steps `engine.physics`, writes the results back to the entity's `TransformComponent` and `VelocityComponent`, and fires events on `world.events`.

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void buildPlayground(Engine engine) {
  // +Y is down. The default, 981, is real gravity at 1 unit = 1 cm, which
  // feels floaty in a platformer.
  engine.physics.setGravity(0, 2000);
  final world = engine.world;

  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 200, 0)),
    RectangleComponent(
      width: 900,
      height: 40,
      fillStyle: const ShapePaintStyle(color: Colors.brown),
    ),
    // Static ground: a collider is enough. Match shape follows the rectangle.
    Collider2D(shape: ColliderShape2D.matchShape),
  ], name: 'Ground');

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
    RectangleComponent(width: 80, height: 80, filled: false),
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

/// A platformer body: no bounce, no spin, no drag, no grip on walls.
Entity addPlatformer(World world) => world.createEntityWithComponents([
  TransformComponent(),
  VelocityComponent(),
  InputComponent(),
  RectangleComponent(width: 32, height: 48),
  RigidBody2D(friction: 0, lockRotation: true),
  Collider2D(size: Vector2(32, 48)),
  TagComponent('player'),
], name: 'Player');

/// Runs and jumps, but only jumps from the ground.
class PlatformerSystem extends System {
  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [
    InputComponent,
    VelocityComponent,
    RigidBody2D,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final input = entity.getComponent<InputComponent>()!;
      final body = entity.getComponent<RigidBody2D>()!;
      final velocity = entity.getComponent<VelocityComponent>()!.velocity;
      velocity.x = input.vector('move').dx * 260;
      if (body.isGrounded && input.wasPressed('jump')) {
        velocity.y = -800; // up is -Y
      }
    });
  }
}
```

In `main`, with the input of step 4 loaded: `buildPlayground(engine);`, `engine.world.addSystem(PlatformerSystem());`, `addPlatformer(engine.world);`.

A character can also be moved by gameplay rather than by the simulation: a `CharacterBody2D` (3-D's `CharacterBody3D`). It walks slopes up to `maxSlopeAngle`, climbs steps up to `stepHeight`, keeps to the floor going down, rides moving platforms and stands on one-way platforms — and needs no rigid body or collider of its own.

```dart
Entity addCharacter(World world) => world.createEntityWithComponents([
  TransformComponent(),
  InputComponent(),
  RectangleComponent(width: 32, height: 48),
  CharacterBody2D(shape: CharacterShape2D.box, width: 32, height: 48),
  TagComponent('player'),
], name: 'Hero');

/// Runs and jumps a CharacterBody2D.
class CharacterControlSystem extends System {
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

A character's own body is kinematic, so sensors see it and dynamic bodies bump into it; it touches static ground through the mover, not through contacts — read `groundEntity` for what it stands on.

- Collider shapes (`Collider2D.shape`): `box` (`size`, optional `cornerRadius`), `circle` (`radius`), `capsule` (`radius`, `height`), `polygon` (`points`), `segment` and `chain` (`points`, `loop`), and `matchShape` — whatever the entity draws (a rectangle, circle, polygon or sprite), followed as it changes. Centred on the entity unless `offset` moves them; `rotation` and `scale` turn and stretch the collider itself. It also grows and shrinks with the entity's scale, as its sprite does.
- Rigid bodies are dynamic by default. `bodyType: BodyType.static` never moves; `BodyType.kinematic` moves only by the velocity you set (moving platforms). On the collider, `oneWay: true` makes a platform you can jump up through.
- The defaults are the same as in 3-D: `friction: 0.5`, `restitution: 0` (no bounce), `mass: 0` (worked out from the collider's area: a 100 × 100 box weighs 1000 kg, as a 1 m cube does in 3-D) and a little damping (`linearDamping: 0.05`, `angularDamping: 0.05`). Bounce comes from `restitution` on both bodies; give both some for a bouncy hit. A character usually wants `friction: 0` (so it slides down walls instead of sticking to them) and `lockRotation: true`.
- Collision layers: put a body on `layer: 1` to `15`, name the layers and say which collide in `assets/project/physics.json` (a `PhysicsLayers`; the editor's Physics Layers dock writes it), and list that file under `flutter: assets:`. A body's own `collidesWith` overrides the grid.
- `isGrounded`, `groundEntity`, `groundNormal`, `linearVelocity` and `angularVelocity` on `RigidBody2D` are kept up to date for you.
- Push from code with `addForce`, `addImpulse`, `addTorque`, `addAngularImpulse`, `setVelocity` and `setAngularVelocity`; they apply at the next step.
- Events: `CollisionEnter2DEvent` (the two entities, the contact `point` and `normal`) when a contact begins, `CollisionExit2DEvent` when it ends, `CollisionStay2DEvent` every step in between once you set `PhysicsSystem.reportContactStay`, and `SensorEnter2DEvent` / `SensorExit2DEvent` (`sensor` and `other`) for sensors.
- Queries: `Physics2DQueries(engine.physics, physicsSystem)` casts rays and circles and finds overlaps, filtered by layer.
- To teleport a body, write its `TransformComponent`. The physics system moves the body to match.
- Debug builds draw every collider's outline over the game; `showDebugOutline: false` on the collider hides one. Release builds never draw them.

---

## 6. Sprites and animation

`SpriteComponent` shows an image or one region of an atlas. `SpriteAnimationComponent` plays clips from an atlas. `AnimatorComponent` runs an animator graph — a state machine that picks the clip from the entity's own state, so the game has no animation code.

The atlas is an Aseprite JSON export (TexturePacker JSON works too). Clips are the `frameTags`; for an Aseprite file, `meta.app` must contain `aseprite`. The image path is relative to the JSON file.

`assets/sprites/hero.json`:

```json
{
  "frames": {
    "hero 0": { "frame": { "x": 0, "y": 0, "w": 32, "h": 32 }, "duration": 150 },
    "hero 1": { "frame": { "x": 32, "y": 0, "w": 32, "h": 32 }, "duration": 150 },
    "hero 2": { "frame": { "x": 64, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    "hero 3": { "frame": { "x": 96, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    "hero 4": { "frame": { "x": 128, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    "hero 5": { "frame": { "x": 160, "y": 0, "w": 32, "h": 32 }, "duration": 100 }
  },
  "meta": {
    "app": "http://www.aseprite.org/",
    "image": "hero.png",
    "size": { "w": 192, "h": 32 },
    "frameTags": [
      { "name": "idle", "from": 0, "to": 1, "direction": "pingpong" },
      { "name": "run", "from": 2, "to": 3, "direction": "forward" },
      { "name": "jump", "from": 4, "to": 4, "direction": "forward" },
      { "name": "fall", "from": 5, "to": 5, "direction": "forward" }
    ]
  }
}
```

The graph's parameters are **bound** to the entity: `speedX` and `velocityY` read its `VelocityComponent` every frame. A state plays the clip of its own name unless it names one with `"clip"`. `"from": "*"` means from any state.

`assets/sprites/hero.animator.json`:

```json
{
  "version": 1,
  "atlas": "assets/sprites/hero.json",
  "entry": "idle",
  "parameters": [
    { "name": "speed", "type": "float", "binding": "speedX" },
    { "name": "vy", "type": "float", "binding": "velocityY" },
    { "name": "grounded", "type": "bool", "binding": "grounded" }
  ],
  "states": [
    { "name": "idle" },
    { "name": "run" },
    { "name": "jump" },
    { "name": "fall" }
  ],
  "transitions": [
    { "from": "idle", "to": "run", "conditions": [{ "param": "speed", "op": ">", "value": 20 }] },
    { "from": "run", "to": "idle", "conditions": [{ "param": "speed", "op": "<=", "value": 20 }] },
    {
      "from": "*",
      "to": "jump",
      "conditions": [
        { "param": "grounded", "op": "==", "value": false },
        { "param": "vy", "op": "<", "value": 0 }
      ]
    },
    {
      "from": "*",
      "to": "fall",
      "conditions": [
        { "param": "grounded", "op": "==", "value": false },
        { "param": "vy", "op": ">=", "value": 0 }
      ]
    },
    { "from": "jump", "to": "idle", "conditions": [{ "param": "grounded", "op": "==", "value": true }] },
    { "from": "fall", "to": "idle", "conditions": [{ "param": "grounded", "op": "==", "value": true }] }
  ]
}
```

```dart
import 'package:just_game_engine/just_game_engine.dart';

void addSprites(Engine engine) {
  // `grounded` is not one of the engine's bindings: teach it to this
  // engine. The built-in ones are velocityX, velocityY, speed, speedX,
  // speedY, health, healthFraction and alive.
  engine.context.animatorBindings.register(
    'grounded',
    (entity) => entity.getComponent<RigidBody2D>()?.isGrounded,
  );

  final world = engine.world;

  // A whole image.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-200, 150, 0)),
    SpriteComponent(spritePath: 'assets/sprites/crate.png'),
  ], name: 'Crate');

  // One region of an atlas: the frame called "hero 0".
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-100, 150, 0)),
    SpriteComponent(
      spritePath: '',
      atlasPath: 'assets/sprites/hero.json',
      region: 'hero 0',
    ),
  ], name: 'Statue');

  // Animated: the graph picks the clip, and faceVelocity flips the sprite
  // to face the way the entity moves.
  world.createEntityWithComponents([
    TransformComponent(),
    VelocityComponent(),
    SpriteAnimationComponent(atlasPath: 'assets/sprites/hero.json'),
    AnimatorComponent(
      graphPath: 'assets/sprites/hero.animator.json',
      faceVelocity: true,
    ),
    InputComponent(), // steered by step 5's PlatformerSystem
    RigidBody2D(friction: 0, lockRotation: true),
    Collider2D(size: Vector2(28, 32)),
    // Draw order: lower layer first, then lower zOrder first.
    LayerComponent(zOrder: 10),
  ], name: 'Hero');
}
```

- Without a graph, `SpriteAnimationComponent(atlasPath: ..., clip: 'run')` plays one clip; `switchClip('idle')` changes it.
- Set parameters that have no binding yourself: `animator.setBool('attacking', true)`, `setFloat`, `setInt`, `setTrigger`.
- `SpriteAnimationComponent` samples pixel art without smoothing by default (`pixelArt: true`); `SpriteComponent` smooths unless `pixelArt: true`.

---

## 7. Levels

A level is a scene: a JSON file listing entities and their components. The Just Game Engine editor writes these files; they are plain JSON, so you can also write them by hand. `assets/scenes/scenes.json` lists the scenes in play order:

```json
{ "scenes": ["level_01", "level_02"] }
```

`assets/scenes/level_01.scene.json`:

```json
{
  "version": 9,
  "name": "level_01",
  "mode": "2d",
  "entities": [
    {
      "name": "Ground",
      "components": [
        { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 300, "z": 0 } } },
        { "type": "RectangleComponent", "fields": { "width": 1200, "height": 40 } },
        { "type": "Collider2D", "fields": { "shape": "matchShape" } }
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

A field left out keeps the component's default. A child names its parent with `"parentName"`, and `"enabled": false` loads an entity switched off.

```dart
import 'package:flutter/painting.dart' show Offset;
import 'package:just_game_engine/just_game_engine.dart';

/// Loads [name] (or the first scene in scenes.json) into the engine's world.
Future<void> startLevel(
  Engine engine,
  List<Spawner> spawners, {
  String? name,
}) async {
  final world = engine.world;
  final scene = name ?? (await SceneLoader.loadManifest()).first;
  await SceneLoader.loadAsset(world, SceneAssets.pathFor(scene));

  // Maps and their tile collision, before the first frame: otherwise the
  // player can fall through ground that is still loading.
  await LevelMaps.preload(world);

  // Spawn points name what to create; the game says how (step 10).
  SpawnPoints.spawnAll(world, spawners);
}

/// Replaces the current level with [name].
Future<void> changeLevel(
  Engine engine,
  List<Spawner> spawners,
  String name,
) async {
  engine.world.destroyAllEntities();
  engine.cameraSystem.brain.reset(); // forget the old level's cameras
  await startLevel(engine, spawners, name: name);
  LevelMaps.evictUnused(engine.world); // drop tilesets no map uses now
}

/// A level map from a file.
Entity addMap(World world) => world.createEntityWithComponents([
  TransformComponent(),
  LevelMapComponent(mapPath: 'assets/maps/level_01.tmx'),
], name: LevelMaps.primaryName);

/// Knocks out the tile under [point] on the map's "Ground" layer.
void breakTile(World world, Offset point) {
  final map = LevelMaps.primary(world);
  final ground = map?.layer('Ground');
  if (map == null || ground == null) return;
  map.setTile(ground, map.cellAt(ground, point), TileCell.empty);
}
```

- **Package components.** The engine's own components always load. A package's components (a genre kit, `just_ui_editor`) load once its extension is installed: `Engine(config: EngineConfig(extensions: [...]))`. Otherwise loading throws `UnknownComponentTypeException` naming the type.
- **Versions.** Older scene files are migrated as they load. A file saved by a newer engine throws `UnsupportedFormatVersionException`.
- **Level maps** are layers of tiles. `LevelMapComponent` takes the engine's own `.map.json`, or a Tiled `.tmx` / `.tmj`, with tilesets as `.tileset.json` or Tiled `.tsx`. A map can also be stored in the scene (the `inline` field), which is what the editor does. Layers marked `collides` get physics bodies from `MapCollisionSystem`. Changing tiles fires a `TileChangedEvent` and rebuilds the collision.

---

## 8. Cameras

`engine.cameraSystem.mainCamera` is the camera the world is drawn through. You can move it by hand (`lookAt`, `zoom`), as in step 2. Games usually describe **shots** instead: entities with a `VirtualCameraComponent`. Each frame the camera brain picks the enabled shot with the highest priority, blends to it, and writes the result into the main camera. With no shots in the world, the brain leaves the main camera alone.

```dart
import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';

void addCameras(Engine engine) {
  final world = engine.world;

  // Follows whoever is tagged "player", looked up every frame, so it keeps
  // working after a respawn makes a new player entity.
  world.createEntityWithComponents([
    TransformComponent(),
    VirtualCameraComponent(follow: const EntityTarget.tag('player'), zoom: 1.5),
    CameraFramingComponent(
      screenY: 0.1, // the target sits a little below the middle
      deadZoneWidth: 0.15,
      dampingX: 0.3,
      lookaheadTime: 0.25,
    ),
    CameraConfinerComponent(boundsName: 'LevelBounds'),
    CameraImpulseListenerComponent(),
  ], name: 'FollowCam');

  // The view never shows anything outside this rectangle.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(2000, 400, 0)),
    CameraBoundsComponent(width: 4000, height: 800),
  ], name: 'LevelBounds');

  // A fixed shot of the boss room. Its trigger raises its priority from 5
  // to 25 while a player is inside, so it wins there.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(3600, 300, 0)),
    VirtualCameraComponent(priority: 5, zoom: 0.8),
    CameraTriggerComponent(
      width: 800,
      height: 600,
      mode: CameraTriggerMode.boostPriority,
      amount: 20,
    ),
  ], name: 'BossCam');

  // How long switching shots takes; CameraBlend.cut switches at once.
  engine.cameraSystem.brain.defaultBlend = const CameraBlend(duration: 0.8);
}

/// A landing, an explosion: every listening shot near it shakes.
void thud(Engine engine, Offset where) {
  engine.cameraSystem.brain.emitImpulse(
    CameraImpulse(position: where, amplitude: 16, duration: 0.3),
  );
}
```

- **Framing** is in screen fractions: `screenX`/`screenY` place the target (−0.5 is the left or top edge), the dead zone is where it moves freely, and the soft zone is where the camera eases after it.
- **Triggers** default to `EntityTarget.tag('player')`. `CameraTriggerMode.enableWhileInside` makes a shot exist only inside the trigger.
- Blends per pair of shots: `brain.blendTable` with `CameraBlendRule`s. `CameraNoiseComponent` adds handheld motion. `CameraTargetGroupComponent` with `CameraGroupFramingComponent` keeps several players in view.

---

## 9. Timelines

A timeline animates any component field over time — a bobbing coin, a door, a cut-scene — and can fire named events. Timelines are JSON assets.

`assets/timelines/door_open.timeline.json` — slides its entity 96 units up in one second, and fires `opened` at the end:

```json
{
  "formatVersion": 2,
  "name": "door_open",
  "duration": 1.0,
  "wrap": "once",
  "tracks": [
    {
      "kind": "property",
      "component": "TransformComponent",
      "field": "position",
      "channel": "y",
      "mode": "relative",
      "keys": [
        { "t": 0.0, "v": 0.0, "i": "eased", "e": "easeInOutCubic" },
        { "t": 1.0, "v": -96.0 }
      ]
    },
    {
      "kind": "event",
      "events": [{ "time": 1.0, "name": "opened" }]
    }
  ]
}
```

`"mode": "relative"` makes the keys offsets from where the field was when the timeline started, so one asset opens every door wherever it stands. A key reaches the next in a straight line unless it says otherwise: `"i": "eased"` with an easing name in `"e"` (`easeInOutCubic`, `easeOutBounce`, …), or `"i": "step"` to hold.

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

void addDoor(Engine engine) {
  final world = engine.world;

  // Plays when a player walks into the 200 x 200 area round the door,
  // and plays backwards when they leave.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(500, 250, 0)),
    RectangleComponent(width: 40, height: 96),
    TimelinePlayerComponent(
      timelinePath: 'assets/timelines/door_open.timeline.json',
    ),
    TimelineTriggerComponent(
      width: 200,
      height: 200,
      onEnter: TimelineTriggerAction.play,
      onExit: TimelineTriggerAction.reverse,
    ),
  ], name: 'Door');

  // Events from every timeline.
  engine.world.getSystem<TimelineSystem>()?.events.listen((event) {
    debugPrint('${event.owner.name}: ${event.name}');
  });
}

/// Starts every timeline player whose `listenSignal` is "alarm".
void soundTheAlarm(Engine engine) => engine.context.signals.emit('alarm');
```

- `TimelinePlayerComponent(playOnStart: true)` plays at once; `play()`, `reverse()`, `restart()`, `pause()`, `seek(t)` control it.
- A timeline can also live in the scene (the `inline` field) instead of a file.
- Track kinds: `property`, `event`, `spriteClip`, `cameraShot`, `audio`, `activation` and `nested`.

---

## 10. Tags, targets and spawn points

**Tags** are labels systems find entities by: `player`, `enemy`, `boss`. An entity can carry several. The world keeps an index, so looking them up is cheap.

**Targets** (`EntityTarget`) name an entity instead of holding it: by name (`EntityTarget.name('Door')`), by tag (`EntityTarget.tag('player')`) or the component's own entity (`EntityTarget.self()`). Cameras, triggers and timelines use them, and they are looked up when needed, so a camera authored before the player exists still finds it.

**Spawn points** are entities with a `SpawnComponent`. They say *what* to create (a spawner id); the game's `Spawner`s say *how*.

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

/// What a level's spawn points can create.
final List<Spawner> spawners = [
  Spawner(
    id: 'player',
    label: 'Player',
    tags: const {'player'}, // what the spawned entity will carry
    spawn: (world, point) => world.createEntityWithComponents([
      // The spawn point's position; TransformComponent copies it.
      TransformComponent(
        position: point.getComponent<TransformComponent>()?.position,
      ),
      VelocityComponent(),
      InputComponent(),
      RectangleComponent(width: 32, height: 48),
      RigidBody2D(friction: 0, lockRotation: true),
      Collider2D(shape: ColliderShape2D.matchShape),
      TagComponent('player'),
    ], name: 'Player'),
  ),
];

void tagsAndTargets(World world) {
  final boss = world.createEntityWithComponents([
    TransformComponent(position: Vector3(900, 0, 0)),
    TagComponent.of(['enemy', 'boss']),
  ], name: 'Boss');
  boss.addTag('armored');

  final enemies = world.allTagged('enemy'); // switched-on ones, oldest first
  final player = world.findTagged('player'); // the oldest, or null
  debugPrint('${enemies.length} enemies; player: ${player?.name}');

  const target = EntityTarget.tag('boss');
  final found = target.resolve(world, null);
  debugPrint(
    'the boss is ${found?.name}, armored: ${found?.hasTag('armored')}',
  );
}
```

- `SpawnPoints.spawnAll(world, spawners)` calls the matching spawner for every spawn point (step 7). `SpawnPoints.first(world, 'player')` finds one.
- Switched-off entities (`entity.isActive = false`) are left out of queries, tag lookups and targets.

---

## 11. Particles and effects

A `ParticleEmitterComponent` puts an emitter on an entity. `ParticleEffects` has presets: `explosion`, `fire`, `smoke`, `sparkle`, `rain`, `snow`, `portal`, `magic` and more. `ParticleSystemECS` updates emitters. It is **not** a default system, so add it once.

Effects are small tick-based animations — `MoveEffect`, `ScaleEffect`, `RotateEffect`, `FadeEffect`, `ShakeEffect`, `ColorTintEffect`, `PathEffect`, combined with `SequenceEffect`, `ParallelEffect`, `DelayEffect` and `RepeatEffect`. They count fixed steps (60 a second), so they play the same on every machine and can be sent over a network.

```dart
import 'package:just_game_engine/just_game_engine.dart';

/// A one-shot explosion; the entity goes when its last particle does.
void explode(World world, Vector3 at) {
  if (!world.hasSystem<ParticleSystemECS>()) {
    world.addSystem(ParticleSystemECS());
  }
  world.createEntityWithComponents([
    TransformComponent(position: at),
    ParticleEmitterComponent(
      emitter: ParticleEffects.explosion(position: at),
      removeEntityWhenComplete: true,
    ),
  ], name: 'Explosion');
}

/// A hit: a short shake, then a fade out.
void hit(World world, Entity enemy) {
  var effects = world.getSystem<EffectSystemECS>();
  if (effects == null) {
    effects = EffectSystemECS();
    world.addSystem(effects);
  }
  effects.scheduleEffect(
    entity: enemy,
    effect: SequenceEffect(
      children: [
        ShakeEffect(amplitude: 6, durationTicks: 12),
        FadeEffect(to: 0, durationTicks: 30, easing: EasingType.easeInQuad),
      ],
    ),
  );
}
```

`FadeEffect` changes the opacity of the entity's `RenderableComponent` (a shape or a sprite). `scheduleEffect` returns an `EffectHandle`; pass it to `cancelEffect` to stop the effect early.

---

## 12. Audio

`engine.music` plays one music track; `engine.sfx` plays sound effects. Paths are asset paths.

```dart
import 'package:just_game_engine/just_game_engine.dart';

Future<void> startMusic(Engine engine) =>
    engine.music.play('assets/audio/theme.ogg', volume: 0.6, fadeIn: true);

Future<void> playJump(Engine engine) async {
  await engine.sfx.play('assets/audio/jump.wav', volume: 0.8);
}

/// From a system: AudioSystem plays it once and removes the component.
void playCoin(Entity coin) =>
    coin.addComponent(AudioPlayComponent(clipPath: 'assets/audio/coin.wav'));

/// A looping sound placed in the world. It is heard from the entity that
/// has an AudioListenerComponent (the player, or the camera).
Entity addWaterfall(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(600, 100, 0)),
  AudioSourceComponent(
    clipPath: 'assets/audio/waterfall.ogg',
    loop: true,
    is3d: true,
  ),
], name: 'Waterfall');
```

- Channel volumes: `engine.music.setChannelVolume(0.5)`, `engine.sfx.setChannelVolume(0.8)`. Every sound from an `AudioSourceComponent` or `AudioPlayComponent` plays on the sfx channel for now, whatever its `channel` field says.
- On the web, browsers keep audio silent until the player interacts, so the engine starts audio at the first key or pointer press (`EngineConfig.deferAudioUntilInput` changes this).

---

## 13. UI over the game

UI is ordinary Flutter, drawn over `GameWidget` in one of two ways:

- **`GameWidget(overlay: ...)`** — widgets stacked over the game. Taps on them do not reach the game. They can never take keyboard focus, so use them for a HUD, not for text fields.
- **`engine.layers`** — a `GameLayer` registered on the engine is drawn in every `GameWidget` that shows it. Layers can take focus: menus walked with the keyboard, text fields.

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

/// The game with a score and touch controls over it.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.engine, required this.score});

  final Engine engine;
  final ValueNotifier<int> score;

  @override
  Widget build(BuildContext context) {
    return GameWidget(
      engine: engine,
      showFPS: false,
      overlay: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: ValueListenableBuilder<int>(
              valueListenable: score,
              builder: (context, value, _) => Text(
                'Score $value',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          ),
          // The on-screen sticks and buttons the input asset defines,
          // shown on touch platforms.
          Positioned.fill(child: OnScreenControls(input: engine.input)),
        ],
      ),
    );
  }
}

/// A pause menu. Register once: `engine.layers.register(const PauseMenu())`.
class PauseMenu extends GameLayer {
  const PauseMenu();

  @override
  String get id => 'pause_menu';

  @override
  GameLayerController createController(Engine engine) => _PauseMenuView(engine);
}

class _PauseMenuView extends GameLayerController {
  _PauseMenuView(this.engine);

  final Engine engine;
  final ValueNotifier<bool> _paused = ValueNotifier(false);

  // Called every frame, even while the engine is paused.
  @override
  void onFrame() => _paused.value = engine.isPaused;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _paused,
    builder: (context, paused, _) => paused
        ? Center(
            child: FilledButton(
              autofocus: true,
              onPressed: engine.resume,
              child: const Text('Resume'),
            ),
          )
        : const SizedBox.shrink(),
  );

  @override
  void dispose() => _paused.dispose();
}
```

`package:just_game_engine/widgets.dart` also has `RebindList` (the controls, each with a button to rebind it), `DialogueBoxWidget` and `DialogueChoicesWidget`, `SubtitleOverlay`, `LocalizedText` and `GameCameraControls` (zoom by wheel, pinch or buttons).

For HUDs and menus designed in an editor, saved as `.ui.json` screens, and text and buttons placed in the level itself, use the `just_ui_editor` package: `JustGameUi.install(engine)` puts its screens on `engine.layers`.

---

## 14. Services

Achievements, sign-in, leaderboards, a currency wallet, an inventory and ads are in a separate package, `just_game_services`. Nothing runs unless you list it. Services start as the engine initializes and stop when it is disposed.

```yaml
dependencies:
  just_game_services: ^0.1.0
```

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_services/just_game_services.dart';

/// A service of your own: started and stopped with the engine.
class PlayTimer implements EngineService {
  final Stopwatch _watch = Stopwatch();

  @override
  Future<void> start(ServiceContext context) async => _watch.start();

  @override
  Future<void> stop() async {
    _watch.stop();
    debugPrint('Played for ${_watch.elapsed}');
  }
}

Future<Engine> bootWithServices() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      // Or GameServices.all() for all six.
      services: [CurrencyManager(), AchievementManager(), PlayTimer()],
    ),
  );
  await engine.initialize();

  engine.currency.add('coins', 10); // saved to disk by default
  engine.achievements.define(
    Achievement(id: 'first_coin', name: 'Rich', description: 'Pick up a coin'),
  );
  engine.achievements.unlock('first_coin');
  debugPrint('Timer running: ${engine.maybeService<PlayTimer>() != null}');
  return engine;
}
```

`engine.currency`, `engine.achievements` and the rest are `engine.service<T>()` under another name. Asking for a service the engine was not given throws a `StateError` that says how to add it.

---

## 15. Testing

Make a new engine in each test and dispose it afterwards. Nothing ticks by itself in a test — there is no `GameWidget` — so step the world yourself with `world.update(1 / 60)`. For plain ECS logic, a `World()` on its own is enough and much faster.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('velocity moves an entity', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    world.addSystem(MovementSystem());

    final box = world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(velocity: Vector3(60, 0, 0)),
    ]);
    for (var i = 0; i < 30; i++) {
      world.update(1 / 60);
    }

    expect(
      box.getComponent<TransformComponent>()!.position.x,
      closeTo(30, 1e-9),
    );
  });

  test('a level loads', () async {
    final engine = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.headless),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    SceneLoader.loadString(engine.world, '''
      {"version": 9, "name": "test", "mode": "2d", "entities": [
        {"name": "Spawn", "components": [
          {"type": "TransformComponent", "fields": {}},
          {"type": "SpawnComponent", "fields": {"spawner": "player"}}
        ]}
      ]}
    ''');
    engine.world.update(1 / 60);

    expect(SpawnPoints.first(engine.world, 'player')?.name, 'Spawn');
  });
}
```

- `DefaultSystems.headless` leaves out rendering and audio.
- `SceneLoader.loadString` loads a scene without an asset bundle.
- Scenes from assets: `SceneLoader.loadAsset` reads through `world.context.bundle`, so an engine made with `Engine(context: EngineContext(bundle: myTestBundle))` loads from a test bundle. A context you pass in is yours to dispose.

---

## 16. When something does not work

| What you see | Likely cause |
|---|---|
| A blank screen, nothing moves | No `defaultSystems` in `EngineConfig`, or `engine.start()` was not called. |
| `EngineNotReadyError` | `engine.world` (or another subsystem) was used before `await engine.initialize()`, or after `dispose()`. |
| `StateError` from `start()` | The engine is not initialized, or already running. |
| Things appear in the wrong place | +Y is down, and the camera's position is the world point in the middle of the screen. || A sprite does not show | The file is not listed under `flutter: assets:`, or the atlas image is not beside its JSON. |
| An animator never changes state | It needs a `SpriteAnimationComponent` on the same entity. A parameter whose `binding` is not registered in `engine.context.animatorBindings` silently keeps its default. |
| Particles do not move | `ParticleSystemECS` was not added; it is not a default system. |
| `UnknownComponentTypeException` loading a level | The package that defines the component was not given to `EngineConfig(extensions: ...)`. |
| The player falls through a map on the first frame | Call `await LevelMaps.preload(world)` after loading the scene. |
| Your system reads stale input or runs after physics | Its priority: character control belongs at `SystemPriorities.playerControl` (95). |

---

## 17. Where next

- [README.md](README.md) — an overview of every feature.
- [MIGRATION.md](MIGRATION.md) — moving a 1.x game to 2.0.
- [example/example.dart](example/example.dart) — a complete example you can run.
- [API reference](https://pub.dev/documentation/just_game_engine/latest/) on pub.dev.
- [ARCHITECTURE.md](ARCHITECTURE.md) — how the engine is built inside.
- [CHANGELOG.md](CHANGELOG.md) — what changed in each release.
- [Contributing](https://github.com/just-unknown-dev/just-game-engine/blob/main/CONTRIBUTING.md) and [issues](https://github.com/just-unknown-dev/just-game-engine/issues).
