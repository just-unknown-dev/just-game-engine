# Just Game Engine - Architectural and Design Blueprints

> **Version:** 1.0.1  
> **Date:** February 28, 2026  
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
14. [Design Patterns Reference](#14-design-patterns-reference)
15. [Known Gaps & Future Work](#15-known-gaps--future-work)

---

## 1. Overview & Package Metadata

`just_game_engine` is a cross-platform 2D game engine built on top of Flutter. It provides a complete game-development framework including a fixed-timestep game loop, a layer-based rendering pipeline, ECS (Entity-Component-System) architecture, sprite/particle systems, physics, audio mixing, input unification, asset loading, animation, and a scene graph. The engine integrates directly into Flutter's widget tree via `GameWidget`, making it possible to embed game views anywhere in a Flutter application.

| Field | Value |
|---|---|
| **Package name** | `just_game_engine` |
| **Version** | `1.0.1` |
| **Dart SDK** | `^3.11.0` |
| **Flutter** | `>=1.17.0` |
| **Runtime dependency** | `audioplayers: ^6.1.0` |
| **Dev dependencies** | `flutter_test`, `flutter_lints: ^6.0.0` |
| **Repository** | https://github.com/just-unknown-dev/just-game-engine |

### Source Layout

```
packages/just_game_engine/
├── lib/
│   ├── just_game_engine.dart          ← public API barrel export
│   └── src/
│       ├── core/                      ← Engine, GameLoop, TimeManager, SystemManager, Lifecycle
│       ├── rendering/                 ← RenderingEngine, Renderables, Sprite, Camera, GameWidget, Particles
│       ├── physics/                   ← PhysicsEngine, PhysicsBody
│       ├── input/                     ← InputManager, Keyboard/Mouse/Touch/Controller
│       ├── audio/                     ← AudioEngine, AudioClip
│       ├── animation/                 ← AnimationSystem, Tweens, Easings
│       ├── assets/                    ← AssetManager, Asset types
│       ├── ecs/                       ← World, Entity, Component, System, built-ins
│       ├── editor/                    ← SceneEditor, Scene, SceneNode
│       └── networking/                ← NetworkManager (Upcoming)
├── example/
├── test/
└── pubspec.yaml
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
│    Engine (singleton FSM) ─ GameLoop ─ TimeManager ─ SystemManager     │
└───┬──────┬───────┬──────────┬────────┬──────────────┬───────┬──────────┘
    │      │       │          │        │              │       │
┌───▼──┐ ┌─▼────┐ ┌▼──────┐ ┌▼─────┐ ┌▼──────────┐ ┌▼─────┐ ┌▼─────────┐
│Render│ │Physic│ │Input  │ │Audio │ │ Animation │ │Asset │ │ Network  │
│Engine│ │Engine│ │Manager│ │Engine│ │ System    │ │Manag.│ │ Manager  │
└───┬──┘ └──────┘ └───────┘ └──────┘ └───────────┘ └──┬───┘ └──────────┘
    │                                                   │
┌───▼───────────────────────────────────────────────────▼────────────────┐
│                       ECS World Layer                                   │
│  World ─ Entity ─ Component bag ─ System (priority-ordered dispatch)    │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────────────┐
│                     Scene Graph Layer                                   │
│          SceneEditor ─ Scene ─ SceneNode (tree) ─ Renderable attach     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Subsystem Dependency Map

```
Engine
 ├─► GameLoop          uses  TimeManager
 ├─► SystemManager     registrar for all subsystems
 ├─► RenderingEngine   uses  Camera, List<Renderable>, AssetManager (indirect)
 ├─► PhysicsEngine     standalone; mirrored by PhysicsSystem in World
 ├─► InputManager      aggregates Keyboard/Mouse/Touch/Controller
 ├─► AudioEngine       uses  audioplayers package
 ├─► AnimationSystem   uses  Renderable (to mutate properties)
 ├─► AssetManager      uses  Flutter rootBundle / dart:ui codec
 ├─► SceneEditor       uses  SceneNode → Renderable → RenderingEngine
 ├─► World (ECS)       owns  List<Entity>, List<System>
 └─► NetworkManager    (upcoming)
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
   gravity: Offset       (default: Offset(0, 980) — pixels/s²)
   enabled: bool

   update(dt):
     for each body (non-static):
       body.velocity += gravity * dt
       body.velocity *= (1 - body.drag * dt)    ← drag
       body.velocity = clampMagnitude(vel, maxSpeed)
       body.position += body.velocity * dt
     broadPhaseCircleCollision()

   broadPhaseCircleCollision():
     for each pair (A, B):
       if layers don't overlap: skip
       dist = (A.position - B.position).distance
       if dist < A.radius + B.radius:
         resolveCollision(A, B, dist)

   resolveCollision(A, B, dist):
     normal = (B.pos - A.pos) / dist
     overlap = A.radius + B.radius - dist
     // positional correction (weighted by inverse mass)
     totalInvMass = 1/A.mass + 1/B.mass
     A.position -= normal * overlap * (1/A.mass / totalInvMass)
     B.position += normal * overlap * (1/B.mass / totalInvMass)
     // impulse resolution
     relVel = dot(B.velocity - A.velocity, normal)
     if relVel > 0: return       ← already separating
     e = min(A.restitution, B.restitution)
     j = -(1 + e) * relVel / totalInvMass
     A.velocity -= normal * j / A.mass
     B.velocity += normal * j / B.mass
```

**`PhysicsBody` Properties:**

| Property | Type | Description |
|---|---|---|
| `position` | `Offset` | World-space center |
| `velocity` | `Offset` | Pixels per second |
| `mass` | `double` | Kg-equivalent |
| `radius` | `double` | Collision circle radius (pixels) |
| `restitution` | `double` | Bounciness 0–1 |
| `drag` | `double` | Velocity damping coefficient |
| `isStatic` | `bool` | Immovable; still participates in collision |
| `collisionLayers` | `int` | Bitmask; bodies only collide if layers overlap |
| `maxSpeed` | `double` | Velocity magnitude cap |

---

### 7.2 ECS Physics — PhysicsSystem

Mirrors `PhysicsEngine` logic but operates on entities carrying `PhysicsBodyComponent`, `TransformComponent`, and `VelocityComponent`. Reads mass/drag etc. from the component; writes back to `TransformComponent.position` and `VelocityComponent.velocity`.

---

### 7.3 Future Physics Stubs

These classes exist as shells in `physics_engine.dart` for planned expansion:

| Class | Purpose (planned) |
|---|---|
| `RigidBody` | Full rigid-body dynamics with torque/angular momentum; has `x/y/z` fields suggesting 3D |
| `CollisionDetector` | Separate broad-phase / narrow-phase passes (SAT, AABB, etc.) |
| `ForceManager` | Named persistent forces (wind, gravity zones) |
| `CollisionShape` *(abstract)* | Pluggable shapes (box, polygon, capsule, mesh) |

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
   │  Map<AudioChannel, bool>   _channelMuted
   │  List<AudioPlayer> _sfxPool        (10 pre-created players)
   │  AudioPlayer? _musicPlayer
   │  Map<String, AudioClip> _activeClips
   │
   ├── playSfx(path, {volume, loop, channel})
   │     └── acquire free slot from _sfxPool (round-robin)
   │     └── AudioPlayer.play(AssetSource(path))
   │
   ├── playMusic(path, {volume, loop, fadeIn})
   │     └── _musicPlayer ??= AudioPlayer()
   │     └── apply fadeIn tween if specified
   │
   ├── stopMusic({fadeOut})
   ├── pauseMusic() / resumeMusic()
   ├── setChannelVolume(channel, volume)   ← 0.0–1.0
   ├── muteChannel(channel) / unmuteChannel(channel)
   └── getMasterVolume() / setMasterVolume(v)
```

---

### 9.2 AudioClip

Wraps an `audioplayers.AudioPlayer` instance. Returned by `playSfx()` / `playMusic()` for programmatic control.

| Method | Description |
|---|---|
| `play()` | Start / restart playback |
| `pause()` | Pause, retaining position |
| `resume()` | Resume from paused position |
| `stop()` | Stop and reset to beginning |
| `setVolume(double v)` | Local volume [0–1]; multiplied by channel volume |
| `setLoop(bool loop)` | Toggle looping |
| `fadeIn(Duration d)` | Linearly ramp volume from 0 to `volume` over duration |
| `fadeOut(Duration d)` | Linearly ramp volume to 0, then stop |
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
| `.mp3`, `.wav`, `.ogg`, `.flac` | `AudioAsset` | Loaded as `Uint8List`; played via `audioplayers.AssetSource` |
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

## 13. Design Patterns Reference

| Pattern | Implementation Location | Description |
|---|---|---|
| **Singleton** | `Engine` | `Engine._instance` + factory constructor; `Engine.resetInstance()` for test isolation |
| **Service Locator** | `SystemManager` | `getSystem<T>()` and `getSystemByName(String)` for runtime subsystem retrieval |
| **Observer / Callback** | `InputManager`, `Animation` | `onKeyEvent`/`onPointerEvent` listener registration; `Animation.onComplete` callback |
| **Object Pool** | `AudioEngine._sfxPool` | 10 pre-created `AudioPlayer` instances reused for concurrent SFX playback |
| **Entity-Component-System** | `World`, `Entity`, `Component`, `System` | Data-oriented composition: entities are pure IDs; systems query components and apply logic |
| **Template Method** | `Animation` | `update()` is concrete and calls abstract `updateAnimation()`, defined by each subclass |
| **Strategy** | `TweenAnimation`, `Easings` | `Easing` typedef injected into tweens; any easing function can be swapped at construction |
| **Flyweight** | `SpriteSheet` | Source image is shared; `getSprite(index)` stamps only `sourceRect` on returned `Sprite` |
| **Composite / Scene Graph** | `SceneNode` | Recursive parent-child tree; `update()` and `render()` propagate from root down |
| **Fixed-Timestep Loop** | `GameLoop` | Accumulator pattern decouples game-logic tick rate from Flutter render frame rate |
| **State Machine** | `Engine`, `EngineState` | Enum-driven FSM with guard conditions on every transition method |
| **Facade** | `Engine` | Single entry point that exposes all subsystems through convenient named getters |

---

## 14. Known Gaps & Future Work

| Area | Status | Notes |
|---|---|---|
| **Networking** | Not implemented | Coming in next release |
| **Scene serialization** | Not implemented | Coming in next release |
| **Camera shake** | Not implemented | Coming in next release |
| **Smooth delta time** | Not implemented | Coming in next release |
| **ECS render pipeline** | Manual wiring required | `World.render()` is not automatically called by the engine; must be triggered explicitly |
| **3D expansion** | Not implemented | Coming in next release |
| **Sub-frame interpolation** | Computed, unused | `GameLoop` computes `interpolationAlpha` but nothing consumes it yet |
| **Controller input** | Partial | `ControllerInput` is implemented but Flutter does not natively support gamepads; requires a plugin bridge |
| **Polygon collision** | Circle only | `PhysicsEngine` supports only circle-circle; arbitrary convex shapes require `CollisionShape` completion |
| **Asset hot-reload** | Not supported | `AssetManager` caches assets indefinitely until `unload()` is called manually |

---

*Document generated from source analysis of `packages/just_game_engine` v1.0.1*
