# Engine Diagnostics & Stats Reference

This document describes every stats/diagnostics API `just_game_engine` 2.0.0-dev.1 exposes, key by key, as the code produces it. All of them work at runtime with no external tooling, and all are cheap enough to read every frame.

`Engine.performanceStats` is safe in any engine state. The subsystems (`engine.world`, `engine.physics`, `engine.rendering`, `engine.gameLoop`, `engine.time`, `engine.cache`, `engine.systemManager`) exist only between `initialize()` and `dispose()`; outside that window their getters throw `EngineNotReadyError`. Check `engine.isInitialized` first when that can happen.

---

## Table of Contents

1. [Engine — `performanceStats`](#1-engine--performancestats)
2. [SystemManager — `schedulerStats`](#2-systemmanager--schedulerstats)
3. [World (ECS) — `stats`](#3-world-ecs--stats)
4. [PhysicsEngine — `stats`](#4-physicsengine--stats)
5. [RenderingEngine — `stats`](#5-renderingengine--stats)
6. [GameLoop — live getters](#6-gameloop--live-getters)
7. [TimeManager — live getters](#7-timemanager--live-getters)
8. [CacheManager — live getters](#8-cachemanager--live-getters)
9. [AssetManager — `getCacheStats()` and getters](#9-assetmanager--getcachestats-and-getters)
10. [Debug HUD](#10-debug-hud)
11. [Putting it all together — one snapshot](#11-putting-it-all-together--one-snapshot)

---

## 1. Engine — `performanceStats`

**Getter:** `Engine.performanceStats` → `Map<String, dynamic>`

The top-level snapshot. Covers the most recent fixed update step.

| Key | Type | Description |
|-----|------|-------------|
| `frame` | `int` | Fixed update steps run while the engine was `running`, since this engine was made. Stopping and starting does not reset it; a new `Engine()` starts at 0. |
| `deltaTime` | `double` | The `dt` of the last step: the fixed step times the time scale — `1/60` s (`0.01667`) at normal speed, `0` at time scale 0. |
| `lastUpdateMs` | `double` | Wall-clock milliseconds of the last update cycle: every update task (§2) together. |
| `budgetRemainingMs` | `double` | `16.67 − lastUpdateMs`. Positive = headroom; negative = over budget. |
| `isOverBudget` | `bool` | `lastUpdateMs > 16.67`. This is one step measured against a 60 Hz frame; a frame that runs two steps to catch up spends twice that. |
| `systemTimesMs` | `Map<String, double>` | Milliseconds per update task, as in `schedulerStats['taskTimesMs']`. The engine's tasks, in order: `input`, `camera`, `parallax`, `particles`, `ecs` — plus any registered with `registerUpdateTask`. (`audio` runs once per rendered frame, a frame task after `ecs`, not here.) There is no `physics` task: `PhysicsSystem` steps the physics engine inside `ecs` (see `World.stats` for per-system times). |
| `scheduler` | `Map<String, dynamic>` | `SystemManager.schedulerStats` (see §2); an empty map before the first update step and when the engine has no system manager (before `initialize()`, after `dispose()`). |

**Example:**
```dart
final s = engine.performanceStats;
if (s['isOverBudget'] as bool) {
  debugPrint('Update over budget: ${s['lastUpdateMs']} ms');
}
```

---

## 2. SystemManager — `schedulerStats`

**Getter:** `engine.systemManager.schedulerStats` → `Map<String, dynamic>`

The frame scheduler's state, rebuilt once per update cycle (reading it again in the same frame allocates nothing). Also embedded under the `scheduler` key of `Engine.performanceStats`. Empty until the first update cycle has run.

| Key | Type | Description |
|-----|------|-------------|
| `systemCount` | `int` | Subsystems registered with the manager. The engine registers nine: `rendering`, `physics`, `input`, `audio`, `cache`, `assets`, `camera`, `parallax`, `ecs`. |
| `updateTaskCount` | `int` | Update tasks registered: the engine's six, plus yours. |
| `lastFrameMs` | `double` | Wall-clock milliseconds of the last `runUpdateCycle` call. |
| `taskTimesMs` | `Map<String, double>` | Milliseconds per task, in execution order (an unmodifiable view). |

**Additional getters:**

| Getter | Type | Description |
|--------|------|-------------|
| `lastTaskTimesMs` | `UnmodifiableMapView<String, double>` | The same map as `taskTimesMs`, always current. |
| `lastFrameMs` | `double` | Total milliseconds of the last update cycle. |
| `systemCount` | `int` | Registered subsystems. |
| `getSystemNames()` | `List<String>` | Their names. |

**Registering a custom task:**
```dart
engine.systemManager.registerUpdateTask('my_task', (dt) {
  myService.update(dt);
});
// Runs after the engine's own tasks, and appears in taskTimesMs as 'my_task'.
// Task names are unique: registering one twice throws a StateError.
// unregisterUpdateTask('my_task') removes it.
```

---

## 3. World (ECS) — `stats`

**Getter:** `engine.world.stats` → `Map<String, dynamic>`

The state of the ECS world after its last update.

| Key | Type | Description |
|-----|------|-------------|
| `totalEntities` | `int` | Entities in the world, switched on or off. |
| `activeEntities` | `int` | Entities active in the hierarchy (`Entity.isActiveInHierarchy`): switched on, and every parent too. |
| `systems` | `int` | ECS systems in the world. |
| `activeSystems` | `int` | Systems with `System.isActive == true`. |
| `archetypes` | `int` | Archetypes (distinct component-type combinations) made since the world was last cleared (`destroyAllEntities`). A number that keeps growing points to component churn. |
| `lastUpdateMs` | `double` | Wall-clock milliseconds of the last `world.update()`: every system's `update`, the transform-hierarchy pass and the command-buffer flushes. Drawing is not in it — `RenderSystem` draws in `render()`, which is part of `RenderingEngine.stats['lastRenderMs']`. |
| `lastCommandFlushes` | `int` | How many times the command buffer was flushed during the last update — once after each system that left commands queued. Not the number of commands. |
| `systemTimesMs` | `Map<String, double>` | Milliseconds of each active system's `update`, keyed by the system's runtime type name (two systems of one type share a key), plus `TransformHierarchy` for the world's hierarchy pass. |

Other live getters: `world.entityCount`, `world.queryVersion(types)` (moves whenever what that query matches may have changed), `world.tagsInUse`.

**Example:**
```dart
final w = engine.world.stats;
debugPrint('Entities: ${w['activeEntities']} / ${w['totalEntities']}');
debugPrint('Archetypes: ${w['archetypes']}');
```

---

## 4. PhysicsEngine — `stats`

**Getter:** `engine.physics.stats` → `Map<String, dynamic>`

The keys depend on the backend `just_physics_engine` picked: Box2D through FFI on native platforms, the pure-Dart engine on the web (and on native if the Box2D library would not load). `stats['backend']` tells them apart on native; the web has no `backend` key.

**Always present** (the pure-Dart engine's keys):

| Key | Type | Pure Dart (web, fallback) | Box2D (native) |
|-----|------|---------------------------|----------------|
| `bodyCount` | `int` | Bodies in the engine. | Box2D bodies. |
| `awakeBodies` | `int` | The most bodies awake in any sub-step of the last update. | Equals `bodyCount`: every native body counts as awake. |
| `potentialPairs` | `int` | Candidate pairs from the broadphase grid in the last sub-step. | Not used by Box2D: the idle pure-Dart counter (0). |
| `resolvedCollisions` | `int` | Contacts resolved over all sub-steps of the last update. | Not used (0). |
| `broadphaseDirtyBodies` | `int` | Bodies whose grid cells changed in the last sub-step. 0 while everything is still. | Not used (0). |
| `trackedCells` | `int` | Occupied broadphase grid cells. | Not used (0). |
| `lastStepMs` | `double` | Wall-clock milliseconds of the last `update` (all its sub-steps). | Wall-clock milliseconds of the last `update`, including syncing transforms back from Box2D. |

**Box2D only** (on the pure-Dart fallback on native these are present with the values shown):

| Key | Type | Description | Fallback value |
|-----|------|-------------|----------------|
| `lastStepCount` | `int` | Fixed Box2D steps (1/60 s) taken in the last update: 0, 1 or more. | `0` |
| `contactCount` | `int` | Contacts that began during the last update. | `0` |
| `alpha` | `double` | How far the physics world's accumulator is into its next step, 0..1. | `0.0` |
| `backend` | `String` | `'box2d_v3'` | `'dart_fallback'` |

**Tip:** on the web, `broadphaseDirtyBodies == 0` while bodies exist means nothing moved, and the incremental broadphase did no work.

---

## 5. RenderingEngine — `stats`

**Getter:** `engine.rendering.stats` → `Map<String, dynamic>`

One frame of `RenderingEngine.render`. The four counts — `drawCalls`, `renderedObjects`, `culledObjects`, `batchedSprites` — cover the whole frame: the rendering engine's own renderables (the **deprecated** `addRenderable` / managed-emitter path, to be removed in 3.0) plus whatever reported into `RenderingEngine.addFrameStats` while the frame was drawn. The ECS `RenderSystem` reports there when it has a `statsSink`; the default systems make it with `statsSink: engine.rendering`. A `RenderSystem` you add yourself counts in these figures only if you pass `statsSink: engine.rendering` too. Its own counts are also in `RenderSystem.stats` (below). `renderables`, `layers` and the spatial-index keys describe only the legacy renderables.

| Key | Type | Description |
|-----|------|-------------|
| `renderables` | `int` | Renderables added with `addRenderable` (and managed emitters). |
| `layers` | `int` | Layers those renderables are filed under. |
| `lastRenderMs` | `double` | Wall-clock milliseconds of the whole last `render`: background hooks (parallax), scene renderers, the legacy renderables, the overlay hooks (the ECS world's `render`, plugins) and camera effects. |
| `drawCalls` | `int` | Canvas draws: 1 for the background clear, plus one for each thing drawn by itself and one for each batch flushed (of sprites, or of shapes with `RenderSystem(batchShapes: true)`). |
| `renderedObjects` | `int` | Things drawn — legacy renderables, and the ECS world's renderables, render items (level-map layers) and particle emitters — a batched sprite or shape counting as one. |
| `culledObjects` | `int` | Renderables skipped: invisible, or outside the camera's view (in the ECS world, only with `RenderSystem(cullOffscreen: true)`). None of them were drawn. |
| `batchedSprites` | `int` | Sprites drawn through a sprite batch. |
| `usedSpatialIndex` | `bool` | The quadtree answered the visibility test last frame: `useSpatialIndex` on, more than 200 legacy renderables, and nothing moved since it was built. |
| `spatialRebuilds` | `int` | Times the quadtree has been built, in total. Should grow slowly while things are still. |
| `spatialReusedLastFrame` | `bool` | The quadtree was reused unchanged last frame. |
| `postProcessPasses` | `int` | Enabled post-process passes registered (`addPostProcessPass`, or `PostProcessSystem` from `ShaderComponent`s). Where shaders cannot filter layers (the web, Skia) they are counted but skipped; see `ShaderFilterSupport`. |

**Tip:** `spatialReusedLastFrame` flips to `false` every frame while any legacy renderable moves — the tree is rebuilt only once everything is still.

### `RenderSystem.stats`

**Getter:** `world.getSystem<RenderSystem>()?.stats` → `Map<String, int>`

What the ECS `RenderSystem` drew in its last `render`, under the same keys: `drawCalls`, `renderedObjects`, `culledObjects` and `batchedSprites`. The extra render passes' own drawing (the `ComponentPainterPass` that draws text and other painted components) is not counted. These are the counts it reports to its `statsSink`.

---

## 6. GameLoop — live getters

**Access:** `engine.gameLoop`

Read-only properties (not a map):

| Getter | Type | Description |
|--------|------|-------------|
| `currentFPS` | `int` | Frames per second: ticks counted over at least one second of frame time, then updated. 0 until the first second has passed. |
| `interpolation` | `double` | How far the accumulator is into the next fixed step, clamped to `0.0–1.0`. `GameWidget` passes it to the world's `RenderSystem` each frame. |
| `fixedDeltaTime` | `double` | The length of one fixed step in seconds, before time scale: `1 / targetUPS`. |
| `targetUPS` | `int` | Fixed steps per second. The engine's loop uses the default, 60. |
| `isRunning` | `bool` | Whether the loop has been started (and not stopped). |
| `isPaused` | `bool` | Whether the loop is paused: ticks still arrive and time is still measured, but no steps run. |

**Example:**
```dart
final fps = engine.gameLoop.currentFPS;
final alpha = engine.gameLoop.interpolation;
// Draw between steps: position = previous + (current - previous) * alpha
```

---

## 7. TimeManager — live getters

**Access:** `engine.time`

Updated once per frame (every `GameLoop.tick` while the loop runs, paused or not) with the frame's time — not once per fixed step. Systems get the fixed step as their `dt`; these are the frame's figures.

| Getter | Type | Description |
|--------|------|-------------|
| `deltaTime` | `double` | The last frame's time, clamped to `maxDeltaTime`, times `timeScale`. |
| `unscaledDeltaTime` | `double` | The last frame's time, clamped to `maxDeltaTime`, ignoring `timeScale`. |
| `totalTime` | `double` | Sum of `deltaTime` since the `TimeManager` was made (seconds). |
| `elapsedTime` | `double` | Wall-clock seconds since the `TimeManager` was made (it is made in `initialize()`). |
| `timeScale` | `double` | Time multiplier (`1.0` normal, `0.0` frozen, `0.5` half speed). Read/write; negative values throw. `pause()`, `resume()`, `slowMotion()` and `fastForward()` set it. |
| `frameCount` | `int` | Frames counted — one per tick, including paused frames. |
| `fps` | `double` | `1.0 / deltaTime`: the last frame's rate, scaled by `timeScale` (0 while time is frozen). |
| `maxDeltaTime` | `double` | The largest frame time counted (default `0.1` s). Read/write; must be positive. |
| `getSmoothDeltaTime([smoothing = 0.1])` | `double` | An exponential moving average of `deltaTime`. |

---

## 8. CacheManager — live getters

**Access:** `engine.cache`

| Getter | Type | Description |
|--------|------|-------------|
| `isInitialized` | `bool` | `true` once `initialize()` has finished (whatever it could open). |
| `isUsingMemoryFallback` | `bool` | `true` when the key-value store could not be opened (or the manager was made with `forceMemoryFallback`): everything is held in memory. Expected in unit tests and headless runs. |
| `isBinaryInMemory` | `bool` | `true` when binary data is in memory only — the database could not be opened or set up — while strings may still reach the key-value store. |
| `CacheManager.keyPrefix` | `String` (static) | `'just_game_engine.cache/'`: every key the cache writes starts with it. |
| `maxBinaryEntries` | `int?` | The binary-cache limit; `null` (none) for the engine's own cache. |
| `getBinaryCacheSize()` | `Future<int>` | Entries in the binary cache. |
| `captureProfile()` | `MemoryProfileSnapshot` | The in-memory stand-ins the cache uses when a store is unavailable or a write fails, as `cacheStats['cache.strings']` and `cacheStats['cache.binary']` (`entryCount`, `currentCost`, `maxCost`). |

> **Note:** In memory-fallback mode the cache behaves the same from the caller's side — `setString`/`getString`/`setBinary`/`getBinary` all succeed — but nothing survives the process. Where it does persist, the key-value store is the engine's own file (`<application support>/just_game_engine/just_storage.json`), or browser storage under `just_game_engine/` on the web.

---

## 9. AssetManager — `getCacheStats()` and getters

**Access:** `engine.assets` (the engine context's `AssetManager`; available before `initialize()`)

`getCacheStats()` → `Map<String, dynamic>`:

| Key | Type | Description |
|-----|------|-------------|
| `totalAssets` | `int` | Assets loaded and kept. |
| `assetCount` | `int` | The same number. |
| `memoryUsage` | `int` | Estimated bytes held, as each asset reports it (an image counts width × height × 4). Updated when assets load or unload. |
| `memoryUsageMB` | `String` | `memoryUsage` in megabytes, two decimals. |
| `assetsByType` | `Map<AssetType, int>` | Loaded assets per `AssetType`. |

Getters: `assetCount`, `totalMemoryUsage` (bytes), `isLoaded(path)`, `refCount(path)` (for assets taken with `acquire`).

---

## 10. Debug HUD

`GameWidget` has three switches for on-screen diagnostics:

```dart
GameWidget(
  engine: engine,
  showFPS: true,       // the default
  showDebug: kDebugMode,
  showTerminal: kDebugMode,
)
```

- **`showFPS`** (default `true`) — an `FPS: n` badge at the top right, showing `engine.gameLoop.currentFPS`. It is updated about once a second, in its own repaint boundary, so it costs the rest of the widget nothing.
- **`showDebug`** (default `false`) — two things:
  - sets `engine.rendering.debugMode`: every legacy renderable gets its bounds (green) and origin (red) drawn, and a text block at the top left shows `Renderables`, `Camera`, `Zoom`, `Render: … ms`, `Draws | Culled` and `Spatial Index` — the figures of `RenderingEngine.stats` (§5). `Renderables` and `Spatial Index` are about the deprecated legacy path only; `Draws` and `Culled` include the ECS world's drawing;
  - adds a `ColliderDebuggerSystem` to the world, which outlines every physics body (entities with a `PhysicsBodyRefComponent`) and every `RaycastColliderComponent` through the main camera, over everything else. It is removed when `showDebug` turns off or the widget goes.
- **`showTerminal`** — the developer terminal (`engine.terminal`), toggled with the backquote key.

`GameWidget` may be built before `initialize()` has completed: it starts drawing the engine and applies `showDebug` as soon as the engine is ready (it listens to `Engine.stateListenable`).

Apart from `GameWidget`, debug builds (`kDebugMode`) draw collider outlines from `PhysicsSystem` (for bodies whose `Collider2D.showDebugOutline` is true, the default) and checkpoint radii from `CheckpointSystem`, each through the camera it was given.

The HUD shows no update or physics timings. For those, draw your own from the maps above — for example `performanceStats['lastUpdateMs']`, `world.stats['systemTimesMs']` and `physics.stats['lastStepMs']`.

---

## 11. Putting it all together — one snapshot

A single `Map` with every subsystem's figures:

```dart
Map<String, dynamic> fullSnapshot(Engine engine) => {
  ...engine.performanceStats,
  if (engine.isInitialized) ...{
    'fps': engine.gameLoop.currentFPS,
    'interpolation': engine.gameLoop.interpolation,
    'time': {
      'total': engine.time.totalTime,
      'scale': engine.time.timeScale,
      'frames': engine.time.frameCount,
    },
    'ecs': engine.world.stats,
    'physics': engine.physics.stats,
    'rendering': engine.rendering.stats,
    'cache': {
      'initialized': engine.cache.isInitialized,
      'memoryFallback': engine.cache.isUsingMemoryFallback,
      'binaryInMemory': engine.cache.isBinaryInMemory,
    },
  },
  'assets': engine.assets.getCacheStats(),
};
```

Log it, show it in a HUD of your own, or send it to a telemetry endpoint.
