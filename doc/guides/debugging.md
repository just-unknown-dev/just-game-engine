# Debugging & stats

_Flutter & shipping_ · Read the engine's performance and per-subsystem stats, switch on the debug overlay and the developer terminal, and fix the most common problems.

Every stat the engine keeps can be read at run time, without external tools, and all of them are cheap enough to read every frame. `GameWidget` adds an FPS badge, a debug overlay and a developer terminal on top.

## The debug overlay

```dart
GameWidget(
  engine: engine,
  showFPS: true, // the default
  showDebug: kDebugMode,
  showTerminal: kDebugMode,
)
```

- **`showFPS`** shows `FPS: n` in the top right corner, from `engine.gameLoop.currentFPS`. It updates about once a second and costs the rest of the widget nothing.
- **`showDebug`** adds a `Collider2DDebuggerSystem` to the world, which outlines every 2-D collider as simulated (coloured by body kind) and every 2-D character through the main camera. It also sets `engine.rendering.debugMode`, which prints the rendering figures (render time, draws, culled objects) in the top left corner. Both go away when `showDebug` turns off.
- **`showTerminal`** enables the developer terminal (below).

`Physics2DSystem` draws nothing: collider outlines come only from a `Collider2DDebuggerSystem` in the world. Without `showDebug`, add one yourself, `engine.world.addSystem(Collider2DDebuggerSystem(camera: engine.camera.mainCamera))`, and narrow it with `outlineFilter`; a collider's own `showDebugOutline` has the last word. Remove it with `engine.world.removeSystem(...)` to hide them again.

## The developer terminal

With `showTerminal: true`, the backquote key opens a command console over the game. While it is open, the keyboard goes to the terminal, not the game. It has `help` and `clear` built in; register your own commands on `engine.terminal`:

```dart
void addDebugCommands(Engine engine) {
  engine.terminal.registerCommand(
    name: 'stats',
    description: 'Show entity counts and the last update time.',
    handler: (args) {
      final world = engine.world.stats;
      final perf = engine.performanceStats;
      return 'entities ${world['activeEntities']}/${world['totalEntities']}, '
          'update ${perf['lastUpdateMs']} ms';
    },
  );
  engine.terminal.registerCommand(
    name: 'timescale',
    description: 'Set the time scale. Usage: timescale <value>',
    handler: (args) {
      final value = args.isEmpty ? null : double.tryParse(args.first);
      if (value == null || value < 0) return 'Usage: timescale <value>';
      engine.time.timeScale = value;
      return 'time scale $value';
    },
  );
}
```

A handler gets the words after the command name and returns a line to print, or null to print nothing. A command name is one word; registering a name again replaces its handler.

## Engine stats

`engine.performanceStats` is safe to read in any state. It covers the last fixed step:

| Key | What it is |
|---|---|
| `frame` | Fixed steps run while the engine was running, since it was made. |
| `deltaTime` | The `dt` of the last step: the fixed step times the time scale. |
| `lastUpdateMs` | Milliseconds the last step's update tasks took together. |
| `budgetRemainingMs`, `isOverBudget` | The last step measured against a 16.67 ms frame. |
| `systemTimesMs` | Milliseconds per update task: `input`, `ecs`, and any you registered. Physics and particles are inside `ecs`. |
| `scheduler` | `engine.systemManager.schedulerStats`: task count and timings. |

The subsystems' own figures exist only between `initialize()` and `dispose()`; check `engine.isInitialized` first when that can happen.

- **`engine.world.stats`**: `totalEntities`, `activeEntities`, `systems`, `activeSystems`, `archetypes` (a number that keeps growing points to component churn), `lastUpdateMs`, `lastCommandFlushes`, and `systemTimesMs` with each system's update time by type name, plus `TransformHierarchy`.
- **`engine.physics.stats`**: `bodyCount`, `awakeBodies`, `lastStepMs` and the pure-Dart engine's broadphase counters. On native platforms, `backend` is `box2d_v3`, or `dart_fallback` when the Box2D library did not load; the web has no `backend` key.
- **`engine.rendering.stats`**: `lastRenderMs`, `drawCalls`, `renderedObjects`, `culledObjects`, `batchedSprites` and `postProcessPasses` for the whole frame. `world.getSystem<RenderSystem>()?.stats` holds what the world's `RenderSystem` drew.
- **Live getters**: `engine.gameLoop.currentFPS` and `interpolation`; `engine.time.deltaTime`, `totalTime`, `timeScale` and `frameCount`; `engine.cache.isUsingMemoryFallback`; and `engine.assets.cacheStats` for loaded assets and their estimated memory.

> **Note:** Timings are measured in debug and profile builds only. In a release build `engine.systemManager.profiling` and `engine.world.profiling` are off and the timings read 0; set them to `true` to measure anyway.

One map with every subsystem's figures, to log or send to telemetry:

```dart
Map<String, dynamic> snapshot(Engine engine) => {
  ...engine.performanceStats,
  if (engine.isInitialized) ...{
    'fps': engine.gameLoop.currentFPS,
    'ecs': engine.world.stats,
    'physics': engine.physics.stats,
    'rendering': engine.rendering.stats,
    'cacheInMemory': engine.cache.isUsingMemoryFallback,
  },
  'assets': engine.assets.cacheStats,
};
```

The overlay shows no update or physics timings; draw your own from these maps, for example from `lastUpdateMs`, `systemTimesMs` and `physics.stats['lastStepMs']`.

## When something does not work

| What you see | Likely cause |
|---|---|
| A blank screen, nothing moves | No `defaultSystems` in `EngineConfig`, or `engine.start()` was not called. |
| `EngineNotReadyError` | `engine.world` or another subsystem was used before `await engine.initialize()`, or after `dispose()`. |
| `StateError` from `start()` | The engine is not initialized, or already running. |
| Things appear in the wrong place | +Y is down, and the camera's position is the world point in the middle of the screen. |
| A sprite does not show | The file is not listed under `flutter: assets:`, or the atlas image is not beside its JSON. |
| An animator never changes state | It needs a `SpriteAnimationComponent` on the same entity. A parameter whose `binding` is not registered in `engine.context.animatorBindings` silently keeps its default. |
| Particles do not move | `ParticleSystem` was not added; it is not a default system. |
| `UnknownComponentTypeException` loading a level | The package that defines the component was not given to `EngineConfig(extensions: ...)`. |
| The player falls through a map on the first frame | Call `await LevelMaps.preload(world)` after loading the scene. |
| Your system reads stale input or runs after physics | Its priority: character control belongs at `SystemPriorities.playerControl` (95). |
| No collider outlines | Add a `Collider2DDebuggerSystem` to the world, or use `GameWidget(showDebug: true)`. |
| Every timing reads 0 | A release build: see the note above. |
| No sound on the web until the first click | Expected: browsers keep audio silent until the player interacts. |
