# Migrating from 1.x

_Getting started_ · Upgrade a 1.6 game to 2.0: the checklist first, then each breaking change with before-and-after code.

`just_game_engine` 2.0 is a breaking release. The engine is now an object you create, initialize and dispose yourself. Levels are JSON scenes loaded at run time. Cameras, input, sprites, tile maps and the transform hierarchy were rebuilt, and several built-in parts moved to packages of their own.

This page condenses the [full migration guide](https://github.com/just-unknown-dev/just-game-engine/blob/main/MIGRATION.md) on GitHub, which has every table, every removed API and the edge cases. Scene files saved by earlier versions still load: they are migrated in memory when they are read.

## Checklist

1. Raise the constraints: `just_game_engine: ^2.0.0` and Flutter 3.47 (3.47.1 or newer; see "Flutter versions" in [Installation](/docs/installation)). Coming from a 2.0 dev release, `^2.0.0` replaces its `^2.0.0-dev` constraint.
2. Create the engine with `Engine(config: ...)`, `await initialize()` before `runApp`, and dispose it once. Replace `Engine.instance` with a reference you pass around.
3. Add the standard systems through `EngineConfig.defaultSystems`, or give `Physics2DSystem` the engine's physics.
4. Replace `PhysicsBodyComponent` with a `RigidBody2DComponent` and a `Collider2DComponent`, and the collision events with the `...2D` events.
5. Using achievements, sign-in, leaderboards, currency, inventory or ads? Add `just_game_services`.
6. Rename `transform.rotation` to `transform.angle`, drop `HierarchySystem`, and rename `ParentComponent.localOffset` to `localPosition`.
7. Replace camera behaviours and `CameraFollowComponent` with virtual cameras, and read input as actions from `just_inputs`.
8. Replace the in-game UI components, the Tiled components, `engine.animation` and the tweens, and read tags with `hasTag` and `tags`.
9. Move render hooks to the hook chains, and fix imports: `package:just_game_engine/widgets.dart` for the widgets, and the source package for names no longer re-exported.
10. Check the removed and renamed APIs, re-test what behaves differently, and read the known limitations if you query bodies whose collision mask is 0 or change a playing sound.

## Engine lifecycle

In 1.6, `Engine()` returned one process-wide engine, also reachable as `Engine.instance`. In 2.0 every call makes a new, independent engine. Build and initialize it before `runApp`, and add the standard systems through its config:

```dart
// 1.6
final engine = Engine(); // the shared engine
engine.initialize().then((ok) {
  engine.world.addSystem(RenderSystem());
  engine.start();
});

// 2.0
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize(); // throws EngineInitException if a stage fails
  engine.start();
  runApp(MaterialApp(home: Scaffold(body: GameWidget(engine: engine))));
}
```

| 1.6 | 2.0 |
|---|---|
| `Engine()` returns the shared engine; `Engine.instance`, `Engine.resetInstance()` | `Engine({config, context})` makes a new engine each time; keep a reference |
| `Future<bool> initialize()` printed errors and returned `false` | `Future<void> initialize()` throws `EngineInitException(stage, cause, stackTrace)` and undoes what it built |
| `void dispose()`; the singleton could be reset and reused | `Future<void> dispose()`, and it is final: make a new `Engine()` to start over |
| `rendering`, `physics`, `world` were `late final` fields | getters that throw `EngineNotReadyError` before `initialize` and after `dispose` |
| `EngineState.error`; `engine.getSystem<T>()` | `EngineState.failed`; `engine.subsystem<T>()` (`getSystem` is removed) |

- **A widget that owns its engine** disposes it in `State.dispose`; not awaiting `dispose()` there is safe. A `GameWidget` given an engine that is still initializing starts drawing it once it is ready (you still call `engine.start()`), and your own code can follow it through `engine.stateListenable`.
- **Default systems.** `DefaultSystems.all` adds input, physics, movement, audio, rendering, sprites, the animator, timelines, level maps, map collision and cameras; `DefaultSystems.headless` leaves out rendering and audio. A system you added yourself is kept, not added twice. `ParticleSystem` and `EffectSystem` (1.6's `ParticleSystemECS` and `EffectSystemECS`), `HealthSystem`, `LifetimeSystem` and `CheckpointSystem` are not defaults: add the ones you use.
- **Changed constructors.** `PhysicsSystem()` is `Physics2DSystem(engine.physics)`, and gravity is `engine.physics.setGravity(x, y)`. `PhysicsBridgeSystem` is gone. Collider outlines come from a `Collider2DDebuggerSystem(camera: ...)` in the world (`GameWidget(showDebug: true)` adds one). `InputSystem(engine.input)..buttonMappings` is `InputSystem(engine.input, maps: ['player'])`.
- **Your own components in scenes** need a `ComponentDefinition`, installed through a `ContextExtension` in `EngineConfig(extensions: [...])`. See [Scenes](/docs/scenes).

## Physics bodies

`PhysicsBodyComponent` is split the way 3D physics splits a body: `RigidBody2DComponent` says how it moves, `Collider2DComponent` gives it its shape. A `Collider2DComponent` alone is a static body, so walls and floors need nothing else.

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

| 1.6 | 2.0 |
|---|---|
| `shape: RectangleShape(w, h)` | `Collider2DComponent(size: Vector2(w, h))` (a box, the default shape) |
| `shape: CircleShape(r)` | `Collider2DComponent(shape: Collider2DShape.circle, radius: r)` |
| a shape sized to the sprite or rectangle | `Collider2DShape.matchShape`, kept in step as the drawing changes |
| `isStatic` | `RigidBody2DComponent.bodyType` (`Body2DType.static`, `Body2DType.kinematic`, or dynamic by default) |
| `drag` | `linearDamping` |
| `fixedRotation`, `isBullet` (pre-release 2.0, not in 1.6) | `lockRotation`, `continuousCollision` |
| `layer` as a bit, `collisionMask` | `layer` as a number from 0 to 15, `collidesWith` |
| `categoryBits`, `maskBits` | `layer` (a number) and `collidesWith` |
| `CollisionEvent`, `ContactExitEvent`, `SensorEnterEvent`, `SensorExitEvent` | `CollisionEnter2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent`, `SensorExit2DEvent` (`visitor` is now `other`) |
| `DistanceJointComponent`, `WeldJointComponent`, `PrismaticJointComponent`, `WheelJointComponent` (pre-release 2.0, not in 1.6) | `DistanceJoint2DComponent`, `FixedJoint2DComponent`, `SliderJoint2DComponent`, `WheelJoint2DComponent` |
| `RaycastColliderComponent`, `RaycastSystem` (`castRay`, `hasLineOfSight`), `RayTracer` | a `Collider2DComponent` (a sensor, if nothing should bump into it) and `physicsSystem.queries` (`raycast`, `raycastAll`); `RayTracer2D` for rays that bounce off a collider's `reflectivity` |

- **The defaults changed** to 3D's: `friction` 0.5 (1.6 used 0.2), `restitution` 0 (1.6: 0.8, so everything bounced), `linearDamping` and `angularDamping` 0.05 (1.6's `drag` was 0.98), and `mass` 0, which works the mass out from the collider's area. Set the old values where you relied on them; scenes saved by 1.6 keep theirs.
- **Colliders follow scale.** Scale an entity by 2 and its collider grows with it. Code that sized a shape for an entity it also scaled now sizes it unscaled.
- **Named layers.** The layer names and which pairs collide live in `assets/project/physics.json` (a `PhysicsLayers`); list it under `flutter: assets:`. Check pairs with `engine.context.physicsLayers.collides(a, b)`.
- **New:** `CharacterBody2DComponent`, a character gameplay moves (`moveVelocity`, `jump`) instead of the simulation. See [2D physics](/docs/physics-2d).

## Transforms and the hierarchy

The 2D angle is `angle`, and the full rotation is three Euler angles (`eulerX`, `eulerY`, and `angle` about Z). Every `World` now keeps its transform hierarchy itself, so `HierarchySystem` goes, and a child's offset turns and scales with its parent.

```dart
// 1.6
transform.rotation += 0.1;
world.addSystem(HierarchySystem());
world.createEntityWithComponents([
  TransformComponent(),
  ParentComponent(parentId: ship.id, localOffset: Vector3(0, -20, 0)),
]);

// 2.0: no HierarchySystem; the world keeps the hierarchy itself
transform.angle += 0.1; // or transform.rotate(0.1)
world.createEntityWithComponents([
  TransformComponent(),
  // 20 units above the ship from the next update on, turning with it.
  ParentComponent(parentId: ship.id, localPosition: Vector3(0, -20, 0)),
]);
```

Also renamed: `rotationX` and `rotationY` are `eulerX` and `eulerY`, `prevRotation` (a `double`) is `prevAngle`, and `TransformSignals.rotation` is `TransformSignals.angle`. Code that added a `ChildrenComponent` by hand can go: a `ParentComponent` is the whole link.

## Cameras

Camera behaviours, `CameraFollowComponent`, springs, shake and `worldBounds` are gone. A shot is now an entity with a `VirtualCameraComponent`; the camera brain (`engine.camera.brain`) shows the enabled shot with the highest priority and blends to it. Components on the same entity decide how the shot moves.

```dart
// 1.6
engine.cameraSystem.addBehavior(SpringFollowBehavior(target: playerPosition));
engine.cameraSystem.mainCamera.worldBounds = const Rect.fromLTWH(0, 0, 4000, 800);
engine.cameraSystem.mainCamera.shake(12, 0.4);

// 2.0
world.createEntityWithComponents([
  TransformComponent(position: Vector3(2000, 400, 0)),
  CameraBoundsComponent(width: 4000, height: 800),
], name: 'Level Bounds');
world.createEntityWithComponents([
  TransformComponent(),
  VirtualCameraComponent(follow: const EntityTarget.name('Player')),
  CameraFramingComponent(dampingX: 0.3, dampingY: 0.5, lookaheadTime: 0.2),
  CameraConfinerComponent(boundsName: 'Level Bounds'),
  CameraImpulseListenerComponent(),
], name: 'Main Camera');
engine.camera.brain.emitImpulse(
  CameraImpulse(position: const Offset(640, 360), amplitude: 12),
);
```

The other behaviours map to components too: `LookaheadBehavior` to `CameraFramingComponent.lookaheadTime`, `MultiTargetBehavior` to `CameraTargetGroupComponent` with `CameraGroupFramingComponent`, `RoomBehavior` to a virtual camera per room switched by a `CameraTriggerComponent`, `PathBehavior` to `CameraDollyComponent`, and `CinematicBehavior` to `CameraBlendListComponent` or a timeline. The dead zone and soft zone are fractions of the screen, not pixels. The camera systems are in `DefaultSystems.all`, or add them with `registerCameraSystems(world, engine.camera)`. With no virtual camera in the world, the brain leaves `engine.camera.mainCamera` alone, so a game that moves it by hand keeps working.

## Input

`engine.input` was an `InputManager` you polled for keys. It is now a `just_inputs` `InputService`: named actions bound to keyboard, mouse, gamepads and touch, read the same way whatever the device. The bindings live in an input asset (`.input.json`) that the game loads after `initialize()`.

```dart
Future<void> loadInput(Engine engine) async {
  final text = await rootBundle.loadString('assets/input/game.input.json');
  engine.input.loadAsset(InputActionAsset.parse(text));
  await engine.input.attachGamepads(); // optional: starts platform channels
}

// InputSystem copies the 'player' map's actions into each InputComponent.
void readInput(Engine engine, Entity player) {
  final input = player.getComponent<InputComponent>()!;
  final Offset move = input.vector('move'); // was input.moveDirection
  if (input.wasPressed('jump')) debugPrint('jump while moving $move');
  // Or read any action directly:
  final pause = engine.input.actions.action('ui/pause');
  if (pause.wasPressedThisFrame()) engine.pause();
}
```

| 1.6 | 2.0 |
|---|---|
| `engine.input.keyboard.isKeyDown(key)` | an action: `engine.input.actions.action('map/name').isPressed` |
| `InputComponent.isButtonPressed('jump')` | `input.isDown('jump')`; also `wasPressed`, `wasReleased`, `wasPerformed`, `axis` |
| `VirtualJoystick`, `JoystickInputComponent` | on-screen controls in the asset, drawn by `OnScreenControls` |

Input keeps running while the engine is paused, so menus and rebinding work. [Input](/docs/input) shows the asset format.

## Game services

Achievements, sign-in, leaderboards, currency, inventory and ads moved to the `just_game_services` package (`just_game_services: ^0.1.0`, not yet on pub.dev: see [Game services](/docs/services)). In 1.6 every engine built all six; now you list the ones you use, and the engine starts them in `initialize()` and stops them in `dispose()`.

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_services/just_game_services.dart';

Future<Engine> startGame() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      // GameServices.all() gives all six, as 1.6 had them.
      services: [AchievementManager(), CurrencyManager()],
    ),
  );
  await engine.initialize(); // starts both services
  engine.currency.add('coins', 10);
  return engine;
}
```

Saved progress carries over: achievements, currency and inventory still save to the `jge_engine` database. `engine.achievements` and the others now throw a `StateError` naming the fix when the engine has no such service. The managers' `bindWorld`, `initialize` and `dispose` are now `start` and `stop`, called by the engine. The Steam and Epic providers are gone; they did nothing.

The services changed a little too. `AdsManager`'s ready signals are nouns (`isInitialized` → `sdkReady`, `isInterstitialReady` → `interstitialReady`, `isRewardedReady` → `rewardedReady`, `isAppOpenReady` → `appOpenReady`), and its `isInterstitialAdReady`, `isRewardedAdReady` and `isAppOpenAdReady` getters are gone: read the signals' `value`. An `AdsProvider` of your own returns a `RewardedAdResult`, `(shown: …, reward: …)`, from `showRewardedAd()`. An `Achievement`'s `goal` must be positive and finite. Changes are saved together a moment later instead of at once; `flush()` on the achievement, currency and inventory managers saves them now.

## Imports

- **Widgets moved** to `package:just_game_engine/widgets.dart`: `DialogueBox`, `DialogueChoices`, `SubtitleOverlay`, `LocalizedText`, `GameCameraControls`, `OnScreenControls`, `RebindList` and the rest. `GameWidget`, `GameLayers`, `LocalizationScope` and `GameTerminal` stay in the main library.
- **Re-exports are lists now.** The engine re-exports only what its own API uses from `just_inputs`, `just_dart`, `just_memory`, `just_audio_engine` and `just_physics_engine`. For anything else, such as the input asset model (`ActionMapDef`, `InputActionDef`), `Quadtree` or `ObjectPool`, add the package to `pubspec.yaml` and import it. A file that imported `package:just_game_engine/src/...` must import the library instead.

## Removed and renamed APIs

| 1.6 | 2.0 |
|---|---|
| `SceneEditor`, `Scene`, `SceneNode`, `engine.sceneEditor` | entities, and `SceneLoader` for JSON scenes |
| `engine.animation`, the tweens, `AnimationStateComponent` | `SpriteAnimationComponent`, effects (`MoveEffect`, `FadeEffect` and the rest) and timelines |
| `TileMapLayerComponent`, `TiledMapFactory`, `TileMapRenderSystem`, `TiledCollisionSystem` | `LevelMapComponent`, `LevelMapSystem`, `MapCollisionSystem` |
| `TextComponent`, `ButtonComponent`, `UIComponent` | `just_ui_editor`'s `UiTextComponent`, `UiButtonComponent`, `UiElementComponent`, or Flutter widgets over `GameWidget` |
| `engine.network` and the networking classes | nothing: they were stubs |
| `tagComponent.tag` | `tags`, `entity.hasTag('enemy')`, `world.allTagged`, `world.findTagged` |
| `onRenderOverlay`, `onRenderBackground` | `engine.rendering.overlayHooks.add(...)` and `backgroundHooks` |
| `engine.rendering.addRenderable`, `removeRenderable`, `useSpatialIndex` and the other spatial-index and layer members; `addManagedEmitter` | an entity with a `RenderableComponent` (or a `ParticleEmitterComponent`), drawn by `RenderSystem`; `RenderSystem(cullOffscreen: true)` for culling |
| `engine.parallax`, `ParallaxSystem` | an entity with a `ParallaxComponent`, drawn by `ParallaxRenderSystem` |
| `engine.getSystem<T>()` | `engine.subsystem<T>()` |
| `HierarchySystem` | nothing: every world keeps its hierarchy itself |
| `Entity.generation` | nothing: ids are never reused (`world.isEntityAlive(entity)`) |
| `IUpdatable`, `IRenderable`, `IPausable`, `IEnableable`, `ILifecycle`, `LifecycleStateMixin` | nothing: the engine never used them |
| `LocalizationManager.instance` | `engine.context.localization` |
| `Sprite.fromAsset(path)` | `Sprite.fromAsset(path, assets: engine.assets)` |
| `AssetBundle` (the engine's), `typedef Easing` | `GameAssetBundle`, `EasingFunction` |
| `SystemPriorities.tileMap` | `SystemPriorities.levelMap` |
| `PhysicsSystem` | `Physics2DSystem` |
| just_physics_engine 1.x's types: `PhysicsEngine`, `PhysicsBody`, `CollisionShape`, `CircleShape` … `RoundedPolygonShape`, `BodyType`, `Ray`; `engine.physics.castRay`, `castRayAll`, `castCircle`; `RigidBody` | just_physics_engine 2.0's: `Physics2DEngine`, `Physics2DBody`, `Shape2D`, `Circle2DShape` … `RoundedPolygon2DShape`, `Body2DType`, `Ray2D`; `raycast`, `raycastAll`, `circleCast`; `RigidBody` is gone (its CHANGELOG lists every name) |
| `ParticleSystemECS`, `EffectSystemECS` | `ParticleSystem`, `EffectSystem` |
| `CameraSystem`, `engine.cameraSystem` | `CameraEngine`, `engine.camera` |
| `Camera` (the output camera), `ColliderDebuggerSystem` | `OutputCamera`, `Collider2DDebuggerSystem` |
| `AudioSourceComponent.is3d` | `is3D` (saved scenes are renamed as they load) |
| `DialogueBoxWidget`, `DialogueChoicesWidget`, `L10nContext` | `DialogueBox`, `DialogueChoices`, `BuildContextLocalization` |
| `getBounds()`, `getMemoryUsage()`, `getVisibleBounds()`, `getCacheStats()`, `getSystemNames()` | the getters `bounds`, `memoryUsage`, `visibleBounds`, `cacheStats`, `systemNames` |
| `CircleComponent`, `RectangleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent` | `Circle2DComponent`, `Rectangle2DComponent`, `Polygon2DComponent`, `Line2DComponent`, `Capsule2DComponent`; saved scenes are renamed as they load (format 11) |
| `RectangleRenderable`, `CircleRenderable`, `LineRenderable`; `SpriteSheet` | the 2-D shape components or a `CustomRenderable`; an atlas (`SpriteAtlas.fromAsset`) |
| `await parser.parse(json, basePath)` (an `AtlasParser`'s `Future<SpriteAtlas>`) | `parser.parse(json, basePath)`: it returns the `SpriteAtlas` at once |
| `VelocitySignals`, `HealthSignals`; `offload` | a `ComponentSignal` over the field; Flutter's `compute` |

Coming from an earlier 2.0 dev release? The full guide's [Renamed since 2.0.0-dev.3](https://github.com/just-unknown-dev/just-game-engine/blob/main/MIGRATION.md#renamed-since-200-dev3) lists what was renamed after dev.3: every component's name ends in `Component`, `ComponentSchema` and `SchemaField` are `ComponentDefinition` and `FieldDefinition`, `PrefabLibrary.of(context)` is `context.prefabLibrary`, `PhysicsJointBindingSystem` is gone (`Physics2DSystem` makes the joints), and more.

## Behaviour you may notice

- **Destroying an entity destroys its children.** `world.destroyEntity(entity, withChildren: false)` keeps them.
- **A switched-off parent switches off its subtree.** Queries, tag lookups and the engine's systems go by `Entity.isActiveInHierarchy`.
- **Draw order follows `LayerComponent`** (layer, then z-order). Give entities one where order matters.
- **`GameWidget` always draws the world.** If your overlay hook called `engine.world.render`, remove the call, or the world draws twice.
- **`RenderSystem` draws particle emitters itself.** An emitter goes on an entity, in a `ParticleEmitterComponent`; `addRenderable` and `addManagedEmitter` are gone.
- **`CollisionEnter2DEvent.depth` is always 0**, and its `point` is worked out from where the two bodies' bounds meet.

## Known limitations

These wait on `just_physics_engine` and `just_audio_engine`. The fields involved are saved as usual, so scenes need no change when the limits lift.

- **Queries on native Box2D** skip bodies whose collision mask is 0; the Dart backend finds them.
- **Playing sounds.** A playing sound's pitch, pan, speed and loop cannot change until it plays again.

## Saved data

- **Scenes** carry a `version`; the current format is 11 (9 in 2.0.0-dev.1, 10 in dev.2 and dev.3). `SceneLoader` migrates an older file in memory, one step at a time, before creating anything, and nothing on disk changes until the file is saved again. Timelines, animator graphs, level maps and tilesets have format numbers too, and a file from a newer engine is refused with an `UnsupportedFormatVersionException`.
- **Rewrite the files** with `just game migrate` in a project made with the CLI ([The just CLI](/docs/cli)), or from your own script with `SceneFormat.migrateWithReport`, as the full guide shows. Review the diff before you commit it.
- **Storage.** The engine keeps its own storage file, apart from the app's, and moves its keys there on the first launch of 2.0. Cache entries written with `setString` or `setJson` before 2.0 are no longer read. Game services data stays in the `jge_engine` database, as in 1.x.
