# Just Game Engine - Architectural and Design Blueprints

> **Version:** 1.2.1  
> **Date:** March 15, 2026  
> **Scope:** `packages/just_game_engine` — a 2D Flutter game engine

---

## Table of Contents

1. [Overview & Package Metadata](#1-overview--package-metadata)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Engine Core & Lifecycle](#3-engine-core--lifecycle)
4. [Per-Frame Data Flow](#4-per-frame-data-flow)
5. [Rendering System](#5-rendering-system)
6. [Entity-Component-System (ECS)](#6-entity-component-system-ecs)
7. [Physics System](#7-physics-system)
8. [Input System](#8-input-system)
9. [Audio System](#9-audio-system)
10. [Animation System](#10-animation-system)
11. [Asset Management](#11-asset-management)
12. [Scene Graph & Editor](#12-scene-graph--editor)
13. [Reactive ECS Layer](#13-reactive-ecs-layer)
14. [Design Patterns Reference](#14-design-patterns-reference)
15. [Known Gaps & Future Work](#15-known-gaps--future-work)
16. [Tiled Map Integration](#16-tiled-map-integration)

---

## 1. Overview & Package Metadata

`just_game_engine` is a cross-platform 2D game engine built on top of Flutter. It provides a complete game-development framework including a fixed-timestep game loop, a layer-based rendering pipeline, ECS (Entity-Component-System) architecture, sprite/particle systems, physics, audio mixing, input unification, asset loading, animation, and a scene graph. The engine integrates directly into Flutter's widget tree via `GameWidget`, making it possible to embed game views anywhere in a Flutter application.

| Field | Value |
|---|---|
| **Package name** | `just_game_engine` |
| **Version** | `1.2.1` |
| **Dart SDK** | `^3.11.0` |
| **Flutter** | `>=1.17.0` |
| **Runtime dependency** | `flutter_soloud: ^3.5.0` |
| **Dev dependencies** | `flutter_test`, `flutter_lints: ^6.0.0` |
| **Companion packages** | `just_tiled: ^0.2.0` (Tiled map support), `just_zstd: ^1.0.0` (Zstandard decompressor) |
| **Repository** | https://github.com/just-unknown-dev/just-game-engine |

### Source Layout

```
packages/just_game_engine/
├── lib/
│   ├── just_game_engine.dart          ← public API barrel export
│   └── src/
│       ├── core/                      ← Engine, GameLoop, TimeManager, SystemManager, Lifecycle
│       ├── rendering/                 ← RenderingEngine, Renderables (incl. RayRenderable), Sprite, Camera, GameWidget, Particles
│       ├── physics/                   ← PhysicsEngine, PhysicsBody, ray_casting (Ray, RaycastColliderComponent, RaycastSystem, RayTracer)
│       ├── input/                     ← InputManager, Keyboard/Mouse/Touch/Controller
│       ├── audio/                     ← AudioEngine, AudioClip
│       ├── animation/                 ← AnimationSystem, Tweens, Easings
│       ├── assets/                    ← AssetManager, Asset types
│       ├── ecs/                       ← World, Entity, Component, System, built-ins
│       ├── reactive/                  ← ComponentSignal, EntitySignal, WorldSignal, ReactiveSystem, ReactiveComponent
│       ├── editor/                    ← SceneEditor, Scene, SceneNode
│       └── networking/                ← NetworkManager (Upcoming)
├── example/
├── test/
└── pubspec.yaml

Companion packages (separate pub packages, used alongside just_game_engine):
  packages/just_tiled/
  │   ├── lib/src/parser/             ← TileMapParser (async TMX/TSX parser)
  │   ├── lib/src/renderer/          ← TileMapRenderer (Canvas.drawRawAtlas), TextureAtlas
  │   ├── lib/src/models/            ← TileMap, Layer types, Tileset, MapObject, TileData
  │   └── lib/src/spatial/           ← SpatialHashGrid<T>
  packages/just_zstd/
      └── lib/src/                   ← ZstdDecoder (Zstandard RFC 8878 decompressor)
```

---

## 2. High-Level Architecture

The engine is organized into **six horizontal layers**, each depending only on the layers below it.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Flutter Widget Layer                             │
│   GameWidget (StatefulWidget + CustomPainter + Ticker + event routing)  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │  vsync ticks · key/pointer events
┌──────────────────────────────▼──────────────────────────────────────────┐
│                         Engine Core Layer                               │
│    Engine (singleton FSM) ─ GameLoop ─ TimeManager ─ SystemManager      │
└───┬──────┬───────┬──────────┬────────┬──────────────┬───────┬───────────┘
    │      │       │          │        │              │       │
┌───▼──┐ ┌─▼────┐ ┌▼──────┐ ┌▼─────┐ ┌▼──────────┐ ┌▼─────┐ ┌▼─────────┐
│Render│ │Physic│ │Input  │ │Audio │ │ Animation │ │Asset │ │ Network  │
│Engine│ │Engine│ │Manager│ │Engine│ │ System    │ │Manag.│ │ Manager  │
└───┬──┘ └──────┘ └───────┘ └──────┘ └───────────┘ └──┬───┘ └──────────┘
    │                                                   │
┌───▼───────────────────────────────────────────────────▼─────────────────┐
│                       ECS World Layer                                   │
│  World ─ Entity ─ Component bag ─ System (priority-ordered dispatch)    │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────────────┐
│                     Scene Graph Layer                                   │
│          SceneEditor ─ Scene ─ SceneNode (tree) ─ Renderable attach     │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │  canvas · AssetManager
┌──────────────────────────▼──────────────────────────────────────────────┐
│              Tiled Map Layer  (just_tiled companion package)            │
│   TileMapParser ─ TileMap ─ TileMapRenderer ─ TextureAtlas              │
│   SpatialHashGrid<T> ─ MapObject queries                                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Subsystem Dependency Map

```
Engine
 ├─► GameLoop          uses  TimeManager
 ├─► SystemManager     registrar for all subsystems
 ├─► RenderingEngine   uses  Camera, List<Renderable>, AssetManager (indirect)
 ├─► PhysicsEngine     standalone; mirrored by PhysicsSystem in World; ray-casting queries via RaycastSystem / RayTracer
 ├─► InputManager      aggregates Keyboard/Mouse/Touch/Controller
 ├─► AudioEngine       uses  flutter_soloud (SoLoud C++ engine via FFI)
 ├─► AnimationSystem   uses  Renderable (to mutate properties)
 ├─► AssetManager      uses  Flutter rootBundle / dart:ui codec
 ├─► SceneEditor       uses  SceneNode → Renderable → RenderingEngine
 ├─► World (ECS)       owns  List<Entity>, List<System>
 ├─► NetworkManager    (upcoming)
 │
 │  External companion packages (not owned by Engine, used alongside it):
 ├─► just_tiled
 │     ├── TileMapParser    uses  AssetManager / rootBundle to load .tmx / .tsx
 │     ├── TextureAtlas     uses  dart:ui codec to build packed atlas image
 │     ├── TileMapRenderer  uses  Canvas.drawRawAtlas (RenderingEngine canvas)
 │     └── SpatialHashGrid  standalone; application code bridges to ECS queries
 └─► just_zstd
       └── ZstdDecoder      used by TileMapParser for Zstandard-compressed tile data
```

---

## 3. Engine Core & Lifecycle

### 3.1 Engine State Machine

`Engine` is the central singleton that orchestrates all subsystems. It enforces legal state transitions via an `EngineState` enum.

```
                    initialize()
  uninitialized  ──────────────►  initialized
                                       │
                                 start()│
                                       ▼
                              ┌──── running ◄──── resume() ───┐
                              │        │                       │
                              │      pause()                   │
                              │        ▼                       │
                              │      paused ───────────────────┘
                              │
                            stop()
                              │
                              ▼
                           initialized (stopped)
                              │
                           dispose()
                              │
                              ▼
                         uninitialized
```

**Guard conditions:** Each transition method checks the current `EngineState` and throws if the requested transition is illegal (e.g., calling `start()` while already running).

**Singleton access:**
```dart
final engine = Engine.instance;        // factory constructor
Engine.resetInstance();                // test isolation — clears singleton
```

---

### 3.2 Initialization Order

When `Engine.initialize()` is called, subsystems are brought up in dependency order:

| Step | Subsystem | Reason for position |
|---|---|---|
| 1 | `TimeManager` | Needed by `GameLoop` immediately |
| 2 | `SystemManager` | Registry must exist before anything registers |
| 3 | `GameLoop` | Wired to `_update` + `_render` callbacks, references `TimeManager` |
| 4a | `AssetManager` | First subsystem; others may load assets during init |
| 4b | `RenderingEngine` | Creates default `Camera` |
| 4c | `PhysicsEngine` | — |
| 4d | `InputManager` | — |
| 4e | `AudioEngine` | — |
| 4f | `SceneEditor` | — |
| 4g | `AnimationSystem` | — |
| 4h | `NetworkManager` | — |
| 5 | `World` (ECS) | Invokes `System.initialize()` on all pre-added systems |

After each subsystem initializes, it is registered with `SystemManager` by both **name** (string) and **type** (generic `T`).

---

### 3.3 Shutdown Order

`Engine.dispose()` tears down subsystems in **reverse initialization order** to respect dependencies:

```
NetworkManager → AnimationSystem → SceneEditor → AudioEngine
→ InputManager → PhysicsEngine → RenderingEngine → AssetManager
→ World → SystemManager
```

---

### 3.4 GameLoop — Fixed-Timestep Algorithm

`GameLoop` drives the update cycle at a configurable `targetUPS` (updates per second, default 120). It decouples physics/game-logic tick rate from the Flutter frame rate.

```
GameLoop.start()
    │
    └── Timer.periodic(1/targetUPS)
              │
              ▼ each tick
         frameTime = now - lastTime
         clamp frameTime to MAX_DELTA (prevents spiral of death)
         TimeManager.update(frameTime)
         accumulator += scaled frameTime
         while accumulator >= fixedDt:
             Engine._update(fixedDt)    ← game logic at fixed rate
             accumulator -= fixedDt
         interpolationAlpha = accumulator / fixedDt  ← for future lerp
```

**Key properties:**
- `targetUPS` — target updates per second (default: 120)
- `fixedDt` — `1.0 / targetUPS`
- `accumulator` — leftover time carried between ticks
- `interpolationAlpha` — fraction into current step for sub-frame interpolation

---

### 3.5 TimeManager

Tracks all temporal state for the engine. Consumed by `GameLoop` and exposed to game code.

| Property | Type | Description |
|---|---|---|
| `deltaTime` | `double` | Seconds elapsed last step (scaled by `timeScale`) |
| `unscaledDeltaTime` | `double` | Raw seconds elapsed, ignoring time scale |
| `totalTime` | `double` | Accumulated scaled time since engine start |
| `timeScale` | `double` | Multiplier applied to `deltaTime` (0 = pause, 0.5 = half speed) |
| `frameCount` | `int` | Total frames processed |
| `fps` | `double` | Frames per second (rolling average) |
| `getSmoothDeltaTime()` | `double` | **TODO** — planned smooth/filtered delta |

---

### 3.6 SystemManager

Implements the **Service Locator** pattern. All subsystems register themselves on initialization.

```dart
// Registration (done internally by Engine)
systemManager.registerSystem('rendering', renderingEngine);

// Retrieval (used by game code or other subsystems)
final renderer = engine.systems.getSystem<RenderingEngine>();
final renderer = engine.systems.getSystemByName('rendering');
```

---

### 3.7 Lifecycle Interfaces

Defined in `lifecycle.dart`. All subsystem classes implement the appropriate interfaces.

| Interface | Methods | Implementors |
|---|---|---|
| `ILifecycle` | `initialize()`, `dispose()` | All subsystems, `Engine` |
| `IUpdatable` | `update(double deltaTime)` | `PhysicsEngine`, `AnimationSystem`, `AudioEngine`, `World`, input handlers |
| `IRenderable` | `render(Canvas, Size)` | `RenderingEngine`, `World` |
| `IPausable` | `pause()`, `resume()` | `AudioEngine`, `GameLoop`, `AnimationSystem` |
| `IEnableable` | `enable()`, `disable()`, `isEnabled` | Any optional subsystem/system |
| `LifecycleStateMixin` | `_isInitialized`, `_isDisposed` state booleans | Mixed into subsystems for guard checks |

---

## 4. Per-Frame Data Flow

Two completely independent pipelines run each frame: the **update pipeline** (logic, driven by `GameLoop`) and the **render pipeline** (visuals, driven by Flutter's vsync).

### 4.1 Update Pipeline

```
 Timer.periodic (GameLoop)
         │
         ▼
 TimeManager.update(rawFrameTime)
   └── clamp, scale, accumulate
         │
   while accumulator >= fixedDt:
         │
  ┌──────▼────────────────────────────────────────────────┐
  │  Engine._update(fixedDt)                              │
  │                                                       │
  │  1. InputManager.update()                             │
  │       ├── diff keysDown/Released sets                 │
  │       ├── compute keyboard axes (WASD/arrows)         │
  │       └── clear per-frame mouse delta/scroll          │
  │                                                       │
  │  2. PhysicsEngine.update(dt)                          │
  │       ├── apply gravity + drag to each PhysicsBody    │
  │       ├── integrate position: pos += vel * dt         │
  │       ├── broad-phase circle collision detection      │
  │       └── impulse resolution + positional correction  │
  │                                                       │
  │  3. AnimationSystem.update(dt)                        │
  │       └── advance all registered Animation instances  │
  │             ├── SpriteAnimation → advance frame       │
  │             ├── TweenAnimation → interpolate + ease   │
  │             ├── AnimationSequence → chain next        │
  │             └── AnimationGroup → run all in parallel  │
  │                                                       │
  │  4. AudioEngine.update()                              │
  │       └── clean up completed AudioClip references     │
  │                                                       │
  │  5. World.update(dt)   ← ECS dispatch                 │
  │       └── for each System (sorted by priority desc):  │
  │             ├── MovementSystem    pos += vel * dt      │
  │             ├── HierarchySystem   propagate transforms │
  │             ├── PhysicsSystem  physics on entities  │
  │             ├── HealthSystem      regen + death event  │
  │             ├── LifetimeSystem    countdown + destroy  │
  │             ├── AnimationSystemECS advance anim timers │
  │             └── BoundarySystem   clamp/bounce/wrap     │
  └───────────────────────────────────────────────────────┘
        accumulator -= fixedDt
```

---

### 4.2 Render Pipeline

```
 Flutter Vsync (Ticker in GameWidget)
         │
         ▼
 GameWidget._onTick()
   └── setState() → marks widget dirty
         │
         ▼
 Flutter build → CustomPaint(painter: _GamePainter)
         │
         ▼
 _GamePainter.paint(Canvas canvas, Size size)
   └── RenderingEngine.render(canvas, size)
         │
         ├── canvas.save()
         ├── Camera.applyTransform(canvas)
         │     ├── translate by -camera.position
         │     ├── scale by camera.zoom
         │     └── rotate by camera.rotation
         │
         ├── sort _renderables by (layer, zOrder)
         │
         └── for each Renderable in sorted order:
               Renderable.render(canvas, size)
                 ├── RectangleRenderable  canvas.drawRect()
                 ├── CircleRenderable     canvas.drawCircle()
                 ├── LineRenderable       canvas.drawLine()
                 ├── TextRenderable       TextPainter.paint()
                 ├── Sprite               canvas.drawImageRect()
                 ├── NineSliceSprite      9x canvas.drawImageRect()
                 ├── ParticleEmitter      canvas.drawCircle() × N
                 └── CustomRenderable     user callback(canvas, size)
         │
         canvas.restore()
```

---

### 4.3 Input Event Routing

```
 Flutter key/pointer events
         │
         ▼
 GameWidget.onKeyEvent(KeyEvent)
   └── InputManager.handleKeyEvent(event)
         ├── KeyboardInput._keysDown.add/remove(logicalKey)
         ├── KeyboardInput._keysPressed.add(key) if KeyDownEvent
         └── KeyboardInput._keysReleased.add(key) if KeyUpEvent

 GameWidget → Listener widget
   └── onPointerDown/Move/Up/Hover/Scroll
         ├── MouseInput._position = event.localPosition
         ├── MouseInput._delta accumulated
         ├── MouseInput._buttons updated
         ├── MouseInput._scrollDelta updated
         └── TouchInput._activeTouches map updated (multitouch)
```

---

### 4.4 Asset → Rendering Flow

```
 AssetManager.load('images/hero.png')
         │
         ▼
 ImageAsset.load()
   └── rootBundle.load(path)           ← Flutter bundle
   └── ui.instantiateImageCodec()      ← decode PNG/JPG
   └── codec.getNextFrame()
   └── _image = frame.image            ← dart:ui Image object

 Sprite(image: assetManager.get<ImageAsset>('images/hero.png').image)
         │
         ▼
 renderingEngine.addRenderable(sprite)
         │
         ▼
 [each render frame]
 Sprite.render(canvas, size)
   └── canvas.drawImageRect(image, src, dst, paint)
```

---

## 5. Rendering System

### 5.1 Renderable Hierarchy

```
Renderable  (abstract)
   │  position: Offset
   │  rotation: double
   │  scale: double
   │  opacity: double
   │  layer: int
   │  zOrder: int
   │  isVisible: bool
   │  render(Canvas, Size)  ← abstract
   │
   ├── RectangleRenderable   canvas.drawRect()    fillColor, strokeColor, strokeWidth, cornerRadius
   ├── CircleRenderable      canvas.drawCircle()  fillColor, strokeColor, strokeWidth
   ├── LineRenderable        canvas.drawLine()    color, strokeWidth, startPoint, endPoint
   ├── TextRenderable        TextPainter          text, style, alignment, maxWidth
   ├── CustomRenderable      user Function(Canvas, Size) callback
   ├── Sprite                canvas.drawImageRect() → see §5.2
   ├── NineSliceSprite       9 drawImageRect() calls → see §5.2
   └── ParticleEmitter       owns List<Particle> → see §5.3
```

All `Renderable` subclasses have `copyWith()` methods and support method-chained configuration.

---

### 5.2 Sprite & SpriteSheet

**`Sprite`**
- Wraps a `dart:ui Image`
- Properties: `sourceRect` (UV crop), `color` tint, `flipX`, `flipY`, `blendMode`
- Renders via `canvas.drawImageRect(image, sourceRect, destRect, paint)`

**`SpriteSheet`**
- Constructed with `spriteWidth`, `spriteHeight`, `spacing`, `margin`
- Pre-computes `List<Rect>` for every frame at construction time
- `getSprite(int index)` returns a configured `Sprite` stamped with that frame's `sourceRect`
- Flyweight: the source image is shared; only `sourceRect` differs per frame

**`NineSliceSprite`**
- Constructed with `top/bottom/left/right` border insets
- Splits source image into 9 sectors and draws each into the corresponding destination sector
- Used for scalable UI elements (buttons, panels) without distorting corners

---

### 5.3 Particle System

```
ParticleEmitter  (extends Renderable)
   │  emissionRate: double       particles/second
   │  maxParticles: int
   │  emitterPosition: Offset
   │  gravity: Offset
   │  startColor / endColor: Color
   │  startSize / endSize: double
   │  minSpeed / maxSpeed: double
   │  minLifetime / maxLifetime: double
   │  spread: double             angle spread in radians
   │  List<Particle> _particles
   │
   └── update(dt)
         ├── spawn new particles at emissionRate (dt-fractional)
         ├── for each Particle:
         │     vel += gravity * dt
         │     pos += vel * dt
         │     age += dt
         │     if age >= lifetime: remove
         └── render(canvas):
               color = lerp(startColor, endColor, t)
               size  = lerp(startSize, endSize, t)
               canvas.drawCircle(pos, size, paint)

Particle
   position: Offset
   velocity: Offset
   age: double
   lifetime: double
   color: Color (lerped at render time)
   size: double  (lerped at render time)
```

**Preset effects** are factory constructors on `ParticleEmitter`:
- `ParticleEmitter.explosion(...)` — radial burst, short lifetime
- `ParticleEmitter.smoke(...)` — slow upward drift, dark colors
- `ParticleEmitter.sparkle(...)` — bright, fast, short-lived

---

### 5.4 Camera

```
Camera
   position: Offset        world-space center of view
   zoom: double            scale factor (1.0 = 100%)
   rotation: double        radians, clockwise
   smoothSpeed: double     lerp factor for smooth follow

   applyTransform(Canvas canvas)
     canvas.translate(viewport.center)
     canvas.scale(zoom)
     canvas.rotate(rotation)
     canvas.translate(-position)

   worldToScreen(Offset world) → Offset screen
   screenToWorld(Offset screen) → Offset world

   follow(Offset target, double dt)
     position = lerp(position, target, smoothSpeed * dt)

   shake(double intensity, double duration)   ← TODO (not yet implemented)
```

---

### 5.5 GameWidget & Flutter Integration

```
GameWidget  (StatefulWidget)
   │  engine: Engine
   │  focusNode: FocusNode   ← captures keyboard events
   │
   └── State._initState():
         ticker = createTicker(_onTick)..start()

   _onTick(Duration elapsed):
     setState(() {})          ← triggers repaint every vsync

   build():
     Focus(
       focusNode: focusNode,
       onKeyEvent: inputManager.handleKeyEvent,
       child: Listener(
         onPointerDown/Move/Up/Hover/Signal: inputManager.handlePointer*,
         child: CustomPaint(
           painter: _GamePainter(engine),
           child: gameContent,
         ),
       ),
     )

_GamePainter  (CustomPainter)
   shouldRepaint(): always true (game frames are always dirty)
   paint(Canvas, Size): engine.rendering.render(canvas, size)
```

---

## 6. Entity-Component-System (ECS)

### 6.1 Core Primitives

```
typedef EntityId = int;

Entity
   id: EntityId             (auto-incremented by World)
   Map<Type, Component>     component bag

Component  (abstract)
   (no fields — pure data container marker)

System  (abstract)
   world: World             (injected by World on registration)
   requiredComponents: List<Type>   ← components an entity must have
   priority: int            (higher = runs first)
   isEnabled: bool
   initialize()
   update(double deltaTime)
   render(Canvas, Size)     (optional — default no-op)

World
   List<Entity> _entities
   List<System> _systems    (sorted by priority descending)

   addEntity()  → EntityId
   removeEntity(id)
   addComponent(id, component)
   removeComponent<T>(id)
   getComponent<T>(id) → T?
   getEntitiesWith(List<Type> components) → List<Entity>
   addSystem(system)
   update(dt) → dispatches to all enabled Systems
   render(canvas, size)    ← must be called manually
```

---

### 6.2 Built-in Components

| Component | Key Fields | Purpose |
|---|---|---|
| `TransformComponent` | `position: Offset`, `rotation: double`, `scale: double` | World-space transform for every game object |
| `VelocityComponent` | `velocity: Offset`, `maxSpeed: double` | Linear movement rate |
| `RenderableComponent` | `renderable: Renderable` | Links an entity to a drawable |
| `PhysicsBodyComponent` | `radius`, `mass`, `restitution`, `drag`, `isStatic`, `collisionLayers` | Physical simulation properties |
| `TagComponent` | `tag: String` | String marker for filtering/querying |
| `LifetimeComponent` | `lifetime: double`, `age: double` | Auto-destroys entity after countdown |
| `HealthComponent` | `health`, `maxHealth`, `regenRate`, `isInvulnerable` | Hit-points with optional regeneration |
| `ParentComponent` | `parentId: EntityId`, `localOffset: Offset`, `localRotation: double` | Parent-child transform hierarchy |
| `ChildrenComponent` | `children: List<EntityId>` | Inverse parent reference list |
| `InputComponent` | `moveDirection: Offset`, `buttons: Map<String, bool>` | Input state posted by InputManager |
| `AnimationStateComponent` | `currentAnimation: String`, `time`, `isPlaying`, `loop` | Per-entity animation playback state |
| `SpriteComponent` | `spritePath: String`, `frame: int`, `flipX`, `flipY`, `tint: Color?` | Sprite descriptor for the render system |

---

### 6.3 Built-in Systems

| System | Required Components | Priority | Responsibility |
|---|---|---|---|
| `MovementSystem` | `Transform` + `Velocity` | — | `position += velocity * dt` |
| `HierarchySystem` | `Transform` + `Parent` | high | Propagates parent world transform to children |
| `PhysicsSystem` | `Transform` + `Velocity` + `PhysicsBody` | — | Gravity, drag, circle collision between all pairs |
| `RenderSystem` | `Transform` + `Renderable` | low | Syncs `TransformComponent` into `Renderable`, calls `render()` |
| `HealthSystem` | `Health` | — | Applies `regenRate * dt`, fires death event at 0 HP |
| `LifetimeSystem` | `Lifetime` | — | Increments age; calls `world.removeEntity()` at expiry |
| `AnimationSystemECS` | `AnimationState` | — | Advances animation timers in `AnimationStateComponent` |
| `BoundarySystem` | `Transform` | — | Enforces world boundaries (clamp / bounce / wrap / destroy) |
| `InputSystem` *(custom)* | `Input` | very high | Must be provided by the game; bridges `InputManager` → `InputComponent` |

---

### 6.4 Two Rendering Paths

```
Path A — ECS-driven:
  RenderableComponent.renderable → RenderSystem.render()
  → syncs TransformComponent → Renderable properties
  → calls Renderable.render(canvas, size)
  Note: World.render(canvas, size) must be called manually from
        inside a game-provided Renderable or from GameWidget.

Path B — Direct:
  renderingEngine.addRenderable(myRenderable)
  → managed by RenderingEngine's own sorted list
  → called automatically each frame by _GamePainter
```

Both paths can coexist. ECS entities that also attach their `RenderableComponent.renderable` to `RenderingEngine` will render automatically via Path B.

---

## 7. Physics System

### 7.1 Standalone PhysicsEngine

`PhysicsEngine` runs independently of ECS. Game objects call `addBody()` to register and can be updated without any component overhead.

```
PhysicsEngine
   List<PhysicsBody> _bodies
   SpatialGrid _spatialGrid  (broad-phase optimization)
   CacheManager? cacheManager
   gravity: Offset       (default: Offset(0, 98.0) — pixels/s²)
   enabled: bool

   update(dt):
     for each body (non-static):
       if (!body.isAwake) continue
       body.velocity += (body.acceleration + gravity) * dt
       body.velocity *= (1 - body.drag * dt)
       body.angularVelocity += (body.torque * body.invInertia) * dt
       body.angularVelocity *= (1 - body.drag * dt)
       body.position += body.velocity * dt
       body.angle += body.angularVelocity * dt
       clear acceleration and torque
     
       // Object Sleeping logic
       if velocity and acceleration are very low for sleepTimeThreshold:
         body.isAwake = false
     
     _detectCollisions()

   _detectCollisions():
     Populate _spatialGrid using body.shape.getBounds()
     for each potential pair in cells:
       CollisionManifold? manifold = SAT.test(A.shape, B.shape)
       if manifold.isColliding:
         _resolveCollision(A, B, manifold)

   _resolveCollision(A, B, manifold):
     // Linear projection to prevent sinking
     A.position -= manifold.normal * overlap * ratioA
     B.position += manifold.normal * overlap * ratioB
     
     // Wake up bodies
     A.isAwake = true; B.isAwake = true
     
     // True Impulse Resolution
     compute relative velocity along normal
     e = min(A.restitution, B.restitution)
     j = -(1 + e) * relVel / totalInvMass
     apply normal impulses scaling by invMass
     
     // Coulomb Surface Friction
     compute tangent vector t
     compute friction impulse scalar jt and clamp by j * mu
     apply tangent impulses
```

**`PhysicsBody` Properties:**

| Property | Type | Description |
|---|---|---|
| `position` | `Offset` | World-space center |
| `velocity` | `Offset` | Linear velocity (pixels per second) |
| `angularVelocity` | `double` | Angular velocity (radians per second) |
| `mass` | `double` | Kg-equivalent (0 = static) |
| `shape` | `CollisionShape` | Physical geometry (Circle, Poly, Rect) |
| `restitution` | `double` | Bounciness 0–1 |
| `friction` | `double` | Surface friction scalar |
| `drag` | `double` | Velocity damping coefficient |
| `isAwake` | `bool` | True if actively updated (Object Sleeping) |
| `collisionLayers` | `int` | Bitmask; bodies only collide if layers overlap |

---

### 7.2 ECS Physics — PhysicsSystem

Mirrors `PhysicsEngine` logic but operates on entities carrying `PhysicsBodyComponent`, `TransformComponent`, and `VelocityComponent`. Reads mass/drag etc. from the component; writes back to `TransformComponent.position` and `VelocityComponent.velocity`.

---

### 7.3 Advanced Features & Caching

The Physics engine is integrated with the `CacheManager`. Heavy polygonal operations like triangulations or pre-computed structures can be saved to persistent storage via `cachePolygonShape` and retrieved via `getCachedPolygonShape`. This drastically minimizes load times for scenes with dense rigid-body structures.

---

## 8. Input System

### 8.1 Architecture

```
InputManager
   ├── KeyboardInput    _keyboard
   ├── MouseInput       _mouse
   ├── TouchInput       _touch
   └── ControllerInput  _controller

   update():
     _keyboard.update()     ← compute axes, clear per-frame pressed/released
     _mouse.update()        ← clear per-frame delta/scroll
     _touch.update()
     _controller.update()   ← poll gamepad state

   handleKeyEvent(KeyEvent)     → routes to _keyboard
   handlePointerEvent(event)    → routes to _mouse / _touch
```

---

### 8.2 KeyboardInput

| Property / Method | Description |
|---|---|
| `isKeyDown(key)` | True while key is held |
| `isKeyPressed(key)` | True only the frame the key went down |
| `isKeyReleased(key)` | True only the frame the key went up |
| `horizontalAxis` | `double` in [-1, 1] — `A`/`←` negative, `D`/`→` positive |
| `verticalAxis` | `double` in [-1, 1] — `W`/`↑` negative, `S`/`↓` positive |

---

### 8.3 MouseInput

| Property / Method | Description |
|---|---|
| `position` | `Offset` — cursor position in widget-local coords |
| `delta` | `Offset` — movement since last frame (cleared in `update()`) |
| `scrollDelta` | `double` — scroll wheel delta (cleared in `update()`) |
| `isButtonDown(MouseButton btn)` | True while button held |
| `isButtonPressed(btn)` | True only the frame it went down |
| `isButtonReleased(btn)` | True only the frame it went up |

`MouseButton` constants: `left`, `right`, `middle`, `back`, `forward`.

---

### 8.4 TouchInput

| Property / Method | Description |
|---|---|
| `activeTouches` | `Map<int, TouchPoint>` keyed by pointer ID |
| `touchCount` | Number of active fingers |
| `getTouch(int id)` | Returns `TouchPoint` for that pointer |

`TouchPoint` carries `position`, `delta`, `startPosition`, `duration`.

---

### 8.5 ControllerInput

| Property / Method | Description |
|---|---|
| `leftStick` | `Offset` — axis values after dead-zone filtering |
| `rightStick` | `Offset` — axis values after dead-zone filtering |
| `leftTrigger` | `double` [0, 1] |
| `rightTrigger` | `double` [0, 1] |
| `isButtonDown(String btn)` | Generic button query |
| `dpad` | `Offset` — D-pad as normalized direction |
| `deadZone` | `double` — configurable; default 0.1 |

---

## 9. Audio System

### 9.1 Architecture

```
AudioEngine
   │  Map<AudioChannel, double> _channelVolumes
   │  Map<String, AudioSource>  _sfxSources   (cached per asset path)
   │  Map<String, AudioClip>    _activeClips
   │  AudioClip? _currentMusic
   │
   ├── initialize()    → await SoLoud.instance.init()
   │
   ├── playSfx(path, {volume, loop})
   │     └── loadAsset(path) → AudioSource  (cached)
   │     └── SoLoud.instance.play(source, volume, looping)
   │     └── returns clip id string
   │
   ├── playMusic(path, {volume, loop, fadeIn})
   │     └── loadAsset(path) → AudioSource
   │     └── SoLoud.instance.play(source, looping: true)
   │     └── SoLoud.instance.fadeVolume() for fade-in
   │
   ├── stopMusic({fadeOut})  → SoLoud.instance.fadeVolume() then stop()
   ├── pauseMusic() / resumeMusic()  → SoLoud.instance.setPause()
   ├── setChannelVolume(channel, volume)   ← 0.0–1.0
   ├── mute() / unmute() / toggleMute()
   └── setMasterVolume(v)
```

---

### 9.2 AudioClip

Holds an `AudioSource` (loaded asset) and a `SoundHandle` (active voice) from `flutter_soloud`. Returned by `playSfx()` / `playMusic()` for programmatic control.

| Method | Description |
|---|---|
| `play()` | Load asset (cached) and start a new voice via `SoLoud.instance.play()` |
| `pause()` | `SoLoud.instance.setPause(handle, true)` |
| `resume()` | `SoLoud.instance.setPause(handle, false)` |
| `stop()` | `SoLoud.instance.stop(handle)` |
| `setVolume(double v)` | Local volume [0–1]; `SoLoud.instance.setVolume(handle, v)` |
| `setLoop(bool loop)` | `SoLoud.instance.setLooping(handle, loop)` |
| `isPlaying` | `SoLoud.instance.getIsValidVoiceHandle(handle)` |
| `dispose()` | Stops the voice and calls `SoLoud.instance.disposeSource()` |
| `state` | `AudioState` enum: `stopped` \| `playing` \| `paused` |

---

### 9.3 Enums

```dart
enum AudioChannel { master, music, sfx, voice, ambient }
enum AudioState   { stopped, playing, paused }
```

---

## 10. Animation System

### 10.1 Class Hierarchy

```
Animation  (abstract)
   name: String
   isPlaying: bool
   isLooping: bool
   duration: double
   onComplete: VoidCallback?

   update(double dt)              ← calls updateAnimation(dt)
   updateAnimation(double dt)     ← abstract (Template Method)
   play() / pause() / stop() / reset()

   ├── SpriteAnimation
   │     sprite: Sprite
   │     frameRate: double
   │     frames: List<int>        ← indices into SpriteSheet
   │     currentFrame: int
   │     updateAnimation(dt): advance frame counter, update sprite.sourceRect
   │
   ├── TweenAnimation<T>
   │     startValue: T
   │     endValue: T
   │     easing: Easing            ← Strategy pattern
   │     updateAnimation(dt): t = elapsed/duration; apply easing; mutate target
   │
   │     ├── PositionTween        T=Offset → Renderable.position
   │     ├── RotationTween        T=double → Renderable.rotation
   │     ├── ScaleTween           T=double → Renderable.scale
   │     ├── OpacityTween         T=double → Renderable.opacity
   │     └── ColorTween           T=Color  → user-supplied callback
   │
   ├── AnimationSequence
   │     List<Animation> _animations
   │     _currentIndex: int
   │     updateAnimation(dt): drive current anim; on complete advance index
   │
   └── AnimationGroup
         List<Animation> _animations
         updateAnimation(dt): update all simultaneously; complete when all done
```

---

### 10.2 Easings Library

`Easings` provides 15+ static easing functions conforming to the `Easing` typedef (`double Function(double t)`).

| Category | Functions |
|---|---|
| **Linear** | `linear` |
| **Quadratic** | `easeInQuad`, `easeOutQuad`, `easeInOutQuad` |
| **Cubic** | `easeInCubic`, `easeOutCubic`, `easeInOutCubic` |
| **Quartic** | `easeInQuart`, `easeOutQuart`, `easeInOutQuart` |
| **Sine** | `easeInSine`, `easeOutSine`, `easeInOutSine` |
| **Exponential** | `easeInExpo`, `easeOutExpo` |
| **Elastic** | `easeInElastic`, `easeOutElastic` |
| **Bounce** | `easeOutBounce` |
| **Back** | `easeInBack`, `easeOutBack` |

Usage:
```dart
PositionTween(
  start: Offset(0, 0),
  end: Offset(200, 0),
  duration: 1.0,
  easing: Easings.easeOutBounce,
  target: myRenderable,
)
```

---

### 10.3 AnimationSystem Manager

```
AnimationSystem
   Map<String, Animation> _animations

   addAnimation(animation)        ← register by name
   removeAnimation(name)
   play(name)
   pause(name)
   stop(name)
   getAnimation(name) → Animation?
   update(dt): iterates all playing animations and calls animation.update(dt)
```

---

## 11. Asset Management

### 11.1 Class Hierarchy

```
Asset  (abstract)
   path: String
   type: AssetType
   isLoaded: bool

   Future<bool> load()    ← loads via Flutter rootBundle
   void unload()          ← releases cached data
   int getMemoryUsage()   ← bytes in memory

   ├── ImageAsset    → ui.Image   (PNG/JPG via dart:ui codec)
   ├── AudioAsset    → Uint8List  (MP3/WAV/OGG/FLAC; format auto-detected from extension)
   ├── TextAsset     → String     (plain UTF-8)
   ├── JsonAsset     → dynamic    (jsonDecode applied automatically)
   └── BinaryAsset   → Uint8List  (raw bytes)
```

---

### 11.2 AssetManager

```
AssetManager
   Map<String, Asset> _cache        ← keyed by asset path

   Future<T> load<T extends Asset>(String path)
     └── if cached: return existing
     └── else: create correct Asset subtype from extension
           └── asset.load()        ← hits Flutter rootBundle
           └── _cache[path] = asset
           └── return asset

   T? get<T extends Asset>(String path)   ← sync retrieval of loaded asset
   void unload(String path)
   void unloadAll()
   void preloadAll(List<String> paths)    ← parallel Future.wait()
   int getTotalMemoryUsage()              ← sum of all cached assets
```

---

### 11.3 Supported Data Formats

| Format | Asset Type | Notes |
|---|---|---|
| `.png`, `.jpg`, `.jpeg` | `ImageAsset` | Decoded to `dart:ui Image` via codec |
| `.mp3`, `.wav`, `.ogg`, `.flac` | `AudioAsset` | Loaded as `Uint8List`; played via `flutter_soloud` (`SoLoud.instance.loadAsset`) |
| `.txt` | `TextAsset` | Raw UTF-8 string |
| `.json` | `JsonAsset` | Auto-decoded with `dart:convert jsonDecode` |
| `.*` (other) | `BinaryAsset` | Raw `Uint8List` |

---

### 11.4 Asset Error Handling

Failures during `load()` throw `AssetLoadException(path, cause)`. Callers should `try/catch` and handle gracefully (fallback asset, show error overlay).

---

## 12. Scene Graph & Editor

### 12.1 Class Hierarchy

```
SceneEditor
   Map<String, Scene> _scenes
   String? _activeSceneName

   createScene(name) → Scene
   setActiveScene(name)
   getActiveScene() → Scene?
   saveScene(name)     ← TODO (not yet implemented)
   loadScene(name)     ← TODO

Scene
   String name
   SceneNode rootNode

   addNode(SceneNode, {parentId?})
   removeNode(id)
   getNode(id) → SceneNode?
   update(dt): rootNode.update(dt)    ← recursive tree traversal
   render(canvas, size): rootNode.render(canvas, size)

SceneNode
   String id
   String name
   Offset localPosition
   double localRotation
   double localScale
   Renderable? renderable     ← optional attached drawable
   SceneNode? parent
   List<SceneNode> children

   worldPosition → Offset    ← accumulates parent transforms up the tree
   worldRotation → double
   worldScale    → double

   addChild(SceneNode)
   removeChild(id)
   update(dt): update self + recurse into children
   render(canvas, size): apply world transform, render renderable, recurse
```

---

### 12.2 Transform Propagation

Each `SceneNode` computes its world transform lazily from its local transform and its parent's world transform:

```
worldPosition = parent.worldPosition
              + rotate(localPosition, parent.worldRotation)
              * parent.worldScale

worldRotation = parent.worldRotation + localRotation
worldScale    = parent.worldScale    * localScale
```

This means detaching a node and re-attaching it to a different parent will immediately change its world-space appearance on the next render.

---

## 13. Reactive ECS Layer

The `src/reactive/` directory provides signal-driven wrappers around the ECS primitives, powered by the `just_signals` package. This layer is entirely optional — the core ECS works without it — but enables Flutter widgets to rebuild surgically when specific component properties change rather than polling the world every frame.

### 13.1 Class Inventory

| Class | File | Role |
|---|---|---|
| `ComponentSignal<C, T>` | `component_signal.dart` | Typed `Signal` that binds to a single component property via getter/setter pair |
| `EntitySignal` | `entity_signal.dart` | Lazy per-component `Signal<T?>` accessors + active-state signal for one entity |
| `WorldSignal` | `world_signal.dart` | Entity/system count signals + reactive entity list; wraps a `World` |
| `ReactiveSystem` | `reactive_system.dart` | Abstract `System` subclass; only processes dirty entities (change-tracked set) |
| `ReactiveComponent` | `reactive_component.dart` | Mixin for `Component`; adds `propertySignal<T>()`, `notifyChange()`, `batchChanges()` |

### 13.2 Class Diagram

```
just_signals
  Signal<T> ◄─────────────────────────────────────────────────────┐
                                                                    │
packages/just_game_engine/lib/src/reactive/                        │
  ComponentSignal<C, T>  extends Signal<T>   ──────────────────────┘
  │  - _component : C
  │  - _getter    : T Function(C)
  │  - _setter    : void Function(C, T)
  │
  EntitySignal
  │  - _entity           : Entity
  │  - _componentSignals : Map<Type, Signal<Component?>>
  │  - _activeSignal     : Signal<bool>
  │  + component<T>()    → Signal<T?>
  │  + watch<T>(handler) → void
  │
  WorldSignal
  │  - _world            : World
  │  - _entityCount      : Signal<int>
  │  - _systemCount      : Signal<int>
  │  - _entitiesSignal   : Signal<List<Entity>>
  │  - _entitySignals    : Map<EntityId, EntitySignal>
  │  + entity(id)        → EntitySignal
  │  + refresh()         → void
  │
  ReactiveSystem  extends System
  │  - _dirtyEntities    : Set<EntityId>
  │  + markDirty(entity) : void
  │  + processEntity(entity, dt) abstract
  │
  ReactiveComponent  mixin on Component
     - _propertySignals  : Map<String, Signal<dynamic>>
     + propertySignal<T>(name, initial) → Signal<T>
     + notifyChange(propertyName)       → void
     + batchChanges(fn)                 → void
```

### 13.3 Data Flow

```
[Game loop update()]
        │
        │  System.update() sets component property
        ▼
  ReactiveComponent.notifyChange('position')
        │
        │  Signal.forceSet() notifies all subscribers
        ▼
  Signal observers (Effects / SignalBuilders in Flutter widget tree)
        │
        │  Flutter marks affected widgets dirty
        ▼
  Widget.build() runs only for affected subtree   ← surgical rebuild
```

### 13.4 Usage Snapshot

```dart
// Wrap a component property
final posX = ComponentSignal<TransformComponent, double>(
  player.getComponent<TransformComponent>()!,
  getter: (c) => c.position.dx,
  setter: (c, v) => c.position = Offset(v, c.position.dy),
);

// Observe world entity count in a widget
SignalBuilder(
  signal: WorldSignal(world).entityCount,
  builder: (_, count, __) => Text('$count entities'),
);

// Dirty-only processing
class HealthFlashSystem extends ReactiveSystem {
  @override
  List<Type> get requiredComponents => [HealthComponent, RenderableComponent];

  @override
  void processEntity(Entity e, double dt) {
    final hp = e.getComponent<HealthComponent>()!;
    e.getComponent<RenderableComponent>()!.opacity = hp.health < 20 ? 0.5 : 1.0;
  }
}
```

---

## 14. Design Patterns Reference

| Pattern | Implementation Location | Description |
|---|---|---|
| **Singleton** | `Engine` | `Engine._instance` + factory constructor; `Engine.resetInstance()` for test isolation |
| **Service Locator** | `SystemManager` | `getSystem<T>()` and `getSystemByName(String)` for runtime subsystem retrieval |
| **Observer / Callback** | `InputManager`, `Animation` | `onKeyEvent`/`onPointerEvent` listener registration; `Animation.onComplete` callback |
| **Asset Cache** | `AudioEngine._sfxSources` | `AudioSource` objects cached per asset path; SoLoud handles concurrent voices natively without a fixed pool |
| **Entity-Component-System** | `World`, `Entity`, `Component`, `System` | Data-oriented composition: entities are pure IDs; systems query components and apply logic |
| **Template Method** | `Animation` | `update()` is concrete and calls abstract `updateAnimation()`, defined by each subclass |
| **Strategy** | `TweenAnimation`, `Easings` | `Easing` typedef injected into tweens; any easing function can be swapped at construction |
| **Flyweight** | `SpriteSheet` | Source image is shared; `getSprite(index)` stamps only `sourceRect` on returned `Sprite` |
| **Composite / Scene Graph** | `SceneNode` | Recursive parent-child tree; `update()` and `render()` propagate from root down |
| **Fixed-Timestep Loop** | `GameLoop` | Accumulator pattern decouples game-logic tick rate from Flutter render frame rate |
| **State Machine** | `Engine`, `EngineState` | Enum-driven FSM with guard conditions on every transition method |
| **Facade** | `Engine` | Single entry point that exposes all subsystems through convenient named getters |

---

## 15. Known Gaps & Future Work

| Area | Status | Notes |
|---|---|---|
| **Networking** | Not implemented | Coming in next release |
| **Scene serialization** | Not implemented | Coming in next release |
| **Camera shake** | Not implemented | Coming in next release |
| **Smooth delta time** | Not implemented | Coming in next release |
| **ECS render pipeline** | Fixed in v1.2.1 | `GameWidget._GamePainter.paint()` now calls `engine.world.render(canvas, size)` automatically — no manual wiring needed |
| **Tiled animated tiles** | Caller must drive `TileMapRenderer.update(dt)` | No automatic timer integration into the engine game loop; caller must call `update()` each frame |
| **Tiled image layers** | Parsed, not auto-rendered | `ImageLayer` is part of the data model but `TileMapRenderer` only renders `TileLayer`; caller must handle image layer drawing manually |
| **3D expansion** | Not implemented | Coming in next release |
| **Sub-frame interpolation** | Computed, unused | `GameLoop` computes `interpolationAlpha` but nothing consumes it yet |
| **Controller input** | Partial | `ControllerInput` is implemented but Flutter does not natively support gamepads; requires a plugin bridge |
| **Polygon collision** | Circle only | `PhysicsEngine` supports only circle-circle; arbitrary convex shapes require `CollisionShape` completion |
| **Asset hot-reload** | Not supported | `AssetManager` caches assets indefinitely until `unload()` is called manually |

---

---

## 16. Tiled Map Integration

Tiled map support is provided by the companion package `just_tiled` (with Zstandard decompression via `just_zstd`). Neither package is a dependency of `just_game_engine` itself — they are used alongside it at the application layer.

### 16.1 Integration Architecture

```
 Flutter asset bundle
         │
         ▼
 TileMapParser.parseAsset('assets/maps/level.tmx')
         │  reads XML, resolves TSX external tilesets
         │  decodes tile data: CSV / Base64 / XML
         │  decompresses: GZIP / Zlib / Zstandard (just_zstd)
         ▼
 TileMap  (pure data model)
   ├── List<Layer>       ← TileLayer | ObjectLayer | ImageLayer | GroupLayer
   ├── List<Tileset>     ← firstGid, tileWidth/Height, imagePath, per-tile TileData
   └── Map<String, String> properties
         │
         ├─────────────────────────────────────────────────────────────┐
         │                                                             │
         ▼                                                             ▼
 TextureAtlas.fromTileMap(tileMap)                    ObjectLayer objects
   └── for each Tileset:                              └── SpatialHashGrid<MapObject>
         load image → dart:ui Image                        .insert(obj, obj.bounds)
         pack into atlas image                             .queryAABB(playerBounds)
         record GID → Rect mapping                        .queryRadius(center, r)
         │
         ▼
 TileMapRenderer(tileMap, layer, atlas)
   └── render(Canvas):
         build Float32List rsts (transform per tile)
         build Float32List rects (source rect per tile)
         canvas.drawRawAtlas(atlas.image, rsts, rects, …)
         ← single draw call for entire tile layer
```

### 16.2 Data Model

```
TileMap
 │  width, height              (map dimensions in tiles)
 │  tileWidth, tileHeight      (tile dimensions in pixels)
 │  orientation: MapOrientation (orthogonal | isometric | staggered | hexagonal)
 │  renderOrder: RenderOrder
 │  List<Layer> layers
 │  List<Tileset> tilesets
 │  Map<String, String> properties
 │
 ├── TileLayer
 │     data: List<int>          (flat GID array, width × height)
 │     width, height
 │     Map<String, String> properties
 │
 ├── ObjectLayer
 │     List<MapObject> objects
 │     DrawOrder drawOrder      (topDown | index)
 │
 ├── ImageLayer
 │     imagePath: String
 │     offset: Offset
 │
 └── GroupLayer
       List<Layer> layers       (recursive nesting)

MapObject
   id, name, type
   bounds: Rect                 (position + size in world pixels)
   polygon: List<Offset>?       (polygon vertices, relative to bounds.topLeft)
   polyline: List<Offset>?
   isPoint, isEllipse: bool
   Map<String, String> properties

Tileset
   firstGid: int                (GID offset for this tileset)
   name, tileWidth, tileHeight, spacing, margin, columns
   imagePath: String?
   Map<int, TileData> tiles     (localId → per-tile metadata)

TileData
   localId: int
   List<AnimationFrame> animation
   Map<String, String> properties

AnimationFrame
   tileId: int                  (local tile ID for this frame)
   duration: int                (milliseconds)
```

### 16.3 SpatialHashGrid\<T\>

Generic $O(1)$ spatial hash grid independent of the ECS. Used to index `MapObject` instances from `ObjectLayer` for fast overlap queries during gameplay.

```
SpatialHashGrid<T>
   cellSize: double             ← grid cell size in world units
   Map<String, List<T>> _cells  ← cell key → items list

   insert(item, Rect bounds)    ← registers item in all overlapping cells
   remove(item, Rect bounds)
   update(item, Rect old, Rect new)

   queryAABB(Rect) → List<T>   ← items overlapping rectangle
   queryPoint(Offset) → List<T>
   queryRadius(Offset, double) → List<T>
```

Typical bridge pattern between `SpatialHashGrid` and ECS:
```dart
// Build grid once after map load
final grid = SpatialHashGrid<MapObject>(cellSize: 128);
for (final obj in objectLayer.objects) {
  grid.insert(obj, obj.bounds);
}

// Each ECS update — query and post to InputComponent / custom event
void update(double dt) {
  final transform = entity.getComponent<TransformComponent>()!;
  final nearby = grid.queryRadius(transform.position, 64);
  for (final obj in nearby) {
    if (obj.type == 'damage_zone') {
      entity.getComponent<HealthComponent>()?.damage(dt * 10);
    }
  }
}
```

### 16.4 GPU-Batched Rendering

`TileMapRenderer` achieves minimal draw calls by using `Canvas.drawRawAtlas`:

```
For each visible tile in TileLayer:
  look up GID → source Rect in TextureAtlas
  compute destination RST (Rotation-Scale-Translation) Float32
  append to rsts and rects buffers

canvas.drawRawAtlas(
  atlas.image,          ← single packed texture
  rsts,                 ← Float32List: [cos, -sin, tx, sin, cos, ty] × N
  rects,                ← Float32List: [srcL, srcT, srcR, srcB] × N
  null,                 ← colors (null = no per-tile tint)
  BlendMode.srcOver,
  null,                 ← cullRect (null = draw all)
  Paint(),
)
← one GPU draw call per layer regardless of tile count
```

### 16.5 Animated Tiles

Animated tiles store a `List<AnimationFrame>` in `TileData`. `TileMapRenderer` maintains a per-tile elapsed timer. Each call to `renderer.update(dt)` advances all timers; when a timer exceeds the current frame's `duration`, the renderer advances to the next frame index and resets the timer. The corresponding GID in the internal render buffer is updated accordingly.

The engine game loop does **not** automatically call `renderer.update(dt)` — the caller must wire it:

```dart
engine.rendering.addRenderable(CustomRenderable(
  onRender: (canvas, size) {
    for (final r in renderers) {
      r.update(engine.time.deltaTime);
      r.render(canvas);
    }
  },
));
```

---

*Document generated from source analysis of `packages/just_game_engine` v1.2.1*
