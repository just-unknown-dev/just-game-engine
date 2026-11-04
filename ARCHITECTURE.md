# Just Game Engine — Architecture

> **Version:** 2.0.0-dev.4
> **Date:** November 4, 2026
> **Scope:** `packages/just_game_engine` — how the engine is built, for people who work on it

This document describes the code in `lib/` as it is in 2.0.0-dev.4. It is written for contributors. To use the engine, start with the [README](README.md) and the [QUICKSTART](QUICKSTART.md); how to work on the code is in [CONTRIBUTING.md](https://github.com/just-unknown-dev/just-game-engine/blob/main/CONTRIBUTING.md). Where this document and the code disagree, the code is right: please fix the document.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Package Layout](#2-package-layout)
3. [Dependencies](#3-dependencies)
4. [The Engine and Its Lifecycle](#4-the-engine-and-its-lifecycle)
5. [EngineContext](#5-enginecontext)
6. [Services, Plugins and Layers](#6-services-plugins-and-layers)
7. [The Frame](#7-the-frame)
8. [Entity-Component-System (ECS)](#8-entity-component-system-ecs)
9. [Serialization](#9-serialization)
10. [Rendering](#10-rendering)
11. [Physics](#11-physics)
12. [Input](#12-input)
13. [Audio](#13-audio)
14. [Assets and Storage](#14-assets-and-storage)
15. [Cameras](#15-cameras)
16. [Timelines and Animation](#16-timelines-and-animation)
17. [Level Maps](#17-level-maps)
18. [Ready for 3-D](#18-ready-for-3-d)
19. [Platform Support](#19-platform-support)
20. [Known Limitations and Debt](#20-known-limitations-and-debt)

---

## 1. Overview

`just_game_engine` is a game engine for Flutter: 2-D, with 3-D graphics and physics to opt into (§18, §11.3). A game is a `World` of entities that carry components; systems run over them every fixed step, and `GameWidget` draws the result on a Flutter canvas. Around the world sit the engine's subsystems — rendering, physics, input, audio, cache, cameras — and an `EngineContext`, which holds everything one engine *knows*: component definitions, loaders, registries and buses. Levels are JSON scenes; the editor writes them and `SceneLoader` reads them.

What 2.0 changed in the architecture:

- `Engine()` makes a new, ordinary engine. There is no singleton. The engine has an explicit lifecycle, and `dispose()` is final (§4).
- Everything that used to be process-wide — the definition registry, loaders, tile caches, the signal bus, registries, migration hooks — lives in the engine's `EngineContext` (§5). A guard test keeps it that way (§19.4).
- Achievements, sign-in, leaderboards, wallet, inventory and ads left the engine for the package `just_game_services`. The engine keeps the host: `EngineService` and `ServiceHost` (§6).
- The standard systems are one call, `registerDefaultSystems`, or one config field, `EngineConfig.defaultSystems` (§7.4).
- The import loops are gone: the features — the top-level folders of `lib/src/` — sit in one layer order, no import loop crosses from one feature to another, and the ECS core imports no feature. `core/` imports whatever it wires, and nothing imports it: the 3-D services implement `EngineService`, which lives below them in `services/` (§2.3).
- The legacy render path — renderables added to `RenderingEngine` directly, managed particle emitters, `engine.parallax` — and the other deprecated 1.x APIs are gone (§10.7).
- Screen UI widgets moved to `package:just_game_engine/widgets.dart`. The re-exports of `just_inputs`, `just_dart`, `just_memory` and `just_audio_engine` are explicit `show` lists (§3).

| Field | Value |
|---|---|
| Package | `just_game_engine` 2.0.0-dev.4 (scene format 11, timeline format 3; needs `just_game_engine_formats` 0.3.0) |
| Dart SDK | `^3.11.0` |
| Flutter | `>=3.47.1` |
| Platforms | Android, iOS, Linux, macOS, Windows, Web (declared in `pubspec.yaml`) |
| Public libraries | `package:just_game_engine/just_game_engine.dart` (the engine and the hosting widget), `package:just_game_engine/widgets.dart` (optional screen UI), `package:just_game_engine/just_game_engine_3d.dart` (3-D graphics and physics, opt-in) |
| Source | `lib/`: 403 Dart files, about 83,900 lines; 101 classes named `…Component` besides the `Component` base (29 of them 3-D; three are abstract bases: `Joint2DComponent`, `Joint3DComponent`, `Primitive3DComponent`); 30 concrete systems, two of them 3-D (plus the abstract `ReactiveSystem` and `AutoSyncSystem`). Counted on November 5, 2026 with `find lib -name '*.dart'` and the `class …Component` / `class … extends System` declarations |
| Tests | `test/`: 265 test files, in folders that mirror `lib/src/`; `flutter test`: 2,520 passed, 7 skipped — the four Flutter GPU tests and the three timing files tagged `perf` (November 5, 2026) |
| Repository | https://github.com/just-unknown-dev/just-game-engine |

---

## 2. Package Layout

### 2.1 Folders

`lib/src/` is organised by feature: each folder holds a feature's components, systems, definitions and the state it keeps per engine, the way the 3-D graphics and physics folders always were. Below the features sit the ECS core and a few leaf folders; above them, `core/` wires everything together.

```
lib/
├── just_game_engine.dart     the public library: one barrel per folder, plus curated `show`
│                             re-exports of just_inputs, just_dart and just_memory (the
│                             feature barrels show the just_game_engine_formats,
│                             just_physics_engine, just_audio_engine and just_signals names)
├── just_game_engine_3d.dart  3-D, opt-in: Graphics3D, models, shapes, materials, lights;
│                             Physics3D, bodies, colliders, joints, queries; `show` lists of
│                             just_graphics_engine, just_physics_engine's 3-D library and
│                             the 3-D material format
├── widgets.dart              optional screen UI: dialogue boxes, subtitles, localized text,
│                             GameCameraControls, and just_inputs' on-screen controls
└── src/
    ├── core/                 the composition root: Engine, EngineConfig, EnginePlugin,
    │                         GameWidget, GameLayers, GameLoop, TimeManager,
    │                         SystemManager, registerDefaultSystems, BuiltInComponents
    │                         (every feature's definitions), ContextLoaders (overrideLoaders),
    │                         GameTerminal (the debug console)
    ├── services/             EngineService, ServiceHost, ServiceContext, SceneCacheService,
    │                         and GameEngine: the engine as a service sees it
    ├── ecs/                  the ECS core: World, Entity, Component, System, archetypes,
    │   │                     command buffer, event bus, tags (one library, world.dart, and
    │   │                     its parts), EngineContext
    │   ├── serialization/    ComponentDefinition and its registry, the core's own field
    │   │                     types (FieldTypes) and definitions (EcsDefinitions), TagLibrary
    │   ├── transform/        TransformComponent, ParentComponent, ChildrenComponent,
    │   │                     VelocityComponent, the transform hierarchy and its maths
    │   └── spatial/          EntitySpatialGrid, SpatialIndex
    ├── reactive/             signals over the ECS
    ├── foundation/           leaves: Dimensions, Easings, WorldAxes, ShapePaintStyle, and
    │                         the solid parts colliders are fitted to (SolidShapeSource)
    ├── interfaces/           leaves: GameCamera, CameraLens, ViewVolume, FrameView,
    │                         BatchableSprite, SpriteBatchRenderer
    ├── assets/               AssetManager, assets and loaders, TextReader
    ├── storage/              CacheManager and the engine's storage files
    ├── audio/  input/  localization/  subtitle/  navigation/
    ├── narrative/            dialogue: graph/, parser/, runtime/, widgets/
    ├── animation/            the animator: component, system, bindings, targets
    ├── timeline/             timelines: assets, tracks/, players, triggers, signals
    ├── camera/               virtual cameras, the brain, managers, stages/, the OutputCamera
    ├── effects/              deterministic effects: the player and base types, built_in/
    │                         (the eleven effects), networking/
    ├── gameplay/             health, checkpoints, spawns, lifetimes, bounds, movement
    ├── scenes/               SceneLoader and prefabs (files, library, instance components)
    ├── physics/              shared by 2-D and 3-D: collision layers and their field types,
    │                         PhysicsDefinitions (velocity's too), BodyRebuild, ContactPairs
    │   ├── physics_2d/       bodies, colliders, joints, queries, ray traces, Physics2DSystem
    │   │                     (with its bodies, contacts, joints and characters parts),
    │   │                     Collider2DDebuggerSystem (collider outlines)
    │   └── physics_3d/       3-D physics (see just_game_engine_3d.dart)
    ├── rendering/            the drawing contracts: Renderable, Sprite, sprite batching, the
    │                         render components, RenderingEngine and its frame, culling/,
    │                         post_processing/
    ├── sprites/              sprite components and systems; atlas/: sheets, regions, clips
    │                         and their parsers
    ├── parallax/  particles/
    ├── level_map/            level maps: data, runtime, painter, systems; collision/ (tile
    │                         collision), wang/ (terrain)
    └── graphics/             the 2-D barrel (graphics.dart) and the two below
        ├── graphics_2d/      2-D graphics: the 2-D renderer (RenderSystem, its draw list,
        │                     batches and passes, Lighting2DPass) and what it draws: shapes/,
        │                     materials/, lighting/
        └── graphics_3d/      3-D graphics (see just_game_engine_3d.dart): the Graphics3D
                              service, the renderer, models, skeletal animation; shapes/,
                              materials/, lighting/
```

Notes:

- **A feature keeps its state on the context** through an extension of its own (`ContextTimeline`, `ContextLevelMap`, `ContextSprites`, …) backed by `EngineContext.slot` (§5). `EngineContext` itself knows no feature.
- **Definitions live with their feature** (`Shape2DDefinitions`, `GameplayDefinitions`, `Lighting2DDefinitions`, …). `BuiltInComponents` in `core/` lists them all, in the order an editor shows them, and an `Engine` installs it.
- **Drawing is two layers.** The drawing contracts in `rendering/` (`Renderable`, `RenderableComponent`, `Sprite`, `LayerComponent`, `RenderItemsComponent`, culling, `RenderingEngine` and its frame) are below every drawable. The 2-D renderer — `RenderSystem` and its pieces, which draw shapes, sprites, map layers, particles, materials and lights — is above them, at the top of `graphics/graphics_2d/`, as the 3-D renderer is at the top of `graphics/graphics_3d/`. It draws a level map's layers as `RenderItem`s and lights them as `Lighting2DItem`s, so it knows no level map.
- **`VelocityComponent` is in the ECS core** (`ecs/transform/`), beside the transform: physics writes it, and movement, cameras and animator bindings read it. Its definition is still `PhysicsDefinitions.velocity`, registered with the rest of the built-in components.
- **The service contract is below the services.** `services/` holds `EngineService`, `ServiceHost`, `ServiceContext`, `SceneCacheService` and `GameEngine`, the engine as a service sees it (§6.1). `Engine` implements `GameEngine`; `Graphics3D` and `Physics3D` use only that, so nothing imports `core/`.
- **By dimension.** `physics/` holds what 2-D and 3-D physics share (layers, field types, contact pairs), with `physics_2d/` and `physics_3d/` inside it; `graphics/` holds `graphics_2d/` and `graphics_3d/`. The folder names repeat their parent's so a search by name finds them. Like every subfolder, each 2-D one is exported by its parent's barrel (`physics.dart`, `graphics.dart`); the 3-D ones only by the 3-D library. The two graphics folders each hold `shapes/`, `materials/` and `lighting/`, with the 2-D/3-D tag in the class and file names (`Light2DComponent` in `graphics/graphics_2d/lighting/light_2d_component.dart`). `graphics/graphics_3d/` also holds the 3-D renderer, models and skeletal animation and the `Graphics3D` service, its only way in; `graphics/graphics_2d/` holds the 2-D renderer the same way; sprites sit outside it. The solid parts both 2-D and 3-D colliders are fitted to (`SolidShapeSource`, `SolidBox`, …) are in `foundation/`, so neither graphics folder imports the other.
- **The `OutputCamera`** (`camera/output_camera.dart`), which `RenderingEngine` draws through, is in `camera/`, below `rendering/` (§2.3). It and the two files beside it that it is made of (`camera_effects.dart`, `camera_state.dart`) import only each other, `interfaces/` and `foundation/` — nothing else from `camera/`, not the camera director; `test/camera/output_camera_imports_test.dart` keeps it so.

### 2.2 Names and barrels

A file is named after its main class (`asset_manager.dart` holds `AssetManager`); a file that holds several is `<subject>_<kind>.dart`, with any 2-D/3-D tag right after the subject, as in the class names (`physics_2d_events.dart` holds `CollisionEnter2DEvent` and the rest). A subfolder says what it holds (`tracks/`, `built_in/`, `widgets/`); there are no `impl/` or `base/` folders, and no folder of one file.

Each top-level folder of `lib/src/` has one barrel, named after it (`src/timeline/timeline.dart`), which `lib/just_game_engine.dart` exports; it exports the whole folder, subfolders included (`ecs.dart` exports `serialization/`, `spatial/` and `transform/`; `rendering.dart` exports `post_processing/`). No subfolder has a barrel of its own, and no other file exports anything. A library that holds parts is not a barrel: `ecs/world.dart` (the ECS core's types), `particles/particle_emitter.dart`, `sprites/atlas/atlas.dart`, `effects/deterministic_effects.dart` and `camera/camera_definitions.dart` are libraries their folder's barrel exports. The 3-D folders are exported by the public `just_game_engine_3d.dart` instead; their own `graphics_3d.dart` and `physics_3d.dart` hold the `Graphics3D` and `Physics3D` services. A barrel exports only its own folder, plus the `show` lists of `just_game_engine_formats` names its feature owns (the scenes barrel shows `SceneFormat` and `PrefabFile`, the animation barrel `AnimatorGraph`, the ECS barrel the `MigrationHooks` its context holds, …; the 3-D library shows `Material3DFile`). Inside `lib/src/`, a file imports the files it needs, or the barrel of a folder below its own (the 3-D folders import a few) — never one that would lead back to it.

**A file is exported, or it is internal.** Every file under a top-level folder is exported by a public library — through its folder's barrel, `widgets.dart` (the screen widgets) or `just_game_engine_3d.dart` (the 3-D folders) — unless it is an internal helper: then each of its public declarations is marked `@internal` (`package:meta`), and nothing exports it (the analyzer refuses an export of an `@internal` declaration). The internal files today are the render system's pieces (in `graphics/graphics_2d/`: the queue, batcher, bounds, shaded draw, 2-D lighting drawer and shape batch; `rendering/sprite_batching.dart`), the physics systems' helpers (2-D bodies and contacts; 3-D bodies, contacts, joints and characters) and the shared `physics/contact_pairs.dart`, the 2-D material batch and shape sheets, the shape paint cache and renderable, `graphics_3d/shapes/outline.dart`, the Yarn tokenizer and expression evaluator, `ecs/serialization/field_definitions.dart`, `ecs/transform/hierarchy_math.dart`, and the storage files. A feature's context state (`TimelineContextState`, …) is public to `core/` but not exported. `test/library_layout_test.dart` checks all of §2.2: every file exported or internal, only barrels exporting, part-holding libraries not barrels, no import leading back to its own barrel, and the ECS core importing no feature — and §2.3's layer order.

### 2.3 Module structure and the import graph

A feature is a top-level folder of `lib/src/`. The features sit in layers, and a feature imports only features in its own layer or below; inside a layer, imports go one way. From the `import`/`export` directives in `lib/src/` (a part file belongs to its library), top to bottom:

```
lib/just_game_engine.dart, just_game_engine_3d.dart, widgets.dart
        │
core ─────────────────── the composition root: Engine, BuiltInComponents, registerDefaultSystems.
        │                Imports every feature it wires; nothing imports it
level_map ────────────── level maps: tiles drawn through 2-D materials, tile collision on
        │                2-D physics, layers lit as Lighting2DItems
graphics ─────────────── graphics_2d: the 2-D renderer (RenderSystem, its draw list, batches and
        │                passes, Lighting2DPass) and the shapes, materials and lights it draws;
        │                graphics_3d: Graphics3D, whose skeletal clips play in animator graphs
        │                and timelines
timeline, animation ──── timelines (audio, camera and sprite tracks); animator graphs (bound to
        │                sprites, timelines, health). animation imports timeline
gameplay ─────────────── health, checkpoints, spawns, lifetimes, bounds, movement
        │
sprites, particles, parallax, effects, physics
        │                what is drawn and simulated. Physics3D adds a camera stage
rendering, services ──── the contracts: rendering (Renderable, Sprite, the render components,
        │                RenderingEngine and its frame, culling, post-processing); services
        │                (EngineService, ServiceHost, GameEngine), which imports rendering
reactive, localization, subtitle, narrative, audio, input, navigation, scenes, camera
        │                basics on the ECS core. subtitle and narrative import localization
ecs ──────────────────── the ECS core: World, Entity, Component, System, EngineContext, the
        │                transform (and VelocityComponent), serialization. Imports no feature
foundation, interfaces, assets, storage ── leaves
```

What puts each where:

- **`camera/` is low.** It needs only the ECS core, `interfaces/` and `foundation/`, and features above use it: `RenderingEngine` draws through its `OutputCamera`, `Physics3D` registers the camera's collision stage in `context.cameraRegistries`, and timelines key virtual cameras.
- **`rendering/` is contracts.** What is drawn builds on them; the renderer that draws shapes, materials, map layers and particles is above them, in `graphics/graphics_2d/`.
- **`services/` is a contract too.** `Graphics3D` and `Physics3D` implement `EngineService` and see their engine as a `GameEngine` (§6.1), so the 3-D folders import nothing of `core/`.
- **`graphics/` is above animation and timelines** because `graphics_3d/` registers its skeletal animation target and clip track into them, and above particles, whose emitters the 2-D renderer draws. **`level_map/` is above `graphics/`** because its layers draw through 2-D materials; the renderer sees a layer only as a `RenderItem` and a `Lighting2DItem`.
- **`VelocityComponent` is in the ECS core**: physics writes it, and cameras — below physics — read it, as do animator bindings and movement.

**No import loop crosses from one feature to another, and none reaches the ECS core.** `test/library_layout_test.dart` holds the layers above as data: it fails when a feature imports one in a layer above its own, or when any loop joins two features, and names the imports behind it. The loops left are each inside one feature: a folder and its own subfolders (`level_map` with `collision/` and `wang/`; `camera` with `stages/`; `narrative` with `runtime/`; `timeline` with `tracks/`; `rendering` with `post_processing/`; the ECS core with `serialization/` and `transform/`) — six, counting folders as nodes. No file imports its own folder's barrel.

Before the feature layout, the ECS core sat in one loop of 34 folders with most of the engine: `EngineContext` had a field for each feature, and the core's registry knew every built-in component. Both now live above the core — the fields as feature extensions on the context (§5), the built-in components in `BuiltInComponents`. After that, thirteen features still made one loop between them: `rendering/` held both the contracts that graphics, sprites, particles and level maps draw through and the renderer that draws them; `VelocityComponent` was in `physics/`, which imports the camera that read it; and the 3-D services imported `core/`, which imports every feature. The renderer moved to `graphics/graphics_2d/`, velocity to the ECS core and the service contract to `services/`, and 2-D lighting reaches map layers through `Lighting2DItem`.

---

## 3. Dependencies

From `pubspec.yaml`:

| Dependency | Version | What the engine uses it for |
|---|---|---|
| `flutter` | SDK | everything |
| `just_physics_engine` | `^2.0.0` | `engine.physics`: Box2D through FFI on native platforms (`just_box_2d`), pure Dart on the web; re-exported with a `show` list of 25 names (`src/physics/physics.dart`). Its 3-D library (`Physics3DEngine` on Jolt) is used only by `Physics3D` and re-exported only by `just_game_engine_3d.dart` |
| `just_inputs` | `^0.1.1` | `engine.input` (`InputService`): actions, devices, players, rebinding, pointer lock; re-exported with a `show` list of 43 names, widgets through `widgets.dart` |
| `just_audio_engine` | `^1.1.0` | `engine.audio`, `music`, `sfx`; re-exported with a `show` list of 17 names (`src/audio/audio.dart`) |
| `just_game_engine_formats` | `^0.3.0` | the saved file formats and their migrations, in pure Dart (scenes, timelines, animator graphs, prefabs, materials), shared with the editor and the `just` tool; 0.3.0 brings scene format 11 and timeline format 3. Its names are shown by the feature barrels (animation, ecs, graphics, scenes, timeline) |
| `just_graphics_engine` | `^0.1.0-dev.2` | 3-D drawing on Flutter GPU, for `Graphics3D`; imported only by `src/graphics/graphics_3d/` and re-exported only by `just_game_engine_3d.dart`. Its web branch has no `flutter_gpu`, so the engine stays web-safe |
| `just_storage` | `^1.2.1` | the key-value store behind `CacheManager` |
| `path_provider` | `^2.1.5` | finds the folder of the engine's storage file; imported only by `src/storage/engine_storage_io.dart` |
| `just_database` | `^1.4.2` | the binary cache database |
| `just_signals` | `^1.0.2` | signals for the reactive layer, localization, narrative, subtitles and `GameWidget`'s FPS badge; `Signal` and `Computed` re-exported (`reactive/reactive.dart`), since the reactive wrappers return them |
| `just_memory` | `^0.1.0` | budgeted caches in `CacheManager`, `MemoryScope` for assets, diagnostics; 11 names re-exported |
| `just_tiled` | `^0.4.1` | reading and writing Tiled's TMX/TSX/TMJ/TSJ files (`TiledInterop`, `TileAssets`) |
| `just_deflate` | `^0.1.0` | zlib for tile-map chunks: pure Dart, the same bytes on every platform |
| `just_dart` | `^0.2.0` | vectors, quaternions, `Matrix4` and its helpers, `Aabb3`, `Frustum`, `Plane`, `Ray3`; 9 names re-exported |
| `meta` | `^1.9.0` | `@internal` and friends |

Dev dependencies: `flutter_test`, `flutter_lints ^6.0.0`.

The curated re-exports decide what a game can name through `just_game_engine.dart` alone. A name the engine's own signatures use is in the list; the rest (the input asset model, just_dart's `Quadtree`, just_memory's pools) needs a direct import of that package. The lists are in `lib/just_game_engine.dart` (just_inputs, just_dart, just_memory), `lib/widgets.dart` (just_inputs' widgets), `lib/src/audio/audio.dart`, `lib/src/physics/physics.dart`, `lib/src/reactive/reactive.dart` (just_signals' `Signal` and `Computed`) and the formats `show` lists of the animation, ecs, graphics, scenes and timeline barrels; `lib/just_game_engine_3d.dart` has its own for just_graphics_engine, just_physics_engine's 3-D library and the 3-D material format (`Material3DFile` and the rest).

---

## 4. The Engine and Its Lifecycle

### 4.1 What an engine is

```dart
final engine = Engine(
  config: const EngineConfig(defaultSystems: DefaultSystems.all),
);
await engine.initialize();
engine.start();
// …
await engine.dispose();
```

`Engine({EngineConfig config = const EngineConfig(), EngineContext? context})` is a normal constructor: each call makes a new engine with its own context, world and subsystems. The constructor makes (or takes) the context, installs `config.extensions` into it and queues `config.services`. No subsystem is built until `initialize()`.

| Member | Valid | What |
|---|---|---|
| `config`, `context`, `assets` | always | how it is built; what it knows (§5); the context's `AssetManager` |
| `plugins`, `services`, `layers`, `terminal` | always | §6 |
| `state`, `stateListenable`, `lastError`, `isInitialized`, `isRunning`, `isPaused`, `isDisposed` | always | §4.2 |
| `performanceStats` | always | see [STATS.md](STATS.md) |
| `systemManager`, `gameLoop`, `time`, `rendering`, `physics`, `input`, `audio`, `music`, `sfx`, `cache`, `camera`, `world` | once `initialize()` has built them, until `dispose()` | otherwise they throw `EngineNotReadyError`, a `StateError` naming the member and the state |
| `service<T>()`, `maybeService<T>()` | always | §6.1 |
| `subsystem<T>()` | always (null before `initialize()` and after `dispose()`) | a subsystem by the type it was registered under (1.x's `getSystem<T>()` is gone) |

### 4.2 States

```text
uninitialized ─initialize()→ initializing ─ok→ initialized ─start()→ running
      ↑                           │ throws           ↑  ↑                │ ↑
      └──── initialize() ──── failed                 │  └── stop() ──────┤ │
                                                     │        pause()/resume()
                                                     │              paused
any state ─dispose()→ disposing → disposed (final: make a new Engine)
```

| Call | Works in | Anywhere else |
|---|---|---|
| `initialize({EngineConfig? config})` | `uninitialized`, `failed` | `initializing`: returns the running Future; `initialized`/`running`/`paused`: `StateError`; `disposing`/`disposed`: `StateError` saying to make a new `Engine()` |
| `start()` | `initialized` | `StateError` |
| `pause()` | `running` | does nothing |
| `resume()` | `paused` | does nothing |
| `stop()` | `running`, `paused` (back to `initialized`) | does nothing |
| `dispose()` | any | a second call returns the same Future, or nothing; during `initializing` it waits for `initialize()` to finish (or fail), then disposes |

`isInitialized` is true in `initialized`, `running` and `paused` only. `isDisposed` is true from the first moment of `dispose()`. A `config` passed to `initialize()` replaces the constructor's (kept for 1.x code; its extensions and services are added then).

`stateListenable` is `state` as a `ValueListenable<EngineState>`: it notifies on every change, `initializing → initialized` included. It is never disposed, so a listener can be removed at any time, also after `dispose()`. `GameWidget` listens to it to wire an engine it was given before `initialize()` finished (§6.3).

### 4.3 Initialization

`initialize()` builds the engine in nine stages. Each stage pushes what undoes it onto one teardown stack. If a stage throws, the stack runs backwards (so everything built so far is undone), `state` becomes `failed`, and an `EngineInitException(stage, cause, stackTrace)` is thrown and kept in `lastError`. `initialize()` may then be called again.

| # | Stage (`EngineInitException.stage`) | Builds |
|---|---|---|
| 1 | `core` | `TimeManager`, `SystemManager`, `GameLoop(onUpdate: _update, onRender: _frame, onFrame: _perFrame)` (§7.1) |
| 2 | `cache` | `CacheManager`, then `initialize()` — opens the engine's storage (§14.3) |
| 3 | `input` | `InputService`, with `overrideStore = CacheInputOverrideStore(cache)` |
| 4 | `audio` | `AudioEngine` (`config.createAudio` or the default), `MusicManager`, `SoundEffectManager`; the audio engine initializes now — or, on the web, at the first key or pointer press (§13). An audio initialization error is logged, not fatal |
| 5 | `physics` | the 2-D `Physics2DEngine` (`config.createPhysics` or the default, `Physics2DEngine()`), then `initialize()`; then `context.loadPhysicsLayers()` reads the project's collision layers (`assets/project/physics.json`), when the bundle has the file |
| 6 | `rendering` | `CameraEngine` (initialized first), `RenderingEngine` (`config.createRendering` or the default); `rendering.camera = mainCamera`; `plugins.renderOverlay` joins `overlayHooks` at order 100 |
| 7 | `world` | `World(context: context)`, `initialize()`; then `registerDefaultSystems(world, this, include: config.defaultSystems)` when that set is not empty; then the two screen passes, `Lighting2DPass` and `ScreenMaterialPass`, join `rendering.screenPasses` (§7.6), with a teardown that takes them out and disposes them |
| 8 | `subsystems` | registers eight subsystems with the `SystemManager` under their declared types — `RenderingEngine`, `Physics2DEngine`, `InputService`, `AudioEngine`, `CacheManager`, `AssetManager`, `CameraEngine`, `World` — the two update tasks and the two frame tasks (§7.2) |
| 9 | `services` (or `service:<Type>`) | starts every `EngineService`, in the order declared (§6.1) |

Then `state` is `initialized`. The game calls `start()`.

### 4.4 Disposal

`dispose()` returns a `Future<void>`, but everything except the slow part happens before it returns, so not awaiting it is safe. In order:

1. `state` becomes `disposing`; the game loop stops; every plugin detaches.
2. The teardown stack runs backwards, each entry guarded (a failing step is logged and the rest go on):
   - every started service's `stop()` is called, last started first;
   - the two screen passes (2-D lighting, screen material) are taken out of `rendering.screenPasses` and disposed;
   - the world is disposed — **before** physics and rendering, so each system hears `onRemovedFromWorld()` and `dispose()` (highest priority first) while the physics bodies, joints and post-process passes it made can still be taken out; then every entity goes and every component is detached;
   - rendering and the camera system;
   - physics; audio (its shutdown starts); input; the cache; the core (loop, system manager).
3. `layers` are cleared and disposed; `terminal` is disposed.
4. The Future waits for the services' `stop()` calls and the audio shutdown.
5. The context is disposed, if the engine made it (`Engine(context: shared)` leaves a shared context alone). `state` becomes `disposed`.

A disposed engine cannot be initialized again: make a new `Engine()`.

---

## 5. EngineContext

### 5.1 One per engine

`EngineContext` (`lib/src/ecs/engine_context.dart`) holds what an engine knows that is not a subsystem. The engine makes one in its constructor (or is given one) and gives it to its world. Other worlds that work with the same scenes — the interface's screens, an editor's previews — are given the same context: `World(context: engine.context)`. A bare `World()` makes a fresh context of its own and disposes it with itself; `World(extensions: [...])` installs extensions into that context.

| Member | What it is |
|---|---|
| `definitions` | `ComponentDefinitionRegistry` — every component this context can save, load, inspect and draw; the ECS core's own (`EcsDefinitions`: transform, parent, children, tags) are registered from the start |
| `fieldTypes` | `FieldTypeRegistry` — the kinds of field definitions are made of |
| `migrations` | `MigrationHooks` — what packages add to the scene and timeline migrations (§9.4) |
| `bundle` | the `AssetBundle` files come from (`rootBundle` unless given) |
| `assets` | the `AssetManager` (`engine.assets`) |
| `withBuiltIns` | whether the context started with the core's components and field types, and each feature's own kinds as a feature makes its state |
| `slot<T>(key, create)` | the state a feature or package keeps per engine (§5.3) |

**The context knows no feature.** Every feature's components come from an extension: an `Engine` installs `BuiltInComponents.extension` (in `core/`) first, then the config's extensions. A context made on its own — a bare `World()`, a test — has the ECS core's components only; give it `BuiltInComponents.extension` when it reads or writes scenes. `BuiltInComponents.registry()` is a registry with all of them, for code without a context. A kit's extension installs `BuiltInComponents.extension` itself, since its levels use the engine's components too; so does an editor scope.

Each feature keeps its own state in a slot and offers it as an extension on `EngineContext`, so code reads it as before:

| Extension (feature folder) | Members |
|---|---|
| `ContextTimeline` (`timeline/`) | `trackKinds` (`TimelineTrackKinds`: the engine's seven, plus packages'), `easings` (`KeyEasings`), `signals` (`TimelineSignals`: named signals for every world on the context), `timelineAudio` (`TimelineAudio.viaAudioSystem` by default), `timelines` (the `TimelineLoader` seam) |
| `ContextAnimation` (`animation/`) | `animatorBindings` (eight built in: `velocityX`, `velocityY`, `speed`, `speedX`, `speedY`, `health`, `healthFraction`, `alive`), `animationTargets`, `animatorGraphs` (the `AnimatorGraphLoader` seam) |
| `ContextLevelMap` (`level_map/`) | `collisionKinds` (`solid` and `oneWay` always there), `tiles` (`TileAssets`: tileset and map files, what was loaded, the built-in tilesets' pictures; its `readText` is a seam) |
| `ContextEffects` (`effects/`) | `effectTypes` (eleven built in) |
| `ContextPhysics` (`physics/`) | `physicsLayers`, `loadPhysicsLayers()` |
| `ContextLocalization` (`localization/`) | `localization` (`LocalizationManager?`; `GameWidget` provides it through a `LocalizationScope`) |
| `ContextSprites` (`sprites/`) | `sprites` (the `SpriteAssetLoader` seam; a `BundleSpriteAssetLoader` by default) |
| `ContextPrefabs` (`scenes/`) | `prefabs` (the `PrefabLoader` seam), `prefabLibrary` (the `PrefabLibrary`: prefab files loaded, and instances made at run time) |
| `ContextMaterials2D` (`graphics/graphics_2d/materials/`) | `material2DText` (the `TextReader` seam), `material2DLibrary` (the `Material2DLibrary`: 2-D material files read, variants resolved, unsaved edits previewed; a `ContextResource`) |
| `ContextCameraRegistries` (`camera/`) | `cameraRegistries` (`CameraRegistries`: the camera stages and managers every brain of the engine runs; a kit's extension registers its own there) |
| `ContextRenderProviders` (`graphics/graphics_3d/`, 3-D library) | `renderProviders` (`RenderProviders`: the providers that draw a package's own components as meshes and instance batches) |
| `ContextGraphics3DModels` (`graphics/graphics_3d/`, 3-D library) | `graphics3DModels` (the `Graphics3DModels` a `Graphics3D` loads, or null without one; set by `Graphics3D`) |

The runtime registries — `TimelineTrackKinds`, `KeyEasings`, `AnimatorBindings`, `MapCollisionKinds`, `EffectTypes` — are instance classes, each with a frozen, read-only `static builtIn` holding the engine's own entries (`register` on it throws `UnsupportedError`). `EngineContext(withBuiltIns: false)` registers no core definitions or field types, and each feature's registry starts empty — only for tests that check a registry precisely.

### 5.2 Per engine, per world

| Scope | What lives there |
|---|---|
| The engine's `EngineContext` (shared by every world given it) | definitions, field types, migration hooks, the bundle and the `AssetManager`; in slots, each feature's state: track kinds, easings, signals and the timeline audio hook, animator bindings and targets, collision kinds and tile caches, effect types, physics layers, localization, the file seams; and package slots |
| The engine's session subsystems | rendering, physics, input, audio and music, cache, camera system (output camera and brain), services, plugins, layers, terminal |
| Each `World` | entities, archetypes and the query cache, the name and tag indexes, the command buffer, the event bus, the transform hierarchy, the systems, the query versions |
| The camera brain (`engine.camera.brain`) | camera memory, noise time, the impulse bus and its seeds; reset by `CameraBrain.reset()` |
| Each `EffectPlayer` | effect-handle ids |

### 5.3 Extensions and slots

A package teaches an engine through a `ContextExtension`:

```dart
final class MyKitExtension implements ContextExtension {
  const MyKitExtension();
  @override
  String get id => 'my_kit';
  @override
  void install(EngineContext context) {
    context.definitions.registerAll(MyKitDefinitions.all);
  }
}

final engine = Engine(
  config: const EngineConfig(extensions: [MyKitExtension()]),
);
```

`install` runs once per context per `id` (a second install of the same id is ignored). `BuiltInComponents.extension` and then `EngineConfig.extensions` are installed in the engine's constructor, so a context is complete before `initialize()`; a service that is also a `ContextExtension` (`Graphics3D`, `Physics3D`) is installed there too. `context.install(ext)`, `installAll`, `isInstalled(id)` and `installed` work at any time. An extension typically registers definitions, adds migration rules, animator bindings, collision kinds, track kinds or easings, and renames its own component types for older scenes (`context.migrations.renamedTypes`).

State a package keeps per engine goes in a slot: `context.slot<T>(key, create)` makes it on first use, under a key private to the package; a value that is a `ContextResource` is disposed with the context. This is the replacement for a package-level static, and how the engine's own features keep theirs: the feature's extension on `EngineContext` reads the slot.

### 5.4 Loader overrides

The file-reading seams — `sprites`, `animatorGraphs`, `timelines`, `tiles.readText`, `prefabs` and `material2DText` — read the bundle by default. An authoring tool points them at a project's files, for one engine only, through `ContextLoaders` (in `core/`, the one place that knows every feature):

```dart
final override = engine.context.overrideLoaders(
  sprites: mySpriteLoader,
  tileText: (path) => File(path).readAsString(),
);
// …
override.restore(); // puts back each seam it set, if nothing replaced it since
```

`LoaderOverride.restore()` restores a seam only when it still holds what this override set, so a later override is not undone. `context.useBundle()` puts every seam back on the bundle and clears the tile caches.

### 5.5 Disposal

`EngineContext.dispose()` disposes every slot that is a `ContextResource` — the timeline's signal bus, the level map's tile caches (including the built-in tilesets' pictures), a package's own — and then the `AssetManager`. Registrations stay readable, and so do the slots: released, not made again. A disposed context is not meant to be used again.

---

## 6. Services, Plugins and Layers

### 6.1 Services

An `EngineService` is something a game runs beside the engine for the engine's whole life:

```dart
abstract class EngineService {
  Future<void> start(ServiceContext context);
  Future<void> stop();
}
```

- Declare them in `EngineConfig(services: [...])`, or add one later with `engine.services.add(service)`. Find them with `engine.service<T>()` (throws a `StateError` saying how to add it) or `engine.maybeService<T>()`.
- `ServiceHost` (`engine.services`) keeps them in start order: `get<T>()`, `maybe<T>()`, `has<T>()`, `all`, `add(service)`, `remove(service)`. Adding a service of a runtime type already there stops and replaces the old one. Added before `initialize()`, a service waits; added to an initialized engine, it starts at once.
- `initialize()` starts them last (stage 9), after the world exists, in order. A `start` that throws fails `initialize()` with stage `service:<Type>`, and the services already started are stopped.
- `dispose()` calls every `stop()`, last started first, before the world goes, and completes when all have finished.
- `ServiceContext` gives a service `engine`, `context` and `events` — the world's `EventBus`, read on each call. `engine` is a `GameEngine`: what a service sees of its engine — `world`, `context`, `assets`, `rendering`, `services`, `service<T>()`, `maybeService<T>()`, `isInitialized` and `isDisposed`. `Engine` implements it. It is all `Graphics3D` and `Physics3D` use, so the service contract lives below them in `services/` and they import nothing of `core/` (§2.3); a service that needs more of its engine casts (`context.engine as Engine`).
- A service that keeps what scenes use (models, material files, maps) also implements `SceneCacheService` (`void releaseUnused()`), and `Engine.releaseUnused()` asks it to let go of what the world no longer uses (§14.1). `Graphics3D` is one. It is an interface of its own, not an `EngineService` member, so other services need no stub.

The engine ships no services. `just_game_services` provides achievements, sign-in, leaderboards, currency, inventory and ads as `EngineService`s, owns their storage, and adds extension getters for them on `Engine`.

### 6.2 Plugins

An `EnginePlugin` observes or extends a running engine — the editor, a profiler, a recorder:

| Member | When it is called |
|---|---|
| `id` | registering a second plugin with the same id detaches and replaces the first |
| `attach(engine)` | once, from `engine.plugins.register(plugin)` |
| `update(dt)` | once per frame, with the unscaled frame time, whether or not the game is paused or its time scale is zero |
| `renderOverlay(canvas, size)` | once per frame, in screen space, from `overlayHooks` at order 100 — after the world has drawn |
| `detach()` | from `unregister(id)`, or when the engine disposes |

`PluginHost` (`engine.plugins`) has `register`, `unregister`, `byId`, `all`, `update`, `renderOverlay` and `detachAll`.

### 6.3 Layers and the widget

`GameWidget(engine: …)` hosts a game in Flutter. It ticks the game loop from a vsync `Ticker`, paints through `RenderingEngine.render` (at most once per `rendering.drawInterval`, §7.1), and forwards key and pointer events to `engine.input`. It may be built before `initialize()` has finished: it listens to `Engine.stateListenable`, and as soon as the engine is initialized it wires the world's render hook and applies `showDebug` — once, with no rebuild. Until then, and after the engine is disposed, it does nothing: no tick, no paint, no input.

What is drawn over the game, as Flutter widgets, has two slots:

- **`GameWidget.overlay`** — a widget stacked over the canvas, inside the game's own `Focus` node. It takes taps, never keyboard focus, so the game's key state stays reliable. Good for simple HUDs and buttons.
- **`engine.layers`** — a `GameLayers` list that packages register `GameLayer`s on (`register`, `unregister`, `byId`, `all`, `isEnabled`, `setEnabled`, `clear`). A layer has an `id`, an `order` (lower draws first) and `createController(engine)`. Each `GameWidget` asks each layer for its own `GameLayerController` (`build`, `onFrame` after the game has stepped, `dispose`), so two views of one engine never share widget state. Layers sit *outside* the game's `Focus` node, so a text field in a layer can be typed into and a menu walked with the arrow keys; keys a layer does not use bubble on to the game's input. A layer switched off keeps its controllers; `GameWidget(showLayers: false)` hides them all.

Stacking, bottom to top: the game canvas (with `overlay`), the layers, the FPS badge (`showFPS`), the developer terminal (`showTerminal`, toggled with the backquote key; `engine.terminal` is its `GameTerminal` model). The engine has no in-game interface of its own: the `just_ui_editor` package registers a layer that draws the game's screens.

`GameWidget` also pauses a running engine when the app goes to the background and resumes it on return — but only if it paused it; a game the player paused stays paused. When `engine.context.localization` is set, everything the widget draws sits under a `LocalizationScope` for it.

---

## 7. The Frame

### 7.1 The loop

`GameLoop` is driven from outside: `GameWidget`'s vsync `Ticker` calls `engine.gameLoop.tick(stamp)` once per frame, with the frame's own timestamp (`SchedulerBinding.currentFrameTimeStamp`), which every view of the engine shares. A headless game or a test calls `tick()` itself; without a frame time the loop times the frame with its own `Stopwatch`.

```
Ticker (GameWidget, vsync) ─ engine.isInitialized? otherwise nothing
 ├─ gameLoop.tick(stamp)                          only while the loop is started
 │    ├─ the same stamp as the last tick? nothing (a second view of the engine ticked it)
 │    ├─ frame time = stamp − previous stamp      (vsync stamps: exact on the web too)
 │    ├─ timeManager.update(frame time, paused:)  clamped to maxDeltaTime (0.1 s), × timeScale;
 │    │                                           game time stands still while paused
 │    ├─ FPS counted over at least one second
 │    ├─ unless paused:
 │    │    accumulator += frame time              capped at 3 steps
 │    │    while accumulator ≥ step × 0.99:       step = fixedDeltaTime = 1/60 s
 │    │        Engine._update(step × timeScale)   only in state running (§7.2)
 │    │        accumulator −= step
 │    │    Engine._perFrame(dt, interpolation)    only in state running; dt is the frame's
 │    │        ├─ rendering.interpolation = interpolation      (the FrameView's, for 3-D)
 │    │        └─ the frame tasks (§7.2): ecs = World.frame (every PerFrame), then audio
 │    └─ Engine._frame()                          every tick, paused or not, on real time
 │         ├─ paused: input clock += unscaled frame time; input.update(clock); audio.update(dt: 0)
 │         ├─ camera.update(unscaled frame time)    the output camera's post effects
 │         └─ plugins.update(unscaled frame time)
 ├─ repaint, unless rendering.drawInterval has not passed since the last one
 │    → _GamePainter.paint → rendering.render(canvas, size)   (§7.6)
 └─ each enabled layer's controller: onFrame()
```

- The engine's loop runs 60 fixed steps a second (`targetUPS` is left at its default; `EngineConfig` has no setting for it).
- A step is taken when the accumulator is within 1 % of one: vsync stamps come rounded, and a strict comparison gave none, then two, steps in alternate frames.
- The time scale scales the `dt` systems receive, not the number of steps. At `timeScale` 0 steps still run, with `dt` 0.
- `interpolation` is `accumulator / step`, clamped to 0..1. `_perFrame` hands it to `rendering.interpolation` and to every `PerFrame`; `RenderSystem` uses it to draw physics-driven entities between their previous and current poses.
- The game ticks every frame, but `GameWidget` repaints only as often as `rendering.drawInterval` allows (null, the default: every frame); in between the view shows the frame it drew last.
- `resume()` empties the accumulator, so a long pause is not caught up in a burst of steps.

**Frame systems.** A `PerFrame` is a `System` that also runs once per rendered frame — `frame(dt, alpha)`, after the frame's fixed steps and before it is drawn — for what must move at the display's rate rather than the simulation's. `World.frame` runs every active one in priority order, flushing the command buffer after each, and settles the transform hierarchy again when one ran. It does not run while the game is paused. The engine's are `RenderSystem` (it takes `interpolation` here), `CameraBrainSystem` (it evaluates the brain here when `CameraBrain.updateMode` is `CameraUpdateMode.frame`, §15) and `AudioSystem` (it sends the listener's and the moved sources' poses, §13). Systems that don't implement it pay nothing.

### 7.2 Update tasks

`Engine._update(dt)` counts the frame and calls `SystemManager.runUpdateCycle(dt)`, which runs the update tasks in the order they were registered and, while `systemManager.profiling` is on (the default outside release builds), times each one:

| Task | What it does |
|---|---|
| `input` | advances the input clock by `gameLoop.fixedDeltaTime` (real time, before time scale — a held button takes as long in slow motion) and calls `input.update(clock)` |
| `ecs` | `world.update(dt)` — every system, including `Physics2DSystem`, which steps `engine.physics` inline, and the `ParticleSystem` a game adds, which updates the particle emitters |

There is no physics task. `Physics2DSystem` steps the physics engine inside the ECS pass, so velocity a player-control system sets this step reaches this step's simulation. Without a `Physics2DSystem` in the world, bodies do not move.

After the frame's fixed steps — and only while the game runs, not while it is paused — `Engine._perFrame` calls `SystemManager.runFrameCycle(dt, alpha)`, which runs the frame tasks in the order they were registered (they are not timed):

| Frame task | What it does |
|---|---|
| `ecs` | `world.frame(dt, alpha)` — every active `PerFrame` (§7.1) |
| `audio` | `audio.update(dt)` — last, once the camera and the sources have moved: every 3-D sound is placed, in one batch (§13) |

Neither cycle has a camera task: the brain runs in the ECS (`CameraBrainSystem`), and `camera.update`, which only advances the output camera's post effects, runs from `Engine._frame` once per tick, on real time, paused or not (§7.1).

`engine.systemManager.registerUpdateTask(name, task)` adds an update task after these two, and `registerFrameTask(name, task)` a frame task after those two; names must be unique. Update-task timings are in `performanceStats` (see [STATS.md](STATS.md)).

### 7.3 World.update

```
if the command buffer holds anything: commands.flush()   (what was queued between updates)
for each system, highest priority first:        (sorted when added)
    before the first system with priority < SystemPriorities.hierarchy (50):
        transformHierarchy.propagate()           (§7.5; at the end if no such system)
    if system.isActive: system.update(dt)        timed into World.stats while World.profiling is on
    if the command buffer holds anything: commands.flush()
```

- The order comes from `System.priority`; systems of equal priority run in the order they were added, and `sortSystems` keeps that order. Systems may be added and removed while the systems run — a system may remove itself or call `clearSystems`: one removed before its turn is skipped, one added runs from the next update. Adding a system already in the world does nothing.
- Commands queued by one system are applied before the next one runs (§8.6).
- An exception from a system ends the update, and `World` does not catch it. The game loop drops the frame's remaining steps (no burst of catch-up steps once it stops throwing) and rethrows; `GameWidget` reports it through `FlutterError.reportError` and goes on ticking, drawing the view and its layers, so one throwing system does not freeze the game.

### 7.4 Default systems and priorities

`registerDefaultSystems(world, engine, {include, camera, inputMaps})` adds the engine's standard systems to a world. Each is added at most once: one already there — a game's own configured instance — is kept, so calling it twice is safe. World-space drawers get `camera`, the engine's main camera by default. `EngineConfig.defaultSystems` (empty by default, so it is opt-in) makes `initialize()` call it on the engine's world.

| `DefaultSystem` | Adds |
|---|---|
| `input` | `InputSystem(engine.input, maps: inputMaps)` — `inputMaps` is `['player']` by default |
| `physics` | `Physics2DSystem(engine.physics)` — bodies, the 2-D joints between them (`Physics2DJoints`) and characters |
| `movement` | `MovementSystem()` |
| `audio` | `AudioSystem(engine: engine.audio, camera: engine.camera.mainCamera)` |
| `rendering` | `RenderSystem(camera: camera, statsSink: engine.rendering, clock: () => engine.time.totalTime)` and `ParallaxRenderSystem(backgroundHooks: engine.rendering.backgroundHooks, camera: camera)` |
| `sprites` | `registerSpriteSystems(world, animators: false, timelines: false)`: `SpriteLoadSystem`, `SpriteAnimationSystem` |
| `animation` | `registerAnimatorSystems(world)`: `AnimatorSystem` |
| `timelines` | `registerTimelineSystems(world)`: `TimelineTriggerSystem`, `TimelineSystem` |
| `levelMaps` | `LevelMapSystem()` |
| `mapCollision` | `MapCollisionSystem()` |
| `cameras` | `registerCameraSystems(world, engine.camera)`: `CameraTargetGroupSystem`, `CameraTriggerSystem`, `CameraBrainSystem` |

`DefaultSystems.all` is all eleven; `DefaultSystems.headless` leaves out `rendering` and `audio`.

Every system's priority, from the `priority` getters of the systems in `lib/src/` (higher runs first):

| Priority | From | System | Added by |
|---|---|---|---|
| 110 | `SystemPriorities.levelMap` | `LevelMapSystem` | `levelMaps` |
| 108 | `mapCollision` | `MapCollisionSystem` | `mapCollision` |
| 105 | `parallax` | `ParallaxRenderSystem` | `rendering` |
| 100 | `input` | `InputSystem` | `input` |
| 91 | literal | `ViewCullingSystem` | — |
| 90 | `physics` | `Physics2DSystem` | `physics` |
| 90 | `physics` | `Physics3DSystem` (3-D library) | `Physics3D` (unless `addSystem: false`) |
| 86 | literal | `FlowFieldSystem` | — |
| 81 | `movement + 1` | `SimpleMovementSystem` | — |
| 80 | `movement` | `MovementSystem` | `movement` |
| 73 | `animation + 3` | `TimelineTriggerSystem` | `timelines` |
| 72 | `animation + 2` | `TimelineSystem` | `timelines` |
| 70 | `animation` | `AnimatorSystem` | `animation` |
| 70 | `animation` | `Animation3DSystem` (3-D library) | `Graphics3D` |
| 69 | `animation − 1` | `SpriteLoadSystem` | `sprites` |
| 68 | `animation − 2` | `SpriteAnimationSystem` | `sprites` |
| 65 | `effects` | `EffectSystem` | — |
| 60 | `gameplay` | `HealthSystem`, `LifetimeSystem` | — |
| 59 | `dialogue` (`gameplay − 1`) | `DialogueSystem` | — |
| 58 | `checkpoint` | `CheckpointSystem` | — |
| 50 | `hierarchy` | the world's `TransformHierarchy` (not a system) | every world |
| 48 | `particles` | `ParticleSystem` | — |
| 47 | `camera + 2` | `CameraTargetGroupSystem` | `cameras` |
| 46 | `camera + 1` | `CameraTriggerSystem` | `cameras` |
| 45 | `camera` | `CameraBrainSystem` | `cameras` |
| 40 | `render` | `RenderSystem` | `rendering` |
| 35 | `postProcess` | `PostProcessSystem` | — |
| 30 | `boundary` | `BoundarySystem` | — |
| 10 | `debug` | `Collider2DDebuggerSystem` | `GameWidget(showDebug: true)` |
| −10 | `audio` | `AudioSystem` | `audio` |

`SystemPriorities` also names slots for packages: `playerControl` (95), `movingPlatform` (92) and `genreRules` (59), used by `just_platformer_kit`. `ParticleSystem` is in no default set: a game that uses `ParticleEmitterComponent`s adds it.

### 7.5 The transform hierarchy

`TransformComponent` is the **world** transform: what every system reads and writes and what a scene saves. A child's place under its parent (`ParentComponent.localPosition`, `localRotation`, `localScale`) is runtime state, never saved. Every world keeps the two in step through its own `World.transformHierarchy`, run inside `World.update` at priority 50 — after physics, movement and gameplay, before the camera brain and rendering:

```
for each child, parents first:
  if its local is unknown (ParentComponent.needsLocal), or its world changed since the last pass:
      local = parent⁻¹ ∘ world        (someone moved it: it stays put)
  else:
      world = parent ∘ local          (it follows its parent)
```

A link starts in one of two ways:

- **Without local values** — `ParentComponent(parentId: p)`, and every link a scene file loads — `needsLocal` is true: the first pass works the local transform out from where the child already is, and the child does not move.
- **With local values** — any of `localPosition`, `localRotation`, `localScale` given — `placesByLocal` is true until a pass has seen the child: the first pass composes its world transform from the parent's and those values, whatever its `TransformComponent` said. `propagateFrom` does the same for such a link.

The world keeps the other end of every link. While a `ParentComponent` is on an entity, the parent it names lists the entity in its `ChildrenComponent`, made for it when it has none. Setting `parentId` (a setter the world listens to) moves the child from the old parent's list to the end of the new one's; removing the component, replacing it with a link to another parent, or destroying the entity takes it off. A `parentId` naming no entity in the world, or the entity itself, is left unlisted. The hierarchy walks down those lists, so a `ParentComponent` is all a game adds. Setting `parentId` keeps the local transform, so the child takes the same place under its new parent; `invalidateLocal()` after it keeps the child where it is instead.

Only entities with children are visited, so a world without a hierarchy pays nothing. `TransformHierarchy.enabled = false` turns it off for a world whose parent links are only organisational. An editor, whose clock stands still while authoring, calls `propagateFrom(entity)` or `adopt(entity)` after its own edits. The maths is in §18.

### 7.6 Rendering the frame

`_GamePainter.paint` clips to the widget and calls `RenderingEngine.render(canvas, size)`:

```
 1  post-process layers open           one saveLayer per enabled PostProcessPass, outermost first
                                       (only where ShaderFilterSupport.isSupported)
 2  screen passes begin                when a ScreenPass is active: the frame from here on is drawn
                                       into an image (or into layers the passes filter)
 3  camera.effectManager.preRender     its layer (motion blur) is the innermost
 4  clear to backgroundColor
 5  backgroundHooks                    screen space: ParallaxRenderSystem
 6  sceneRenderers                     screen space, from `view` (FrameView) — where a 3-D backend draws
 7  overlayHooks below order 100       screen space (all of them when no screen pass is active):
       order 0   world.render          added by GameWidget; each active system's render(),
                                       highest priority first (RenderSystem at 40 draws the world
                                       through its camera; Collider2DDebuggerSystem at 10 over it)
 8  camera.effectManager.postRender
 9  screen passes paint                each active pass over the view, from the frame so far;
    overlayHooks from order 100        then, over them: plugins.renderOverlay (added by Engine.initialize)
10  post-process layers close
11  camera.effectManager.render        screen-space effects: fade, letterbox
12  debug text                         when rendering.debugMode
```

The overlay hooks run in screen space, so an ECS system applies its camera itself. That is why `RenderSystem` and `Collider2DDebuggerSystem` take a `camera`: without one, world coordinates are drawn as screen pixels. `RenderHookChain` runs hooks in ascending `order`, ties in the order added; `addIfAbsent` makes wiring idempotent. The post-process passes wrap the whole frame, the background and parallax included.

**Screen passes.** `RenderingEngine.screenPasses` is a list of `ScreenPass`es, drawn over the whole frame from an image of it. `Engine.initialize` adds the engine's two: `Lighting2DPass` (2-D lights and shadows, while an enabled `Lighting2DComponent` is in the world) and `ScreenMaterialPass` (the material of the `ScreenMaterialComponent` with the highest `order`). Each says once a frame whether it is `active`; when none is, the frame is drawn straight to the canvas. Otherwise everything up to the overlay hooks of order `RenderingEngine.screenPassOrder` (100) is drawn into an image, and the passes paint it over the view, each from what the one before drew. Where the renderer filters layers with shaders, the last passes that can be filters (`ScreenPass.filter`) become layers around the drawing instead (`ScreenPassPlan`). Overlay hooks of order 100 and up — an editor's, a plugin's — draw over the passes, unlit. Unlike post-process passes, screen passes need no layer filter, so they work on the web too.

---

## 8. Entity-Component-System (ECS)

### 8.1 The types

`lib/src/ecs/world.dart` is one library; the files beside it (`component.dart`, `entity.dart`, `archetype.dart`, `system.dart`, `command_buffer.dart`, …) are its parts, so `World`, `Entity`, `Archetype` and `CommandBuffer` share private state. `ecs.dart` is the folder's barrel: it exports `world.dart` and the rest, and holds nothing itself.

| Type | What it is |
|---|---|
| `Component` | data. `componentType` (its runtime type unless overridden — a subclass can share its parent's slot), `onAttach(EntityId)`, `onDetach(EntityId)` |
| `Entity` | a handle: `id`, `name`, `isActive`, `isAlive`, `world`; `addComponent`, `removeComponent<T>()`, `removeComponentByType`, `getComponent<T>()`, `hasComponent<T>()`, `hasComponents(types)`, `components` |
| `System` | logic: `requiredComponents`, `priority`, `isActive`, `world`; `initialize`, `update(dt)`, `render(canvas, size)`, `onAddedToWorld`, `onRemovedFromWorld`, `dispose`; `entities` is `world.query(requiredComponents)` |
| `World` | entities, systems, queries, `commands` (`CommandBuffer`), `events` (`EventBus`), `transformHierarchy`, `context` (`EngineContext`) |
| `EntityPrefab` | a name and component factories; `world.instantiate(prefab)` |

`World.createEntityWithComponents(components, {name})` places an entity in its archetype once, instead of moving it once per component.

### 8.2 Archetype storage

Entities with exactly the same set of component types share an `Archetype`: one dense column (`List<Component>`) per type, with parallel lists of entity ids and entities. Adding or removing a component moves the entity's row to another archetype. Each archetype caches where an added or removed type leads (its add/remove edges), so a move is a map lookup. A row leaves by swap-and-pop: the last row fills the gap. Query results therefore come in archetype order, not creation order — draw order is set with `LayerComponent`, and `RenderSystem` breaks the remaining ties by entity id, never by row (§10.2).

Archetypes are found by a Zobrist hash of their type set: each `Type` gets a random 31-bit key (31 bits, so keys are the same integers on the web), and a set hashes to the XOR of its keys. A hash is only a hash: every hit is checked against the type set itself. Archetypes live until the world is cleared (`destroyAllEntities`, `dispose`).

### 8.3 Queries, the query cache and query versions

`world.query(List<Type> componentTypes)` returns the entities active in the hierarchy (§8.4) that have every one of those types, as an unmodifiable `List<Entity>`:

- There is one cache entry per distinct type set. It holds the archetypes that match (extended when a new matching archetype is made) and the last result.
- A result is dropped only when an archetype it matches gains or loses a row, or one of its entities is switched on or off. Unrelated queries keep theirs. Asking again in the same frame is a lookup.
- A returned list is never changed; a later change makes a new one.

`world.queryArchetypes(types)` returns the matching archetypes, for systems that walk columns directly (`getColumn(type)`, `entityIds`, `entityAt(row)`). It does **not** leave out switched-off entities: the caller checks `archetype.entityAt(row).isActiveInHierarchy`. `getColumn` and `entityIds` are the live lists and marked `@internal`; game code reads rows with `getComponent`, `getComponentByType` and `entityAt`.

`world.queryVersion(types)` is each cached query's own version. It moves on only when what that query matches may have changed: an entity with all of the types is created or destroyed, gains or loses any component, has one replaced, or is switched on or off (itself or through a parent), or a new matching archetype appears. Changes to entities the query cannot match leave it alone. Versions are unique within the world and only go up, so a system reading several queries compares the largest. `RenderSystem`, `ComponentPainterPass`, `Physics2DSystem` (with its characters and joints), `Physics3DSystem`, `Graphics3DSceneRenderer`, `Animation3DSystem`, `ViewCullingSystem`, `LevelMapSystem` and the sprite and timeline systems keep what they built per entity until one of their own queries' versions moves. There is no world-wide structure counter.

### 8.4 isActive and isAlive

- `isAlive` — the entity exists: its world has not destroyed it.
- `isActive` — the entity itself is switched on: the scene's saved "enabled" flag, which the editor shows and saves. `SceneLoader` switches off entities saved with `enabled: false`.
- `isActiveInHierarchy` — it is switched on and so is every parent above it (Unity's `activeInHierarchy`). This is what `query`, `findTagged` / `allTagged`, `findEntityByName(includeInactive: false)`, `activeEntities` and the engine's systems go by: switching a parent off takes its whole subtree out of queries, drawing and simulation without changing the children's own flags. The world keeps it cached, updating it as entities are switched, re-parented, made and destroyed, and moves the affected queries' versions on.

### 8.5 Names and tags

- **Names.** `world.findEntityByName(name, {includeInactive = true})` returns the oldest entity with that name. It is backed by an index (a map from name to entities in id order), kept up to date by the `Entity.name` setter.
- **Tags.** `TagComponent` holds a set of tags (`tags`, `has`, `add`, `remove`; 1.x's single-tag `tag` is gone). The world keeps a tag index: `findTagged(tag, {includeInactive = false})` returns the oldest tagged entity; `allTagged(tag, {includeInactive = false})` returns every tagged entity, oldest first, as an unmodifiable list that is reused until that tag's entities change or one is switched on or off — asking every frame does not allocate. `tagsInUse` lists every tag in the world. `TagNames` validates and normalises tag names.
- **Targets.** `EntityTarget` names an entity by name or by tag, or `self`. `resolve(world, owner)` returns the first switched-on match; `resolveAll(...)` every match. Components that point at other entities (cameras, triggers, spawners) save an `EntityTarget`.

### 8.6 The command buffer

`world.commands` queues structural changes made while systems iterate: `create(components, {name})`, `destroy(entity, {withChildren})`, `addComponent(entity, c)`, `removeComponent<T>(entity)`.

- `flush()` applies them **in the order they were queued**, so `removeComponent<SpriteComponent>(e)` followed by `addComponent(e, newSprite)` ends with the new sprite.
- A command on an entity gone by then is skipped.
- Commands queued during a flush (by a component's `onAttach`, say) run in the same flush, after those already queued.
- `World.update` flushes after every system that leaves commands queued, so the next system sees the change.

### 8.7 Destroying entities

`world.destroyEntity(entity, {bool withChildren = true})`:

- The entity leaves its parent's `ChildrenComponent`.
- With `withChildren` (the default) the whole subtree goes, children first. The children are those its `ChildrenComponent` lists whose `ParentComponent` names it back.
- With `withChildren: false` the children stay, cut loose: their parent link is cleared and each becomes a root where it stands.
- Every component of every destroyed entity is detached (`onDetach`). Replacing a component with another of its type detaches the old one too.
- A stale handle — destroyed already, or another world's — is ignored.

Entity ids count up for the life of the world and are never reused, not even after `destroyAllEntities()`. State a system keeps by id can never attach itself to a newer entity. `world.isEntityAlive(entity)` (or `entity.isAlive`) checks a held handle; entities have no generation counter.

### 8.8 Events

`world.events` is an `EventBus`. `on<T extends GameEvent>(callback)` returns an `EventSubscription` (`cancel()`); `fire(event)` calls the subscribers of the event's exact runtime type, at once, synchronously. The bus is cleared with the world. The engine fires `CollisionEnter2DEvent`, `CollisionStay2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent` and `SensorExit2DEvent` from `Physics2DSystem`, and `TileChangedEvent` from level maps, among others.

### 8.9 The reactive layer

`lib/src/reactive/` wraps the ECS in `just_signals` signals for Flutter UI: `ComponentSignal<C, T>` (a `Signal` over one component field, with `TransformSignals` ready-made; it reads only the ECS core, so signals over a feature's components are a game's own `ComponentSignal`s), `EntitySignal`, `WorldSignal`, `ReactiveSystem` (processes only entities marked dirty), `AutoSyncSystem` with `SignalSyncMixin`, and the `ReactiveComponent` mixin. It is optional: nothing else in the engine depends on it. Of `just_signals` itself only `Signal` and `Computed` are re-exported, the types these wrappers return; import the package for `SignalBuilder`, `Effect` and the rest (see the [app structure guide](doc/guides/app-structure.md)).

---

## 9. Serialization

### 9.1 Definitions are the save format

A component is saved by its `ComponentDefinition<T>`, registered in `context.definitions` (a `ComponentDefinitionRegistry`). The definition is the codec, the schema the editor's inspector is built from, and the hook for how the component presents itself:

| Member | What |
|---|---|
| `type` | the saved `type` string — stable: renaming it orphans saved levels |
| `aliases` | older names still read (never written) |
| `id` | an optional short id |
| `create` | makes a default component to decode into |
| `fields` | `FieldDefinition`s: `name`, `kind` (a `FieldType`), `read`, `write`, `min`, `max`, `enumParser` |
| `parent` | a definition whose fields this one inherits (for a component subclass) |
| `hints` | `ComponentHints` — editor presentation: name, group, description, icon, accent colour, field groups and rows, per-field `FieldHint`s, `Dimensions` (§18) |
| `extent` | `ComponentExtent` — the size the component implies, how to scale and flip it, its 3-D bounds |
| `painter` | `ComponentPainter` — for a component that draws itself (`ComponentPainterPass`, §10.2) |

A component saves as `{"type": ..., "fields": {...}}`. `ComponentDefinition` is a definition that also writes a `customComponentId` (the shape older editor components were saved in). `ComponentCodec` is the lower-level interface (`type`, `encode`, `decode`) for a hand-written codec.

`ComponentDefinitionRegistry` has `register(codec, {override})`, `registerAll(codecs, {override, ifAbsent})`, `encode(component)`, `decode(json)`, `definitionByType(typeOrAlias)`, `definitionFor(component)`, `byName`, `forComponent`, `types` and `definitions`; and `registerUnknownTypeHint(type, hint)` / `unknownTypeHint(type)`, how to make a type known that is not registered (§9.3). Each feature's definitions are in its folder (`Shape2DDefinitions`, `GameplayDefinitions`, `CameraDefinitions`, …); `BuiltInComponents.all` lists them all and `BuiltInComponents.registry()` makes a fresh registry with them and the ECS core's own (`EcsDefinitions`), which every context has (§5.1).

### 9.2 Field types

`FieldTypes` holds the ECS core's kinds, registered in every context's `fieldTypes`: `boolean`, `integer`, `decimal`, `text`, `assetRef`, `entityRef`, `tagRef`, `tagList`, `spawnerRef`, `target` (and `targetOrSelf`), `enumeration`, `list`, `map`, `vector2`, `vector3`, `euler`, `color`, `offset`, `offsetList`, `shapePaintStyle`, `edgeInsets`, and `unknown` (kept and written back as raw JSON). A feature's own kinds live with its definitions and are registered with them: `PhysicsDefinitions.layerType` (one collision layer), `layerMaskType` (the layers a collider meets) and `shapeType` (a 2-D collision shape, for a game's own components), and `Material2DDefinitions.overridesType` (a 2-D material's values changed per entity), all through `BuiltInComponents.extension` (`BuiltInComponents.fieldTypes`); `Material3DDefinitions.overridesType` through `Graphics3D`, and `Physics3D` registers the layer kinds itself, for a context given only 3-D physics. `FieldTypeRegistry.registerAll(types, {override, ifAbsent})` — `ifAbsent` keeps a project's replacement. A field type knows how to encode and decode its value, its `channels` (the parts a timeline keys one by one: `x`, `y`, `z`) and `channels2D` (which of them a 2-D scene shows).

### 9.3 Scenes and SceneLoader

A scene file (`assets/scenes/<name>.scene.json`, see `SceneAssets`) is:

```json
{
  "version": 11,
  "name": "level_01",
  "mode": "2d",
  "entities": [
    { "name": "Player", "parentName": null, "enabled": true,
      "components": [ { "type": "TransformComponent", "fields": { ... } } ] }
  ]
}
```

`SceneLoader.load(world, json, {codecs, hooks, onMigrated})` (and `loadString`, `loadAsset`) reads one into a world:

1. The file is migrated in memory to the current format (§9.4) with `hooks` (default `world.context.migrations`); `onMigrated` hears what the migration found. The file on disk is never rewritten.
2. Prefab instances are expanded: `PrefabExpander.expandScene(entries, world.context.prefabLibrary.loaded)` replaces each entry that places a prefab with the prefab's entities and the instance's changes. A prefab that is not loaded is logged, and its entry stands as an empty entity.
3. Every component of every entry is decoded with `codecs` (default `world.context.definitions`) **before** anything is created. A type nobody registered throws `UnknownComponentTypeException`, naming the type and the entity, with the registry's `unknownTypeHint` for it as its `hint` — `BuiltInComponents.extension` gives one for each 3-D component (`BuiltInComponents.graphics3DTypes`, `physics3DTypes`: core names them as strings, the ECS core not at all), saying which service to give the engine; the world is left untouched.
4. Every entry becomes an entity, one with no components too (a folder in the tree). Entries saved with `enabled: false` are switched off.
5. Parents are linked by name through `SceneLoader.parentIndices(entries)`: the file lists parents before their children, so a repeated name resolves to the entry on the way down; failing that, the nearest earlier one, with a message. Both `ParentComponent` and `ChildrenComponent` are made where the file leaves one out.

`loadAsset` reads from `world.context.bundle` without caching, and first awaits `world.context.prefabLibrary.loadScene(json)`, so the prefabs the scene places are loaded; a caller of `load` loads them the same way first. `SceneLoader.loadManifest()` reads `assets/scenes/scenes.json`, the play order, from `rootBundle` unless given a `bundle:` (not from the context's bundle). The editor writes scenes; the engine only reads them.

### 9.4 Migrations

`SceneFormat.current` is 11. A file without `version` is v0. Each step is a `SceneMigration` (`from`, `apply(json, MigrationRun run)`), listed in `SceneMigrations.chain`. The steps live in `just_game_engine_formats`; the engine re-exports `SceneFormat`, `MigrationHooks` and the results, not the steps (import the formats package to name one):

| Step | What it changes |
|---|---|
| `V0ToV1` | every component becomes `{type, fields}` (core components were stored flat) |
| `V1ToV2` | the camera becomes virtual cameras: `VirtualCameraComponent`, confiner bounds, framing from the old follow settings |
| `V2ToV3` | sprites play from an atlas (`SpriteAnimationComponent`); entities whose old grid description has no atlas are listed in `needsAtlas` |
| `V3ToV4` | keyframe animation becomes an inline timeline on a `TimelinePlayerComponent` |
| `V4ToV5` | UI text keeps its style |
| `V5ToV6` | every entity is 3-D: `position.z`, `rotation {x, y, z}`, `velocity.z`; parent offsets are no longer saved (they follow from the world transforms); the legacy `root` tree goes; `mode` is written; inline timelines move to timeline format 2 |
| `V6ToV7` | tags and targets: `tag` becomes `tags`, `SpawnComponent`'s tag becomes `spawner`, every name-else-tag pair becomes one `EntityTarget` |
| `V7ToV8` | physics bodies: `isStatic` becomes `bodyType`, collision bits become `layer` and `collidesWith`, a collider follows its entity's scale |
| `V8ToV9` | one physics model for 2-D and 3-D: a `PhysicsBodyComponent` becomes a rigid body and a collider beside it; the joints are renamed |
| `V9ToV10` | a scene entry may place a prefab (a `prefab` block) and name an entity inside one as its parent |
| `V10ToV11` | every component's name ends in `Component`, tagged `2D` or `3D` when it has both versions (`RigidBody2DComponent`, `Light3DComponent`), here and in what a prefab instance changes |

`SceneFormat.migrate(json, {hooks})` returns the current-format scene; `migrateWithReport(json, {hooks})` returns a `SceneMigrationResult` (`scene`, `fromVersion`, `migrated`, `needsAtlas`, `notes` — `MigrationNote`s a person may want to read). Neither mutates its input. A scene newer than `current` throws `UnsupportedFormatVersionException` (a `FormatException`) instead of being misread.

A package adds its own rules through the context's `MigrationHooks` (`context.migrations`), normally from its extension:

| Hook | Runs |
|---|---|
| `v0Components[type]` | v0 → v1, instead of the engine's rule for that type |
| `perEntity(from)` | the step from `from` (1–10), after the engine's rules: one component becoming several, or moving to another entity |
| `perType(from)[type]` | the step from 5 to 10, on a component's `fields` |
| `targetPairs[type]` | v6 → v7: a package's own name/tag/target field triples |
| `renamedTypes[type]` | v10 → v11, and timeline v2 → v3: a package's own renamed components, old name → new |
| `perTrack` | timeline v1 → v2, per track |

`MigrationHooks.none` is frozen and empty. Every run gets its own `MigrationRun`, so two migrations never share what they found.

### 9.5 Other versioned files

| File | Format | Reader |
|---|---|---|
| timeline (`.timeline.json`) | `TimelineFormat.current` = 3 | `TimelineAsset.parse` / `fromJson` (migrates with `TimelineFormat.migrate`) |
| level map (`.map.json`) | `LevelMapData.format` = 3 (1 and 2 still read; before 3 a layer's `castShadows` was `castsShadows`) | `LevelMapData.fromJson` |
| tileset (`.tileset.json`) | `TilesetData.format` = 1 | `TilesetData.fromJson` |
| tag library | `TagLibrary.formatVersion` = 1 | `TagLibrary.fromJson` |
| animator graph (`.animator.json`) | `AnimatorGraph.formatVersion` = 2 (written as 1 unless it uses crossfades or blend trees) | `AnimatorGraph.parse` |
| collision layers (`assets/project/physics.json`) | `PhysicsLayers.formatVersion` = 1 | `PhysicsLayers.fromJson` (through `context.loadPhysicsLayers()`) |
| prefab (`.prefab.json`) | `PrefabFile.formatVersion` = 1 | `PrefabFile.parse` / `fromJson` (through the context's `prefabs` loader) |
| 2-D material (`.material2d.json`) | `Material2DFile.formatVersion` = 2 (1, which keyed a colour value `colour`, still reads) | `Material2DFile.parse` / `fromJson` (through `Material2DLibrary`) |
| 3-D material (`.material.json`) | `Material3DFile.formatVersion` = 1 | `Material3DFile.parse` / `fromJson` (through `Material3DLibrary`) |

Every one of them throws `UnsupportedFormatVersionException` for a newer version.

---

## 10. Rendering

### 10.1 RenderingEngine

`engine.rendering` owns the frame (§7.6): the background colour, the camera it draws through, `backgroundHooks` and `overlayHooks` (`RenderHookChain`s), scene renderers (`addSceneRenderer`, `removeSceneRenderer`, `sceneRenderers`), the frame's `view` (`FrameView`, filled at most once a frame and only when read) and its `interpolation` (set by the engine each frame, §7.1), post-process passes (`addPostProcessPass`, `removePostProcessPass`, `postProcessPasses`), `screenPasses` (§7.6), `drawInterval` (the least time between two frames a `GameWidget` draws; null draws every frame), `drawingFrame` (the number of the frame `render` is drawing, counted from 1, and null between frames: every view drawn inside one `render` — an editor's panes — shares it), `debugMode`, and `stats`. `EngineConfig.createRendering` replaces it with a subclass.

`RenderingEngine` is a `RenderStatsSink`. Its `stats` count the whole frame: what it drew itself (the background clear, the screen passes) plus whatever other drawers report through `addFrameStats` while the frame is drawn. The ECS `RenderSystem` reports each `render()` to its `statsSink`, and the default systems make it with `statsSink: engine.rendering`, so `drawCalls`, `renderedObjects`, `culledObjects` and `batchedSprites` include the world's drawing. What is reported outside one of the engine's frames is dropped when the next one starts. The keys are listed in [STATS.md](STATS.md).

### 10.2 RenderSystem

`RenderSystem` (priority 40) draws the world. It needs `camera`.

- **What.** Every entity's `RenderableComponent`, every `RenderItem` of a `RenderItemsComponent` (a level map's layers, say), and every `ParticleEmitterComponent`'s emitter — one sorted draw list.
- **Order.** By layer, then `zOrder`, then sub-order; then renderables before particle emitters before render items, then the entity's id (the order entities were made in), then an item's place in its list — so two things on the same layer never swap from one frame to the next, nor when another entity comes or goes. An entity's keys come from its `LayerComponent`; without one, from its renderable's (or emitter's) own `layer` and `zOrder`, with sub-order 0 (0, 0, 0 when it has neither); a render item carries its own `layer`, `zOrder` and `subOrder`. The sub-order (`LayerComponent.subOrder`, `RenderItem.subOrder`) is how an entity on a map layer draws between that layer's tiles and the next's. Layer and `zOrder` are compared as two numbers; they used to be packed into one with a shift, which on the web sorted every negative layer last.
- **Cost.** The list is kept between frames and brought up to date only when one of its queries' versions moves (`world.queryVersion`) or an entity's render items change, and then only what changed is: the entries still there stay in order, what went is dropped, and what came is sorted and merged in. Each frame refreshes the keys and re-sorts by insertion (one pass when nothing moved). Each entry holds its entity's components, found once per archetype.
- **Parts.** `render_system.dart` (in `graphics/graphics_2d/`) is the system; the renderer's other files beside it are its internal pieces (`@internal`, §2.2): `RenderQueue` (`render_queue.dart`, the draw list above), `RenderBatcher` (sprite, shape and 2-D material batches, and the frame's counts), `RenderBounds` (a renderable's world extent, for culling and shader layers), `ShadedDraw` (a renderable through its entity's `ShaderComponent`), `Lighting2DDrawer` (the normals and shadow casters `Lighting2DPass` reads, from the same queue; a render item that is a `Lighting2DItem` — a level map's layer — draws its own) and `ShapeBatch` (`batchShapes`).
- **Transforms.** Each renderable is synced from its `TransformComponent`. A renderable whose transform captured its previous pose in the last fixed update (`TransformComponent.captureCount` — moving physics bodies and characters, and children of them) is drawn between its previous and current poses by `interpolation`, which `RenderSystem` takes in its `frame` phase; anything else is drawn where it is. A transform seen for the first time is drawn between its poses when the world's latest update captured it (`TransformComponent.capturedInUpdate`, the `World.updateCount` of its last capture, runtime state the world binds as the transform joins an entity). A static body is placed, not stepped: physics settles its previous pose (`settlePrevious`), which is not a capture.
- **Within a key.** Renderables with `ySort` are drawn after the rest of their layer, zOrder and sub-order, by world y, through the same batch and shader path. An entity with no `LayerComponent` is keyed by its renderable's own `layer` and `zOrder`; a sprite from another image ends the pending batch, so batching never changes the order.
- **After the list.** The `passes` run, in ascending order: by default one `ComponentPainterPass`, which draws every component whose definition has a painter (world-space text and buttons from `just_ui_editor`, for one).
- **Filters.** `shouldRender` lets a tool skip entities without touching them. An entity on a hidden map layer (`LayerComponent.hiddenByMap`) is skipped here and in every pass. `RenderSystem.debugDrawOrder()` lists the order, for tests.
- **Counts.** `RenderSystem.stats` holds what the last `render()` drew (`drawCalls`, `renderedObjects`, `culledObjects`, `batchedSprites`; the passes' own drawing is not counted), and the same counts go to `statsSink` when it has one (§10.1).

### 10.3 Batching

- **Sprites.** A `BatchableSprite` goes into a `SpriteBatch` — one `Canvas.drawRawAtlas` call per batch — when `SpriteBatchPlan.plan` accepts it: an image, one uniform positive scale (a mirrored or stretched sprite draws alone), and a render size that keeps the source's proportions. Batches are kept per image object *and* filter quality, so pixel art stays sharp, and a batch unused for a frame is dropped. Pending batches are drawn before anything that is not batched and whenever the draw key (layer, `zOrder`, sub-order) changes, so batching never reorders the layers.
- **Shapes (opt-in).** `RenderSystem(batchShapes: true)` draws runs of plain rectangles and circles in one `Canvas.drawVertices` call. Off by default: triangles are not anti-aliased, and a circle becomes a 16- or 24-sided polygon.

### 10.4 Culling

- `RenderSystem(cullOffscreen: true)` (off by default) reads the visible area from the canvas once a frame (`getLocalClipBounds`) and skips renderables whose bounds miss it. Render items and particle emitters are always drawn. It is only as good as each renderable's `bounds`.
- `ViewCullingSystem` (opt-in, priority 91) marks entities near the camera on their `CullStateComponent`: outside the render radius the renderable is hidden (only on the edge crossing, and only what it hid itself is shown again); outside the larger active radius `MovementSystem` and `Physics2DSystem` skip the entity.

### 10.5 Shaders

A `ShaderComponent` draws its entity through a fragment shader (an offscreen layer with `ImageFilter.shader`). One with `isPostProcess` becomes a full-screen `PostProcessPass`, kept in step with the rendering engine by `PostProcessSystem` (opt-in, priority 35). `ImageFilter.shader` works only under Impeller; on the web and on Skia it throws. Every shaded effect asks `ShaderFilterSupport.check(effect)` first: where it is not supported the content is drawn without the effect and a line is logged once per kind of effect.

### 10.6 Particles and parallax

- **Particles.** A `ParticleEmitterComponent` holds a `ParticleEmitter`. `ParticleSystem` (priority 48, not a default) updates it, keeps it at its entity, and can destroy the entity when the emitter completes (`removeEntityWhenComplete`). `RenderSystem` draws it in layer order.
- **Parallax.** A `ParallaxComponent` holds a `ParallaxBackground` of `ParallaxLayer`s. `ParallaxRenderSystem` (priority 105, part of `DefaultSystem.rendering`) scrolls it and draws it through `backgroundHooks` in screen space, behind the world, with the camera's position and zoom at draw time. Each layer repeats across, down, both or neither (`repeatX`, `repeatY`).

### 10.7 Removed: the legacy render path

Before the ECS drew everything, games added renderables to the rendering engine directly. 2.0 removed that path, with its own layer lists, quadtree culling and sprite batches; the world's `RenderSystem` is the one drawer:

| Removed | Use instead |
|---|---|
| `RenderingEngine.addRenderable` / `removeRenderable`, `renderables`, `renderableCount`, `layerCount`, `markLayerOrderDirty`, `markSpatialIndexDirty`, `useSpatialIndex` | a `RenderableComponent` on an entity; `RenderSystem(cullOffscreen: true)` for culling |
| `RenderingEngine.onRenderBackground` / `onRenderOverlay` | `backgroundHooks` / `overlayHooks` (`add`, `remove`) |
| `Engine.parallax`, `ParallaxSystem` | `ParallaxComponent` + `ParallaxRenderSystem` |
| `RenderingEngine.addManagedEmitter`, `removeManagedEmitter`, `updateManagedEmitters` | an emitter on an entity, `ParticleEmitterComponent(removeEntityWhenComplete: true)`, which `ParticleSystem` updates and `RenderSystem` draws |
| `RectangleRenderable`, `CircleRenderable`, `LineRenderable` | the 2-D shape components (`Rectangle2DComponent`, …), or a `CustomRenderable` |
| `RenderingEngine.spriteBatchFactory` | `RenderSystem(spriteBatchFactory:)` |

The other deprecated 1.x members went at the same time: `Engine.getSystem` (use `subsystem`), `HierarchySystem` (every world keeps its hierarchy, §7.5), `Entity.generation` (ids are never reused, §8.7), `TagComponent.tag` (use `tags`), the unused lifecycle interfaces (`IUpdatable`, `IRenderable`, `IPausable`, `IEnableable`, `ILifecycle`, `LifecycleStateMixin`), `offload`, the `GameLoop` callback typedefs, `ParallaxLayer.repeat` (`repeatX`, `repeatY`), `SpriteSheet` (an atlas) and `ViewCullingSystem`'s ignored `gridCellSize`. [MIGRATION.md](MIGRATION.md) lists them for games.

---

## 11. Physics

### 11.1 Two backends, one API

`engine.physics` is a `Physics2DEngine` from `just_physics_engine`. Its `Physics2DEngine()` factory picks the backend at compile time:

- **Native platforms** get a `Box2DPhysicsEngine` — Box2D v3 through FFI. If the native library will not load, its `initialize()` logs that and falls back to the pure-Dart simulation.
- **The web** gets the pure-Dart engine (fixed 1/60 s sub-steps, at most five a frame).

Both have the same API: bodies (`Physics2DBody`, with `Circle2DShape`, `Rectangle2DShape`, `Polygon2DShape`, `Capsule2DShape` and more), joints, ray and shape casts, `setGravity`, and contact and sensor events. Default gravity is `(0, 981)`. The engine re-exports the names games need with a `show` list.

### 11.2 Physics2DSystem

`Physics2DSystem(engine.physics, {reportContactStay})` (priority 90) is the ECS front end. It owns a body for every entity with a `TransformComponent` and a `Collider2DComponent`. The collider is the body's shape; the entity's `RigidBody2DComponent`, if it has one, says how it moves, and without one the body is static — the model 3-D physics has (`lib/src/physics/physics_3d/`), with the same names. Like `Physics3DSystem`, it is a small system over parts it owns: `Physics2DBodies` and `Physics2DContacts` (internal, §2.2), and the public `Physics2DJoints` and `Physics2DCharacters`; what both dimensions share (`ContactPairs`, `BodyRebuild`, the field descriptions in `PhysicsDefinitions`) is in `physics/`. Each update it:

1. **syncs in** — makes bodies for new entities (and adds a `Physics2DBodyRefComponent`, which stays through a rebuild), removes bodies of entities that left, rebuilds a body whose collider changed (for `matchShape`, whose drawn shape changed — read from the shape's `SolidShape2DSource`), and copies settings, velocities, teleports and the forces, impulses and velocities queued on `RigidBody2DComponent` into the bodies. A kinematic body moved through its transform is driven by velocity, also on updates that run no step;
2. **makes and keeps the joints** (`Physics2DJoints`), so a joint made or made again holds from the step its bodies are in;
3. **moves the characters** (`Physics2DCharacters`, below);
4. **steps** `physics.update(dt)` — inline, in the ECS pass (§7.2); a world with no bodies is not stepped;
5. **syncs out** — body poses into `TransformComponent` (a static body only when it was made or teleported, and then it settles its previous pose rather than capturing it) and velocities into `VelocityComponent`, keeping the previous pose for render interpolation;
6. **dispatches** `CollisionEnter2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent` and `SensorExit2DEvent` on `world.events` (and `CollisionStay2DEvent` once per physics step while `reportContactStay` is on — never on an update that ran no step), and keeps `RigidBody2DComponent`'s `isGrounded`, ground and velocities up to date (a body that touched something from the side and then rests on it is grounded, with that surface's normal). A collision event carries the two entities, the contact `normal`, a `point` worked out from where their bounds meet and a `depth` of 0: no backend reports either in 2-D.

Details:

- Its list of entities is rebuilt only when the versions of the queries it reads move (`world.queryVersion`).
- A switched-off entity leaves the simulation; switched back on, it gets a fresh body where its transform then is.
- **Sleep.** A body at rest may fall asleep, as the physics engine decides. Anything the ECS does to it wakes it: a velocity different from the one the last step left, a teleport through the transform, a force or torque waiting to be applied, a changed `RigidBody2DComponent` or `Collider2DComponent` setting, a return from view culling, or a change of gravity.
- **Removal.** Taking the system out of its world, or disposing it, removes every body it made, so none stay behind colliding as ghosts.
- `MovementSystem` skips entities with a `Collider2DComponent`: physics moves them.
- It draws nothing. Collider outlines have one drawer, `Collider2DDebuggerSystem(camera:, outlineFilter:)` (priority `debug`, 10): `GameWidget(showDebug: true)` adds one through the main camera, and an editor adds its own while it shows colliders. It outlines every collider as simulated, coloured by body kind, every character and every body made outside the ECS; `outlineFilter` picks the entities, and `Collider2DComponent.showDebugOutline: false` hides one.
- `Physics2DQueries` (`physicsSystem.queries`, or `Physics2DQueries(system)`) casts rays and circles and finds overlaps through the physics engine, answering with entities; `overlapBox` tests shapes, not their bounds. `Physics2DSystem.bodyOf(entity)` is the way from an entity to its body.
- **Ray traces.** `RayTracer2D(queries)` bounces a ray: each stretch is a `Physics2DQueries.raycast` with the trace's `layerMask`, `ignore` and `includeSensors`, so a trace hits exactly what the physics ray hits — there is no second collision model for rays. A hit collider's `Collider2DComponent.reflectivity` (saved, 0 by default) decides the rest: 0 absorbs the ray, as does a body with no collider component (a character); above 0 the ray is mirrored about the hit normal and goes on with what was left of its length times the reflectivity, less `RayTracer2D.bounceOffset`. It ends when nothing is left, when it hits nothing, or after `maxBounces`. The tracer only reads the collider; the 3-D side has no tracer, so `Collider3DComponent` has no reflectivity yet.
- **Characters.** Before stepping, `Physics2DCharacters` moves every `CharacterBody2DComponent` with just_physics_engine's `CharacterMover2D` through the world as the last step left it — the recipe `Physics3DSystem` uses: on the ground it moves with the ground (and jumps from it), in the air it keeps its vertical speed, then gravity and `moveVelocity`. A detectable character keeps a kinematic body where it is, registered as its entity's, so sensors and rays see it and its contacts with dynamic bodies are its collision events. `MovementSystem` skips characters as it skips colliders.

- **Joints.** `Physics2DJoints` makes and keeps the joints from `DistanceJoint2DComponent`, `FixedJoint2DComponent`, `SliderJoint2DComponent` and `WheelJoint2DComponent`, each joined to the body its `connectedBody` (an `EntityTarget`) names (where native wheel joints are missing, a wheel is the physics engine's own Dart wheel joint). A joint is made again when its component changes or either body is made again; a weld made again holds the bodies where it held them. What the joints cannot pass to the physics engine yet is in §20.4.

Related: `Physics2DSystem.entityOf(body)` maps a body back to its entity. `BodyRebuild.scaleTolerance` (in `physics/`, shared with 3-D) is how small a change of scale rebuilds no body, and `Collider2DGeometry` builds, measures (`massOf`, `autoMassPerSquareUnit`) and paints a collider's shapes.

### 11.3 3-D physics

`lib/src/physics/physics_3d/`, public as `package:just_game_engine/just_game_engine_3d.dart`: the 3-D components and their definitions, `Physics3DSystem`, the queries and events, the camera's collision stage, and `Physics3D`, the only way in. The simulation is just_physics_engine's `Physics3DEngine` (`JoltPhysicsEngine`, on just_jolt's bindings), so the chain is just_jolt → just_physics_engine → this engine, and nothing depends the other way.

**2-D games carry none of it.** Nothing outside the folder names its code: a game gives the engine a `Physics3D` in `EngineConfig.services`, and the engine reaches it only as a `ContextExtension` and an `EngineService`; `engine.physics3D` is an extension, on `GameEngine`, in the folder itself. `Physics3D`'s install registers the 3-D definitions (`Physics3DDefinitions`); they are in no default list. A game that never makes a `Physics3D` gives the compiler no way to reach the folder, the Jolt engine or the bindings, and tree shaking drops them all. `test/physics/physics_3d/physics_3d_boundary_test.dart` fails when anything else in `lib/src` imports the folder or calls `create3D`, `JoltPhysicsEngine`, `Physics3DDefinitions` or `Physics3DSystem` directly; the CLI's `check release-build` fails a 2-D game's release that holds 3-D names or Jolt's library. Jolt's native code is a separate matter: tree shaking never removes native code, so just_jolt's build hook compiles nothing unless the app's pubspec asks (`hooks: user_defines: just_jolt: build: true`).

**At run time.** `Physics3D.install` (as the engine is made) registers the definitions and `CameraCollision3DStage`; `start` (as it initializes) makes the physics engine — `PhysicsEngineFactory.create3D()`, which throws `Physics3DUnsupportedError` on the web or when Jolt was not built — and adds a `Physics3DSystem.lazy`. The world (Jolt's job system is the process's; a world brings its tables for 10,240 bodies and its temporary allocator) is made only when the first 3-D body or character appears; until then an update is one structure check, and `Physics3DQueries` find nothing. Each step sends what gameplay set, moves characters, steps, reads the moved bodies' poses in one batch (14 floats each) and drains the events once. `Physics3DSystem` is a small system over its internal parts, as `Physics2DSystem` is: `Physics3DBodies`, `Physics3DJoints`, `Physics3DCharacters` and `Physics3DContacts`, with `ContactPairs` and `BodyRebuild` shared from `physics/`; it no longer imports the 2-D folder. The layers a world keeps apart are fixed when it is made (§20.4).

---

## 12. Input

- `engine.input` is an `InputService` from `just_inputs`: devices, the input asset (`InputActionAsset`), action maps and actions, players (`PlayerInputManager`, `PlayerInput`) and rebinding (`RebindingOperation`). It starts with no actions; the game loads its asset after `initialize()`.
- **Events.** `GameWidget` forwards key events (`handleKeyEvent`) and pointer events on the canvas (`handlePointerEvent`). Keys a layer lets go of bubble on to the input too — only key-ups while a text field has focus. When the game loses keyboard focus, held keys are released (`releaseKeyboard`), since their key-ups would never arrive.
- **Updates.** Once per fixed step (the `input` task, §7.2) and every frame while paused, so menus and rebinding still hear the player. The input clock is real time, not scaled.
- **Persistence.** The bindings players change are saved through `CacheInputOverrideStore` (`input.overrideStore`): engine settings kept beside the cache, which `CacheManager.clearAll()` leaves alone.
- **ECS.** `InputSystem` (priority 100) copies the actions of its `maps` (`['player']` by default) into each `InputComponent` by short name — `vectors`, `axes`, `down`, `pressed`, `released`, `performed` — for the component's `playerIndex` (−1 reads the shared actions of every device). A component whose player is not playing is cleared. `SimpleMovementComponent` with `SimpleMovementSystem` moves an entity straight from input, for prototypes.
- **Gamepads** come in through a `GamepadSource` (`JustGamepadsSource` by default), on every platform, browsers included (§19.2).

---

## 13. Audio

- `engine.audio` (`AudioEngine`), `engine.music` (`MusicManager`) and `engine.sfx` (`SoundEffectManager`) come from `just_audio_engine`. `EngineConfig.createAudio` builds another, for example `AudioEngine.withBackend(...)`.
- **On the web the audio engine starts at the first key or pointer press** anywhere in the app, not in `initialize()`. A browser keeps an audio context made before any user gesture suspended, and `just_audio_engine` makes its context when it initializes. `EngineConfig.deferAudioUntilInput` chooses (null: on the web only). A sound played before that press starts the audio engine early, and the browser may then keep it silent.
- An initialization error is logged and the game goes on without sound (headless runs, tests, a platform without the plugin).
- **ECS.** `AudioSystem` (priority −10, a `PerFrame`) starts `AudioSourceComponent`s on the fixed step, carries out their `AudioRequests` (`pause`, `resume`, `stop`) and plays the one-shots asked for with `playOneShot`, and drives `AudioStreamComponent`s — once the audio engine has started. A switched-off entity's sound pauses and plays on when it is switched back on; `suspend` / `resumeSuspended` pause and restore everything for the app's background (`Engine.suspendAudio`, which `GameWidget` calls). While the engine is paused the audio engine still updates every frame, so volume changes are heard. Once per rendered frame, after the camera has moved, it sends the listener's pose (`AudioListenerComponent`, or the camera when there is none) and each moved 3-D source, only when they change. It stops what a removed component or entity played.
- **3-D sound is worked out in Dart**, by `just_audio_engine`: the `audio` frame task (`AudioEngine.update`, last in the frame) turns each 3-D sound's position, the listener and their velocities into a volume, pan, pitch and low-pass cutoff (`AudioSpatial.mix`) and sends the ones that changed to the platform in one call. Every platform hears the same; none of their own 3-D engines is used.
- A 3-D source (`is3D` on an entity with a transform) is placed, not panned. A sound plays on its component's `channel`.
- A timeline's audio track plays through `context.timelineAudio`, by default `TimelineAudio.viaAudioSystem`, a one-shot from the world's `AudioSystem`.
- Disposal starts the audio shutdown; `engine.dispose()`'s Future waits for it.

---

## 14. Assets and Storage

### 14.1 AssetManager

Each context has one `AssetManager` (`engine.assets`, `engine.context.assets`), so it is there before `initialize()`. It reads from the context's `bundle`.

- Typed loads: `loadImage`, `loadAudio`, `loadText`, `loadJson`, `loadBinary`, `load(path, AssetType)`, `loadMultiple`; a loaded asset is kept by path and returned again. `get<T>(path)` and `getImage` … `getBinary` read what is loaded.
- Reference counting: `acquire` / `release(path, type)`, counted per path *and* type (an atlas and its JSON are two), and scoped forms (`acquireScoped`, `acquireImageScoped`, …) that release when a `MemoryScope` (`createScope`) is disposed. An asset only a plain `load` asked for is not unloaded by the last `release`, and a load cancelled by a release takes no other owner's count. `AssetScope` and `GameAssetBundle` group assets that load and unload together. `retainOnly(paths)` unloads every asset not named and not acquired — between levels, keep what the next one uses.
- The memory total (`totalMemoryUsage`) is kept as assets come and go; a JSON asset is measured once, when it loads.
- **Between levels.** The engine never swaps scenes itself. A game that does calls `Engine.releaseUnused()` once the next level is built: it runs `LevelMaps.evictUnused(world)` (map files, tilesets and the tileset images only those drew from), `Material2DLibrary.retainOnly` with the 2-D materials the world's entities and map layers still name (the sprite loader forgets the images only the others used), and `releaseUnused()` on every `SceneCacheService` — an `EngineService` that keeps what scenes use, as `Graphics3D` does (its models, 3-D material files and maps, `Graphics3DSceneRenderer.releaseUnused`). What the world still uses stays, and so does what an `acquire` holds or a plain `load` asked for: the game lets those go with `release`, `unload` or `retainOnly`. An editor, which keeps the maps it edits, calls the parts it wants instead.
- Loaders are per `AssetType` (`registerLoader`); the constructor registers the built-in ones, and `SpriteAtlas.fromAsset` registers the atlas loader.
- `totalMemoryUsage`, `assetCount` and `cacheStats` report what is held (see [STATS.md](STATS.md)).

**Bundle assets are not persisted.** An asset is read from the bundle each time it is loaded; the decoded image stays in memory until it is unloaded, and `ImageAsset` drops the encoded bytes once decoded. Nothing from the bundle is copied into the engine's persistent cache — a copy kept across runs outlived the asset it was made from, so an update shipping a new image went on drawing the old one. `CacheManager` removes the copies older versions made, once.

Sprites and atlases load through the context's `sprites` loader (`SpriteAssetLoader`; a `BundleSpriteAssetLoader` over the `AssetManager` by default). `Sprite.fromAsset(path, assets: …)`, `Sprite.loadImageFromAsset(path, assets: …)` (the caller owns the returned clone) and `SpriteAtlas.fromAsset(jsonPath, assets: …)` take the manager explicitly: nothing in the engine reaches for a global one.

### 14.2 CacheManager

`engine.cache` persists what the game (and the engine) wants kept between runs:

- strings and JSON — `setString`, `getString`, `setJson`, `getJson`, `remove` — in a key-value store;
- binary data — `setBinary`, `getBinary` — in a database named `just_game_engine_cache`, with optional eviction of the oldest entries past `maxBinaryEntries`;
- `clearAll()` removes only the cache's own entries.

Every key the cache writes is under `CacheManager.keyPrefix` (`just_game_engine.cache/`). Engine settings — players' bindings — sit under their own prefix in the same store, which `clearAll()` never touches. Keys may hold any character: in the binary database anything outside letters, digits and `_ . - /` is `%XX`-encoded, and a very long key keeps its start and ends in a hash.

When a store cannot be opened or stops accepting writes, its entries are kept in memory for the rest of the run: `isUsingMemoryFallback` (no key-value store) and `isBinaryInMemory` (no database) say so. Tests and headless runs end up there. The in-memory binary entries are held to a byte budget (`CacheManager(maxMemoryBinaryBytes:)`, `defaultMaxMemoryBinaryBytes`, 32 MB), the least recently used dropped first.

### 14.3 The engine's own storage file

The key-value store is the engine's own, not the app's:

| Platform | Where |
|---|---|
| desktop and mobile | `<application support>/just_game_engine/just_storage.json` — a file beside the app's `just_storage.json`, found with `path_provider` (`storage/engine_storage_io.dart`) |
| web | browser `localStorage`, every key under the `just_game_engine/` namespace (`storage/engine_storage_web.dart`, `storage/namespaced_storage.dart`) |

`just_storage` rewrites a whole file from the copy each instance loaded, so two instances on one file drop each other's keys; a separate file is the only safe way to share a device with app code. Before 2.0 the engine wrote into the app's file. On the first run, `CacheManager.initialize()` moves the engine's entries (its prefixed keys, and players' bindings saved before 2.0) into its own store, deletes them and any pre-2.0 bundle-asset copies from the app's file, leaves everything else there alone, and writes a marker so it never opens the app's file again. A failed move is retried on the next run.

---

## 15. Cameras

- **The output camera** is `engine.camera.mainCamera`, an `OutputCamera` (`camera/output_camera.dart`). It holds a position, a zoom, a roll (`rotation`), a depth (`z`), a pitch, a yaw and a `lens` (`CameraLens`); it turns them into a canvas transform, converts between screen and world, and carries the post effects (`effectManager`, a `CameraEffectManager`: pre-render, post-render and screen-space effects such as fade and letterbox). It decides nothing.
- **Shots** are entities with a `VirtualCameraComponent`: a priority, a follow target (`EntityTarget`) and a lens. Behaviour comes from components: `CameraFramingComponent`, `CameraGroupFramingComponent`, `CameraDollyComponent`, `CameraNoiseComponent`, `CameraImpulseListenerComponent`, `CameraConfinerComponent`; managers choose among cameras (`CameraStateDrivenComponent`, `CameraBlendListComponent`, `CameraMixerComponent`).
- **3-D rigs.** `OrbitFollowComponent`, `FirstPersonComponent` and `LookAtComponent` (`camera_rig_3d_components.dart`, their stages in `stages/rig_3d_stages.dart`) orbit a target, look from its eyes or aim at it; they need no 3-D package. `Physics3D` adds `CameraCollision3DStage` (`CameraCollision3DComponent`), which keeps a camera out of walls.
- **The brain** (`engine.camera.brain`, a `CameraBrain`, `camera/camera_brain.dart`) runs in `CameraBrainSystem` at priority 45 — after everything has moved, before rendering — so a shot frames where its target *is*. By default (`CameraBrain.updateMode` = `CameraUpdateMode.fixed`) it evaluates on each fixed update. With `CameraUpdateMode.frame` it only samples its targets on the fixed update and evaluates once per rendered frame (`CameraBrainSystem` is a `PerFrame`, §7.1), at the frame's interpolation, so a camera following an interpolated body moves smoothly. It runs each live virtual camera's stages (group framing, framing, dolly, the 3-D rigs, noise, impulse listener, confiner) to a `CameraState`, picks the enabled one with the highest priority, and blends the output camera toward it. With no virtual camera in the world it does nothing, so a game that moves the camera by hand is left alone.
- `CameraTargetGroupSystem` (47) keeps target groups current; `CameraTriggerSystem` (46) applies trigger zones' priority boosts.
- `CameraImpulseBus` (`brain.impulses`) numbers its noise seeds itself, so the same impulses in the same order shake the same way each run. `CameraBrain.reset()` forgets camera memory, noise time and seeds (an editor does it when a play-test starts); the brain also resets itself when its world is emptied (`World.clearCount`, moved by `destroyAllEntities`), so a level loaded after another starts with a cut. A camera's first frame is a snap for every stage.
- The stages and managers a brain runs come from `context.cameraRegistries` (`CameraRegistries`: one set per engine, which a kit's extension adds to); a `CameraBrain` made on its own keeps a set of its own.
- `camera.update` runs once per tick from `Engine._frame`, on real time, paused or not, and only advances the output camera's post effects (§7.1).

`CameraEngine`, the brain and the `OutputCamera` all live in `camera/`, which sits below `rendering/` and `physics/` (§2.3): `RenderingEngine` draws through the output camera, and `Physics3D` adds its stage to `context.cameraRegistries`. The output camera imports nothing else from the folder but its effects and state (§2.1).

---

## 16. Timelines and Animation

### 16.1 Sprites and atlases

`SpriteComponent` draws an image or an atlas region; `SpriteAnimationComponent` (`atlasPath`, `clip`) plays a clip from an atlas. `SpriteLoadSystem` (69) loads through `context.sprites`; `SpriteAnimationSystem` (68) advances clips (a negative speed plays backwards; frame events fire once per crossing). Atlas parsers: `TexturePackerAtlasParser` (JSON array, hash, multi-page), `AsepriteAtlasParser`, `GridSheetAtlasParser`. Trimmed or rotated regions (`AtlasRegionSprite`) draw by themselves, never batched.

### 16.2 Animator graphs

`AnimatorComponent(graphPath: …)` runs an `AnimatorGraph` (`.animator.json`, loaded through `context.animatorGraphs`): states that each play a clip, transitions that fire when their conditions hold, and parameters. `AnimatorSystem` (70) evaluates it. A parameter can be bound to an `AnimatorBindings` source (`speedX`, `alive`, …) that writes it every frame, so a game needs no animation code; packages add bindings to `context.animatorBindings`.

### 16.3 Timelines

A `TimelineAsset` (`.timeline.json`, format 3, or inline in a component) is a set of tracks over time. The engine has seven track kinds: `property` (keys any component field's channels on a `KeyCurve`, with easings from `context.easings`), `event` (fires named events, and emits them on `context.signals`), `spriteClip`, `cameraShot`, `audio`, `activation` and `nested` (plays another timeline).

- `TimelinePlayerComponent` plays one; `TimelineSystem` (72) drives one `TimelinePlayback` per player. The playback is disposed when its entity is destroyed or the component removed, and kept while the entity is switched off.
- `TimelineTriggerComponent` with `TimelineTriggerSystem` (73) starts timelines from trigger zones.
- `context.signals` (`TimelineSignals`: `emit(name)`, `stream`) is shared by every world on the context: a button on a UI screen can start a timeline in the level.
- A package adds track kinds to `context.trackKinds`. A track of a kind the engine does not know stays an `UnknownTrack` — saved back unchanged — and `TimelinePlayback` re-reads it with the world's kinds before playing.
- `TimelinePlayback` also works without a component (an editor's preview).

### 16.4 Deterministic effects

An `EffectComponent` holds an `EffectPlayer`; `EffectSystem` (65) advances it. The eleven effect types — `MoveEffect`, `ScaleEffect`, `RotateEffect`, `FadeEffect`, `ColorTintEffect`, `ShakeEffect`, `PathEffect`, `SequenceEffect`, `ParallelEffect`, `DelayEffect`, `RepeatEffect` — are tick-based, so the same inputs give the same result on every machine. `EffectSerializer` (with `context.effectTypes`) and `EffectSnapshot` save and restore running effects. Easings come from `Easings` through `EasingType`.

---

## 17. Level Maps

Level maps are part of the engine (`lib/src/level_map/`). A map's layers hold tiles; the things on a level are entities, and a child of the map entity can belong to one of its layers. A scene has one map. `just_tiled` is used only to read and write Tiled's own files.

### The parts

```
LevelMapComponent (saved: mapPath | inline)          ← the scene
      │
      ▼
LevelMapSystem (110) ── makes ──► LevelMapRuntime   (LevelMaps.runtimeFor(world, c) outside the system)
      │                          ├─ base: LevelMapData (never written by the game)
      │                          ├─ overlays: TileChunkStore.over(base) per layer
      │                          ├─ tilesets and images, through the world's context:
      │                          │    context.tiles, context.sprites, context.tiles.builtInImage
      │                          ├─ hiddenCells (drawing only)
      │                          └─ painter: MapLayerPainter
      ├─► RenderItemsComponent: one MapLayerRenderItem per layer ──► RenderSystem (40)
      ├─► children with LayerComponent.mapLayer: layerId / layer / zOrder,
      │   subOrder, hiddenByMap from their layer (a piece's items: overrides)
      ▼
MapCollisionSystem (108) ── TileCollisionBuilder (tiles of collides layers) ──► static-body entities
                                                           (MapBodyComponent + GeneratedEntityComponent)
```

* **Data.** `LevelMapData` → `MapLayerData` → `TileChunkStore` (sparse 16×16 chunks; the chunk key stays a 32-bit value, so it is exact on the web). A cell (`TileCell`) is tileset *slot* + tile id + Tiled's four flag bits; global ids exist only in exported Tiled files, so a tileset that grows does not renumber the others. `toJson()` always builds a new map and `fromJson()` copies — snapshots (play, undo) rely on it. A chunk that cannot be read is kept as it was, not erased on the next save.
* **Loading.** Map files and tilesets come through the world's `context.tiles` (`TileAssets`), which loads each once and shares it. A file that fails is reported once (`TileAssets.report`, `failureOf`) and not asked for again until its path changes or `TileAssets.revision` moves; `LevelMaps.preload(world)` returns the failures as `List<LevelMapLoadFailure>`. A runtime the system drops — its map replaced, its component or entity gone, the system disposed — is disposed with its images and pictures (`LevelMapRuntime.dispose`, `LevelMaps.release`). A game moving from level to level calls `engine.releaseUnused()` after the next level has loaded (§14.1); its `LevelMaps.evictUnused(world)` drops the map files and tilesets no map in the world uses, and has the sprite loader forget the tileset images only those drew from, so the tile caches do not keep every map.
* **Entities on a layer.** A child of the map entity whose `LayerComponent.mapLayer` (saved) names one of the map's layers belongs to it. Every update, `LevelMapSystem` sets the child's `layerId`, `layer` and `zOrder` from the layer's `sortLayerId`, `sortLayer` and `zOrder`, its runtime-only `subOrder` so it draws just above the layer's tiles and below the next layer's, and its runtime-only `hiddenByMap` to `!layer.visible`. A layer's render item gets the sub-order `(2i) << 16` and the entities on it `((2i + 1) << 16) + n` — `i` being the layer's index in the map and `n` the entity's index among the map's children — so members keep their order as children. An entity that leaves its layer is reset (`subOrder` 0, `hiddenByMap` false). `LevelMaps.ownerOf` and `memberLayer` answer which map and layer an entity is on. (This pass does not yet skip frames where nothing changed — §20.3.)
* **Pieces.** A child with its own `LevelMapComponent` and a `mapLayer` is a piece of that layer — tiles cut out of it to move as one thing (`LevelMaps.isPiece`). Its layers' render items get the parent layer's sort layer and z-order (`MapLayerRenderItem.layerOverride` / `zOrderOverride`) and the member's `subOrder`, so the whole piece draws in that layer's slot. Its collision is its own map's, static: rebuilt when it moves, as any map's is; moving a piece while the game runs is not supported yet.
* **Saved form.** `LevelMapData.format` is 3. A map saved as format 1 still reads, its layers' `castsShadows` as `castShadows`; one saved as format 2, which kept shapes in its layers, also reads, the shapes passed over. A newer map or tileset throws `UnsupportedFormatVersionException`. Layers without ids, or with repeated ones (from Tiled, or an old file), get fresh ids. A map of its own is a `.map.json` (`LevelMapFiles.suffix`); `.tilemap.json` from before the rename is still read, never written. The component saves as `LevelMapComponent`, and its definition's alias reads `TileMapComponent`.
* **One map per scene.** A level's map is the entity called `Level Map` (`LevelMaps.primaryName`); `LevelMaps.primaryEntity` / `primary` find it, falling back to the first map entity no system generated that is not a piece.
* **Geometry.** `MapGeometry` follows Tiled's four renderers. "Stable" coordinates (the map's own, the diamond lattice of a staggered map, axial hex coordinates) keep a block of cells in shape wherever it is placed; stamps and terrain use them.
* **Drawing.** Each layer is a `RenderItem`, sorted by its sort layer, then its `zOrder` (compared as two numbers, §10.2), so one map's layers interleave with sprites; it is a `Lighting2DItem` too, so 2-D lighting draws its normals (through the layer's 2-D material) and, when the layer casts shadows, its silhouette. `MapLayerPainter` walks only the chunks the camera sees. Batches are cached per chunk (orthogonal, isometric) or per band of chunk rows (staggered, hexagonal, whose rows overlap across chunks), rebuilt when a chunk's revision, a tileset or an image changes. Flipped tiles draw from a mirrored copy of the tileset image plus quarter turns. `RenderSystem` sorts every renderable and item by layer, `zOrder`, then `subOrder` (`RenderItem.subOrder`, `LayerComponent.subOrder`), then by kind, entity id and item index (§10.2), and flushes sprite batches whenever that key changes, so batching never pulls a sprite across a map layer. It skips `hiddenByMap` entities in its own pass and in every `RenderPass`, so a hidden layer's text and buttons are hidden too. One exception to the order: what `ComponentPainterPass` draws (text, buttons) comes after the whole list, so such an entity on a map layer is always above all the map's layers. `ySort` renderables stay in their place (layer, `zOrder`, sub-order) and sort by world y within it.
* **Tile collision.** Built only for layers marked *collides*. Every tile collision shape that lands as an upright box — whole cells, half-tile ledges, quarters of terrain, however the tile is turned — is merged with its neighbours of the same kind and class, along rows and then down columns as the kind's `TileMergeMode` allows; a merged box is exactly the boxes it covers, so the collision is unchanged but has no seams for a running character to catch on. Everything else is convex pieces of at most eight points. A kind's `decorate` hook gets the tile's own properties. Kinds come from `context.collisionKinds` (`MapCollisionKinds.solid`, `oneWay`, and packages'). Bodies are generated entities, rebuilt at most once a frame when anything they came from changes — the layer's cells, the map's settings or tilesets, the map's position, the layer's offset. A body sits where the layer's offset puts its tiles; parallax moves only the drawing. A map with no runtime (its source cleared, a file that would not load) has no bodies.
* **Runtime changes.** `LevelMapHandle.setTile` / `setTiles` write the layer's overlay, mark its collision dirty and fire `TileChangedEvent`. The loaded map — shared by every map made from the same file, or the editor's document — is never touched. `setCellsHidden` and `setBodyHidden` (the cells a body came from) add to the runtime's hidden cells and bump `hiddenRevision`, so the layer is drawn again; `hiddenCells` and `hiddenCellsOf(layerId)` are read-only views, and only the painter uses them. The map is unchanged and the bodies stay, for the game to switch off.

### Built-in tilesets

`BuiltInTilesets` holds the tilesets the engine draws itself, under paths starting `builtin:` that name no file. `basicShapes` (`builtin:basic_shapes.tileset.json`) is 24 tiles of 32 pixels, 8 to a row, for blocking out a level: blocks, halves and quarters, a one-way plank, 45° and 22.5° slopes, rounded corners, a circle, a triangle, a diamond. Its `TilesetData` is built in code, each tile with one collision shape, and its picture (`builtin:basic_shapes.png`) is drawn from those same shapes with a `PictureRecorder` and `toImageSync` — so every tile collides exactly as it looks. Tile ids are fixed and append-only.

`TileAssets.tileset` / `loadedTileset` answer a built-in path before looking in the cache, so `clear` and `evict` cannot drop it, and `putTileset` ignores one. `LevelMapRuntime` takes a built-in picture from `context.tiles.builtInImage(path)` — drawn once per context and disposed with it — instead of the sprite loader. `BuiltInTilesets.build(path)` makes a fresh copy of a built-in tileset and `BuiltInTilesets.draw(tileset)` a picture the caller owns. `TileAssets.isVirtual(path)` — a built-in path, or a Tiled map's embedded tileset (`<map path>#<index>`) — marks a path nothing may hand to a file system.

### Tiled object layers

`TiledInterop.importMap` makes every object layer an empty layer of the map: same id, name, offset, parallax, opacity and visibility, sorted as a tile layer is (a `foreground` property puts it in front). Every object comes back in `TiledImport.objects` as a `TiledObjectRecord` whose `mapLayerId` names that layer, so the caller can make each one an entity on it — a child of the map entity with `LayerComponent.mapLayer` set. The engine itself makes no entities from them. `exportMap` writes the map's layers as tile layers only, a layer with no tiles as an empty one; object groups are whatever the caller passes as `objects`.

### In an editor

The editor edits `LevelMapData` directly, so what it draws is what it saves. It switches `MapCollisionSystem` off while authoring (and calls `clearGenerated`); Play builds the bodies. `LevelMapSystem.advanceClock` lets it animate tiles while the game's time is stopped. `LevelMapRuntime.layerAlpha` fades layers for display without changing them. The editor points the context's loaders at the project's files (`overrideLoaders`, §5.4) and restores them, clearing the tile caches, when it detaches. The inspector hides `LayerComponent`'s `layerId`, `layer` and `zOrder` on an entity on a map layer, since they follow the layer, and shows `mapLayer` read-only.

---

## 18. Ready for 3-D

2.0 draws 3-D when a game asks for it (`Graphics3D`, below, on just_graphics_engine) and simulates it with `Physics3D` (§11), on foundations built for both, and keeps a 2-D game exactly as it was: same drawing, same numbers, same speed.

### One world, 2-D as a view of it

Every entity has a 3-D transform; a 2-D scene is a 3-D scene seen straight on by an orthographic camera. A scene's `mode` (`2d` / `3d`, `SceneMode`, in the file) only tells an editor which view, gizmos and fields to show — the runtime treats both alike. What only makes sense in one mode says so with `Dimensions` on its definition (`ComponentHints.dimensions`), a field (`FieldHint.dimensions`, `FieldHint.channels2D`), a prefab, a tool, an overlay or a command.

### Axes, rotation, clip space

| | |
|---|---|
| World axes (`WorldAxes`) | +X right, **+Y down**, +Z into the screen; right-handed. Up is −Y. A positive turn about Z is clockwise on screen. glTF / Blender content (Y-up, +Z towards the viewer) is turned 180° about X on import: `(x, y, z) → (x, −y, −z)`. |
| Euler angles | `q = qY · qX · qZ`: Z first, then X, then Y, about the world axes. A 2-D rotation is `(0, 0, angle)`. `Quaternion.eulerInto(out, hint:)` returns the equivalent triple nearest the hint. |
| Saved rotation | Euler radians `{x, y, z}` (`FieldTypes.euler`); a plain number reads as a turn about Z. |
| Clip space | x, y in −1..1 with **y down**; depth 0 (near) .. 1 (far). `JustMatrix4.setOrthographicYDown` / `setPerspectiveYDown` build into it; a GPU backend applies its own fix-up once. |
| Matrices | `vector_math`'s 64-bit `Matrix4` (Flutter's own class, re-exported by `just_dart`), column-major `Float64List` — straight into `Canvas.transform`. |

### Transforms and the hierarchy

`TransformComponent` is the **world** transform. Rotation is held as Euler angles (the 2-D `angle` is a plain field; `isPlanar` when the X and Y angles are 0) with a quaternion derived on demand. The hierarchy pass is in §7.5.

`HierarchyMath` (internal, not exported) composes TRS without shear: position is always exact; rotation is `qP · D(qL)`, where `D` mirrors by the signs of the parent's scale (a flipped parent mirrors its children exactly); scale is `sP ⊙ sL`. An uneven parent scale under a turned child drops the skew. A parent and child that both turn only about Z take a 2-D path with one sin/cos.

### Cameras

`OutputCamera` has a depth (`z`), a pitch, a yaw and a `CameraLens` beside its 2-D position, zoom and roll. Its orientation is `qY(yaw) · qX(pitch) · qZ(−roll)` — the roll negated because `rotation` turns the *view*. A camera with no pitch, yaw or perspective is `isPlanar` and runs its 2-D code. Otherwise its matrices describe it, `screenToWorldRay` gives picking rays, and `screenToWorld` / `visibleBounds` work on the world plane z = 0. `viewVolume` is a `PlanarViewVolume` (a rectangle at every depth) or a `FrustumViewVolume`. Virtual cameras carry a lens; the brain blends depth, tilt and lens like the rest.

### The frame, and where 3-D draws

```
post-process layers open → screen passes begin → camera pre-effects → clear
      → background hooks (parallax)
      → sceneRenderers (screen space, from FrameView)           ← a 3-D backend's image
      → overlay hooks below 100 (the ECS world: RenderSystem through its camera)
      → camera post-effects → screen passes paint → overlay hooks from 100 (plugins)
      → post-process layers close → screen-space effects
```

A `SceneRenderer` renders its scene into a texture and draws the image over the viewport with `canvas.drawImageRect`; post-processing and camera effects still apply, and sprites, UI and editor gizmos draw on top. `FrameView` (`rendering.view`) holds the frame's view, projection, view-projection and canvas matrices, filled once a frame and only when read, so a 2-D game pays nothing for it. `EngineConfig.createRendering` replaces the rendering engine outright.

### 3-D graphics

`Graphics3D` is opt-in, like `Physics3D`: one object that is both the `ContextExtension` (it registers the 3-D components, the skeletal animation target and the skeletal clip track) and the `EngineService` (it makes the renderer and draws), and a `SceneCacheService` (`releaseUnused`, §6.1). Given in `EngineConfig.services` (`EngineConfig(services: [Graphics3D(), Physics3D()])`), it is installed as the engine is made and started in the order the services are listed, so list it before any service that loads models as it starts; `engine.graphics3D` is an extension beside it, in `src/graphics/graphics_3d/graphics_3d.dart`. The renderer is just_graphics_engine's (`Renderer3D` on a `GpuDevice` over Flutter GPU); the engine reaches it only through that package's public libraries, whose web branch has no flutter_gpu, so the engine stays web-safe (`test/graphics/graphics_3d/graphics_3d_boundary_test.dart`). Without a `Graphics3D` the 3-D components are unknown, and a scene holding one fails to load with `UnknownComponentTypeException`, whose `hint` names the switch (registered by `BuiltInComponents.extension`, §9.3).

- **Components** (`src/graphics/graphics_3d/`): `ModelComponent`, `AnimationPlayerComponent` and `SocketComponent`, `Light3DComponent` and `EnvironmentComponent` (in `lighting/`) and `MaterialOverrides3DComponent` (in `materials/`) are plain data, and their definitions (`Graphics3DDefinitions`, `Lighting3DDefinitions`, `Material3DDefinitions`) mark them `Dimensions.threeD`. They import nothing from the GPU or the renderer, so scene files holding them load on every platform. `Graphics3D` is a `RefreshableExtension`, so an editor picks up new fields after a hot reload.
- **Start.** `Renderer3D.tryCreate` makes the device and the renderer. When there is no GPU, or the renderer can't start, `Graphics3D` logs the reason once, calls `onUnsupported` and runs on a `NullGpuDevice` instead. Scene loading, model loading and bounds keep working, and the frame shows a short note in place of the 3-D view. It registers a model loader with the engine's `AssetManager`, adds the scene renderer to the frame and an `Animation3DSystem` to the world.
- **Shapes** (`src/graphics/graphics_3d/shapes/`): `Primitive3DComponent` and its eleven subclasses are plain data too. Each builds its own mesh on the CPU (a `ShapeMesh`, in engine axes: no axis correction) through just_graphics_engine's `MeshBuilder`, which winds every triangle to face the way its vertices' normals point, so a generator only has to get its normals right. A test checks every shape is closed and encloses its expected volume (positive: facing out). `Primitive3DComponent.componentType` is `Primitive3DComponent`, so all shapes share one archetype column and an entity has one, as a 2-D entity has one renderable. A shape is also a `SolidShapeSource`: its convex parts (a box per step of a staircase, a hull per segment of an arch or a ring, the convex pieces of a concave outline, triangulated by ear clipping, then merged Hertel–Mehlhorn style), which 3-D physics matches. Physics asks for its `solidKey` every step; a shape hands back the same key object until a shape value changes, so the check allocates nothing.
- **`Graphics3DShapes`** is their GPU side: meshes by `shapeKey` (and, for a texture tiled per metre, the entity's scale rounded to a millimetre), materials by `materialKey`. Equal shapes share both, so they instance. A texture loads in the background; materials made before it arrives are made again with it (`revision`). Whatever no shape used for 300 frames is let go.
- **`Graphics3DModels`** loads each model path once: it reads through the engine's bundle (relative `.gltf` URIs resolve next to the file), prefers a cooked `<model>.jmodel` the bundle's manifest lists, parses in an isolate and uploads. `Graphics3DModelAsset` is the engine-side `ModelAsset`. Its bounds and triangles are in engine axes; a mesh used by several nodes gives one triangle set per placement.
- **Animation.** `AnimationPlayerComponent` saves the clip, speed, loop and crossfade; `Animation3DSystem` (priority `animation`) moves time on. The scene renderer samples each animated entity at `FrameView.interpolation` between its last two updates. `SocketComponent` pins a child entity to a joint: each update the system writes the joint's frame as the child's world transform (`parent · G · joint · G`, where G is `gltfToEngine`, so a model hung there is not turned twice), and the hierarchy works the local offset out from it.
- **`Graphics3DSceneRenderer`** (a `SceneRenderer`, order -100) runs inside the frame. It looks the world over (steps 1 and 2, the posing, the providers) once per engine frame, however many views it draws: `Graphics3D` gives it `frame: () => engine.rendering.drawingFrame`, and a view in the same frame, with the same interpolation and world, reuses that work. Only the editor aids, the camera, the view size and the timing are per view; what an aided view hid is shown again before the next view. A view drawn outside the engine's frame (no frame number) looks the world over itself, as every view used to.
  1. **Extract.** It rebuilds the `RenderScene`'s instances only when the world changes identity or its model or shape query's version moves, a model finishes loading, or a `ModelComponent.model` path changes. Otherwise it only compares each entity's transform with the last one and moves that entity's instances. Each instance keeps its entity-from-primitive matrix (`gltfToEngine` x node), so following is one multiply. A shape has one instance; each frame its keys are compared with the last, and a change of size or look swaps the instance's primitive or material.
  2. **Lights.** Lights and the environment are re-read every frame (once, whatever the number of views); they are few. The first directional light is the sun. A scene with no lights at all gets a default sun, so a dropped-in model is readable. Colours are authored in sRGB and converted to linear.
  3. **Draw.** It renders at viewport x device pixel ratio x `renderScale` x `dynamicResolution.scale` into a `GpuSurface` (one per `FrameView` it draws, so an editor's second view in the same frame doesn't overwrite the game's), then draws `surface.image` over the viewport with `drawImageRect` and disposes it. The frame is submitted without waiting; `lastFrame` completes when the GPU is done.
  - **Interpolation.** A transform whose `captureCount` changed over the last fixed step (physics bodies and characters) is drawn between its previous and current pose at `FrameView.interpolation`; anything else is drawn where it is.

### Not yet

The 3-D scene renderer re-adds every model instance when it rebuilds, which is fine at scene load but not for spawning many entities each frame; and local-space timeline tracks.

---

## 19. Platform Support

### 19.1 Web and WASM

`pubspec.yaml` declares Android, iOS, Linux, macOS, Windows and Web. The engine's `lib/` is WASM-ready: it imports no `dart:html` and no `package:web`; the web storage branch (`engine_storage_web.dart`) uses `dart:js_interop`, which works under both dart2js and dart2wasm; and exactly one file imports `dart:io`:

```dart
// lib/src/storage/engine_storage.dart
import 'engine_storage_web.dart'
    if (dart.library.io) 'engine_storage_io.dart'
    as platform;
```

The default branch is the web one; the VM gets `engine_storage_io.dart`, the only file with `dart:io` and `package:path_provider`. Keep it that way: a platform-specific file goes behind a conditional import whose default works in a browser. `grep -rn "dart:io\|dart:html\|package:web" lib` should find only `engine_storage_io.dart`.

### 19.2 What differs on the web

| Area | On the web |
|---|---|
| Physics | the pure-Dart engine, not Box2D (§11.1) |
| Audio | starts at the first key or pointer press (§13) |
| Shaders | `ImageFilter.shader` is not supported, so post-process passes and `ShaderComponent` effects are skipped, with one log line per kind (§10.5). The same holds on native platforms still drawing with Skia |
| Storage | `localStorage` under `just_game_engine/` (§14.3) |
| Gamepads | work in browsers, WASM builds included: `just_gamepads`, which `just_inputs` uses, picks its browser backend with a `dart.library.js_interop` conditional import |
| Timing | `GameLoop.tick(frameTime)` uses the ticker's vsync stamps, because a stopwatch read in a callback is coarse in browsers; the 1 % step slack (§7.1) absorbs rounding |
| Integers | JavaScript numbers: the query hash keys are 31-bit, the draw sort compares layer and `zOrder` as two numbers instead of shifting, tile-chunk keys fit 32 bits, and the cache's key hash multiplies in pieces small enough to stay exact |

### 19.3 Native

Box2D runs through FFI (`just_physics_engine`, on `just_box_2d`); if its library is missing the engine falls back to the pure-Dart simulation with a log line. Shaders filter layers under Impeller. The storage file is in the app's support directory.

### 19.4 No process-wide state

Two engines — or two tests — in one process must never see each other's registrations. `test/no_process_state_test.dart` enforces it: it finds every non-`const` `static` field and every top-level variable under `lib/src` and fails on any that is not on its allowlist. Each allowed entry says why it is safe: immutable tables, frozen `builtIn` registries, component definitions, single-threaded scratch vectors, `Paint`s configured once, `Expando` caches, the Zobrist key cache, and `ShaderFilterSupport`'s per-process check of what the renderer can do. New per-engine state goes in `EngineContext` (a registry, or a package's `slot`); per-world state goes in `World`.

---

## 20. Known Limitations and Debt

### 20.1 Import loops

No import loop crosses features, and the features follow one layer order (§2.3), which `test/library_layout_test.dart` checks: `EngineContext` knows no feature, the 2-D renderer sits above what it draws, velocity is in the ECS core and the service contract below the services. The loops left are each inside one feature.

### 20.2 Editor presentation ships in games

`ComponentDefinition.hints` (`ComponentHints`, `FieldHint`, `ScrubHint`, `FieldRowHint`) describes how the editor shows a component: labels, descriptions, groups, icons (`IconData`), accent colours, scrub steps, file extensions. It lives in the runtime definitions (each feature's `*_definitions.dart` and `ecs/serialization/ecs_definitions.dart`), so every game compiles it in. Moving it out needs a presentation registry the editor fills beside the codecs.

### 20.3 Level-map member sync runs every frame

`LevelMapSystem` re-applies every map child's layer settings (`layerId`, `layer`, `zOrder`, `subOrder`, `hiddenByMap`) on every update. It allocates nothing, but it cannot skip unchanged frames: the editor changes children lists, `mapLayer` and layer settings in place, and there are no change counters to compare. Adding revision counters to those would let the pass skip.

### 20.4 Smaller items

- Logging is `debugPrint`, about a hundred calls, with no hook for a game's own logger.
- The engine's loop runs at 60 updates a second; `EngineConfig` has no setting for it.
- `ParticleSystem` is not a default system; a game with particle emitter components adds it.
- Waiting on `just_physics_engine`: joint anchors (`anchor` / `connectedAnchor` of distance and fixed joints) are not passed to it; with `collideConnected` off the pure-Dart backend still pushes jointed bodies apart (the engine only keeps their contact events back); native Box2D queries skip bodies whose collision mask is 0. Joint springs are hertz and damping ratio everywhere: `Physics2DJoints.dartSpring` converts them for the Dart backend. The editor's inspector hides the anchors the backends ignore (distance, fixed and slider joints), keeping their saved values. In 3-D, the layers a world keeps apart are fixed when the world is made (`Physics3DWorldSettings.layerMasks`): a collision grid edited while a 3-D scene plays reaches the next world made; it waits on a `Physics3DWorld.setLayerMasks`.
- Waiting on `just_audio_engine`: a stream is not routed through `AudioStreamComponent.channel`'s volume, and a playing sound's pitch, pan, speed and loop cannot change.
