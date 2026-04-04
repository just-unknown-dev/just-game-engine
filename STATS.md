# Engine Diagnostics & Stats Reference

This document describes every stats/diagnostics API exposed by `just_game_engine`. All stats are available at runtime with no external tooling required. They are safe to call every frame (read-only, no allocation beyond the returned map).

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
9. [Debug HUD](#9-debug-hud)
10. [Putting it all together — one-liner snapshot](#10-putting-it-all-together--one-liner-snapshot)

---

## 1. Engine — `performanceStats`

**Getter:** `Engine.performanceStats` → `Map<String, dynamic>`

The top-level snapshot. Covers the most recent completed update cycle.

| Key | Type | Description |
|-----|------|-------------|
| `frame` | `int` | Monotonically increasing frame counter (resets on engine restart). |
| `deltaTime` | `double` | Seconds between the two most recent fixed-timestep ticks. Normally equals `1 / targetUPS` (e.g. `0.01667` at 60 UPS). |
| `lastUpdateMs` | `double` | Wall-clock milliseconds the last full update cycle took (all subsystems combined). |
| `budgetRemainingMs` | `double` | `16.67 − lastUpdateMs`. Positive = headroom; negative = over budget. |
| `isOverBudget` | `bool` | `true` when the update cycle exceeded the 60 Hz frame budget (16.67 ms). |
| `systemTimesMs` | `Map<String, double>` | Per-task elapsed times (mirrors `schedulerStats.taskTimesMs`). Keys: `input`, `camera`, `parallax`, `physics`, `animation`, `audio`, `ecs`. |
| `scheduler` | `Map<String, dynamic>` | Nested `SystemManager.schedulerStats` (see §2). |

**Example:**
```dart
final s = engine.performanceStats;
if (s['isOverBudget'] as bool) {
  debugPrint('Frame over budget: ${s['lastUpdateMs']} ms');
}
```

---

## 2. SystemManager — `schedulerStats`

**Getter:** `engine.systemManager.schedulerStats` → `Map<String, dynamic>`

Reports the state of the authoritative frame scheduler. Also embedded under the `scheduler` key of `Engine.performanceStats`.

| Key | Type | Description |
|-----|------|-------------|
| `systemCount` | `int` | Number of subsystems currently registered (rendering, physics, input, …). |
| `updateTaskCount` | `int` | Number of ordered update tasks registered with the scheduler. |
| `lastFrameMs` | `double` | Total wall-clock time (ms) for the last `runUpdateCycle` call. |
| `taskTimesMs` | `Map<String, double>` | Elapsed ms per named task in execution order. |

**Additional getters:**

| Getter | Type | Description |
|--------|------|-------------|
| `lastTaskTimesMs` | `Map<String, double>` | Alias for the unmodifiable task-timing map. |
| `lastFrameMs` | `double` | Total elapsed ms for the last update cycle. |

**Registering a custom task:**
```dart
engine.systemManager.registerUpdateTask('my_system', (dt) {
  mySystem.update(dt);
});
// Stats will then include 'my_system' in taskTimesMs.
```

---

## 3. World (ECS) — `stats`

**Getter:** `engine.world.stats` → `Map<String, dynamic>`

Reports the current state of the Entity Component System world.

| Key | Type | Description |
|-----|------|-------------|
| `totalEntities` | `int` | All entities in the world (alive + pending removal). |
| `activeEntities` | `int` | Entities not marked for destruction. |
| `systems` | `int` | Total ECS systems registered. |
| `activeSystems` | `int` | ECS systems with `isActive == true`. |
| `archetypes` | `int` | Number of distinct component-type combinations (archetype buckets). High numbers can indicate component churn. |
| `lastUpdateMs` | `double` | Wall-clock ms for the last `world.update()` call (all ECS systems). |
| `lastCommandFlushes` | `int` | Number of deferred `CommandBuffer` commands executed in the last flush. |
| `systemTimesMs` | `Map<String, double>` | Per-ECS-system elapsed ms. Keys are the system's `runtimeType` name. |

**Example:**
```dart
final w = engine.world.stats;
print('Entities: ${w['activeEntities']} / ${w['totalEntities']}');
print('Archetypes: ${w['archetypes']}');
```

---

## 4. PhysicsEngine — `stats`

**Getter:** `engine.physics.stats` → `Map<String, dynamic>`

Reports one simulation step's worth of broadphase and narrowphase metrics.

| Key | Type | Description |
|-----|------|-------------|
| `bodyCount` | `int` | Total rigid bodies registered. |
| `awakeBodies` | `int` | Bodies that were simulated last step (non-sleeping). |
| `potentialPairs` | `int` | Candidate collision pairs produced by the broadphase grid. |
| `resolvedCollisions` | `int` | Pairs that passed narrowphase and had impulse resolution applied. |
| `broadphaseDirtyBodies` | `int` | Bodies whose grid cells changed last step (moved or spawned). Zero when the scene is static — confirms the incremental broadphase is working. |
| `trackedCells` | `int` | Total occupied grid cells currently tracked across all bodies. |
| `lastStepMs` | `double` | Wall-clock ms for the last physics step. |

**Tip:** `broadphaseDirtyBodies == 0` while bodies exist means all bodies are stationary and no grid updates were needed — optimal for static scenes.

---

## 5. RenderingEngine — `stats`

**Getter:** `engine.rendering.stats` → `Map<String, dynamic>`

Reports one rendered frame's worth of draw-call and spatial-index metrics.

| Key | Type | Description |
|-----|------|-------------|
| `renderables` | `int` | Total registered renderables. |
| `layers` | `int` | Total registered render layers. |
| `lastRenderMs` | `double` | Wall-clock ms for the last render pass. |
| `drawCalls` | `int` | Draw calls issued last frame. Lower is better (batching reduces this). |
| `renderedObjects` | `int` | Objects that passed frustum culling and were drawn. |
| `culledObjects` | `int` | Objects outside the camera frustum that were skipped. High culling is good for dense scenes. |
| `batchedSprites` | `int` | Sprites combined into a single batch draw call. |
| `usedSpatialIndex` | `bool` | `true` when the quadtree spatial index was active last frame (triggered when `renderables > 200`). |
| `spatialRebuilds` | `int` | Cumulative number of times the quadtree was fully rebuilt. Should grow slowly for mostly-static scenes. |
| `spatialReusedLastFrame` | `bool` | `true` when the quadtree was reused unchanged from the previous frame (bounds and camera position were stable). |

**Tip:** `spatialReusedLastFrame == true` confirms the incremental quadtree optimization is active. If it flips `false` every frame, check whether renderables are being moved or recreated unnecessarily.

---

## 6. GameLoop — live getters

**Access:** `engine.gameLoop`

The game loop exposes three lightweight read-only properties (not a map):

| Getter | Type | Description |
|--------|------|-------------|
| `currentFPS` | `int` | Frames per second, measured as a 1-second rolling average. |
| `interpolation` | `double` | Fractional accumulator position between the last and next fixed-timestep tick (`0.0–1.0`). Use for smooth rendering of physics objects. |
| `isRunning` | `bool` | Whether the loop is actively ticking. |
| `isPaused` | `bool` | Whether the loop is paused (ticks arrive but game logic is skipped). |

**Example:**
```dart
final fps = engine.gameLoop.currentFPS;
final alpha = engine.gameLoop.interpolation;
// Render: position = previousPos + (currentPos - previousPos) * alpha
```

---

## 7. TimeManager — live getters

**Access:** `engine.time`

| Getter | Type | Description |
|--------|------|-------------|
| `deltaTime` | `double` | Seconds since last tick, scaled by `timeScale`. |
| `unscaledDeltaTime` | `double` | Raw seconds since last tick, unaffected by `timeScale`. |
| `totalTime` | `double` | Total scaled time accumulated since engine start (seconds). |
| `elapsedTime` | `double` | Real wall-clock seconds since the `TimeManager` was constructed. |
| `timeScale` | `double` | Current time multiplier (`1.0` = normal, `0.0` = frozen, `0.5` = half speed). Read/write. |
| `frameCount` | `int` | Total `update()` calls since construction (one per game-logic tick). |
| `fps` | `double` | `1.0 / deltaTime` — instantaneous frame rate derived from scaled delta time. |
| `maxDeltaTime` | `double` | Maximum allowed raw delta time (default `0.1 s`). Clamps spikes. Read/write. |

---

## 8. CacheManager — live getters

**Access:** `engine.cache`

| Getter | Type | Description |
|--------|------|-------------|
| `isInitialized` | `bool` | `true` after `initialize()` completes (regardless of fallback mode). |
| `isUsingMemoryFallback` | `bool` | `true` when persistent storage is unavailable and data is held in in-memory maps. Expected `true` in unit tests and on platforms without plugin support. |

> **Note:** When `isUsingMemoryFallback` is `true` the cache behaves identically from the caller's perspective — all `setString`/`getString`/`setBinary`/`getBinary` operations succeed. Data is not persisted across process restarts in this mode.

---

## 9. Debug HUD

When `GameWidget` is constructed with `showDebugHud: true`, an on-screen overlay renders a live summary pulled from the stats above. The HUD is positioned in the top-left corner and updates every frame.

**Displayed values:**
- FPS from `GameLoop.currentFPS`
- Update ms from `Engine.performanceStats['lastUpdateMs']`
- Render ms from `RenderingEngine.stats['lastRenderMs']`
- Physics ms from `PhysicsEngine.stats['lastStepMs']`

```dart
GameWidget(
  engine: engine,
  showDebugHud: true, // toggle in debug builds
)
```

---

## 10. Putting it all together — one-liner snapshot

A single `Map` that aggregates all subsystem stats into a flat diagnostic report:

```dart
Map<String, dynamic> fullSnapshot(Engine engine) => {
  ...engine.performanceStats,
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
  },
};
```

Log it, display it in a custom HUD, or send it to a remote telemetry endpoint—all from a single call.
