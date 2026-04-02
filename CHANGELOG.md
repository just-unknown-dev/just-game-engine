# Changelog

All notable changes to the Just Game Engine will be documented in this file.

## [1.4.1] - 2026-04-02

- Engine performance improved
- Engine stats updated

## [1.4.1] - 2026-03-25

### Changed - Documentation & Examples

- **README**: Overhauled and streamlined — removed outdated sections and links to provide a cleaner, more up-to-date overview.
- **Example**: Consolidated the example suite into a single `example.dart` file covering the core engine setup. Removed the separate `core_system_example.dart`, `ecs_example.dart`, and `input_test_example.dart` files to reduce onboarding friction.

---

## [1.4.0] - 2026-03-21

### Changed - Architecture & Performance

- Major change in architecture and imporved performance

### Added - Parallax Background System

New first-class subsystem for multi-layer scrolling backgrounds, accessible via `Engine.parallax`.

- **ParallaxLayer** — Individual layer with depth-based scrolling.
  - `scrollFactorX` / `scrollFactorY` control camera-relative scroll speed (0.0 = fixed, 1.0 = camera speed).
  - `velocityX` / `velocityY` for continuous auto-scroll independent of camera movement.
  - `scale`, `repeat`, `offset`, `opacity`, and `tint` for full visual control.
  - `ParallaxLayer.uniform()` convenience constructor for equal X/Y scroll factors.
- **ParallaxBackground** — Ordered container of `ParallaxLayer` instances (index 0 = furthest back).
  - `addLayer()`, `insertLayer()`, `removeLayer()` for runtime layer management.
  - `update(deltaTime)` advances auto-scroll offsets; `render(canvas, size)` paints all layers back-to-front.
  - Per-layer camera-driven + auto-scroll + static offset compositing.
  - Tiling logic handles images smaller than the viewport with seamless horizontal/vertical wrapping.
- **ParallaxSystem** — Engine subsystem managing all registered backgrounds.
  - `addBackground()` / `removeBackground()` / `clear()` lifecycle methods.
  - `update(deltaTime, cameraPosition)` feeds camera position into every background each frame.
  - `render(canvas, size)` called via `RenderingEngine.onRenderBackground` in screen space (before camera transform).

### Added - Virtual Joystick Widget

Reusable Flutter widget for touch-based directional input on mobile platforms.

- **VirtualJoystick** — `StatefulWidget` that handles pointer events and emits normalised direction vectors.
  - `JoystickVariant.fixed` — always-visible joystick anchored at a set position.
  - `JoystickVariant.floating` — appears at the touch-down point and follows the finger.
  - `JoystickAxis` constraint: `both`, `horizontal`, or `vertical` axis locking.
  - Configurable `radius`, `showWhenInactive`, `inactiveOpacity`, and `anchorAlignment`.
  - `onDirectionChanged` callback delivers a normalised `Offset` each frame for ECS integration.
  - Rendered via `CustomPaint` with base ring and thumb knob visuals.
- **JoystickInputComponent** — ECS component storing joystick state on an entity.
  - `direction`, `basePosition`, `thumbPosition` for runtime access.
  - `layout` (fixed / floating) and `axis` constraint properties.
  - `hasInput`, `reset()`, `setDirectionFromDelta()` helpers.
  - Automatically processed by `InputSystem._updateJoystickComponents()` alongside keyboard input.

---

## [1.3.0] - 2026-03-15

### Added - Tiled Map ECS Integration

`just_tiled` is now a first-class runtime dependency of `just_game_engine`. The engine ships four new types that bridge parsed Tiled map data directly into the ECS world, covering rendering, collision, and object-to-entity spawning.

- **TileMapLayerComponent** — ECS component that attaches a `TileLayer` and its pre-compiled `TileMapRenderer` to a single entity. One entity per tile layer keeps the world free of per-tile entity bloat.
- **TiledObjectComponent** — ECS component for Tiled map objects. Exposes `properties`, `type`, and `name` directly on the entity for easy custom-logic dispatch.
- **TiledMapFactory** — Static factory that translates an entire `TiledMap` into ECS entities in one call.
  - Tile layers → one entity with `TileMapLayerComponent` + `TransformComponent` (respects layer offset).
  - Object groups → one entity per visible `TiledObject` with `TransformComponent` + `TiledObjectComponent`.
  - `GroupLayer` children are traversed recursively.
  - `ComponentMapper` callback maps any Tiled class name + custom properties to additional engine components (e.g. `HealthComponent`, `EnemyAIComponent`).
- **TileMapRenderSystem** — ECS `System` that GPU-batches all `TileMapLayerComponent` entities. Uses `Camera.getVisibleBounds()` for viewport frustum culling so only in-view tiles are processed. Runs at priority `100` so tile layers are painted before game entities.
- **TiledCollisionSystem** — ECS `System` that converts TMX object-group collision shapes into static `PhysicsBody` instances and registers them with `PhysicsEngine`.
  - Supports **rectangle**, **polygon**, and **ellipse** shapes (mapped to `RectangleShape`, `PolygonShape`, `CircleShape`).
  - Per-object `restitution` and `friction` read from Tiled custom properties.
  - Optional `SpatialHashGrid<PhysicsBody>` for O(1) proximity queries.
  - `loadCollisions(TiledMap)` / `loadObjectGroupCollisions(ObjectGroup)` / `clearCollisions()` lifecycle methods.
---

## [1.2.1] - 2026-03-15

### Changed
- **GameWidget**: `_GamePainter.paint()` now also calls `engine.world.render(canvas, size)`, so ECS entities registered with `RenderSystem` are drawn automatically alongside the classic 
rendering pipeline.

### Added - Audio ECS Integration

Audio playback is now fully ECS-driven alongside the existing `AudioEngine` API.

- **AudioSourceComponent** — Persistent audio source on an entity. Properties: `clipPath`, `volume`, `pan`, `loop`, `playOnAdd`, `channel` (`AudioChannel`), `is3d`. When `is3d` is `true`, stereo pan is ignored and 3D position is derived from `TransformComponent`.
- **AudioPlayComponent** — Fire-and-forget one-shot playback trigger. `AudioSystem` plays the sound and removes the component automatically.
- **AudioListenerComponent** — Marks an entity (typically the camera or player) as the SoLoud 3D listener. `AudioSystem` forwards the entity's `TransformComponent` position to the native listener each frame.
- **AudioSystem** — ECS `System` that drives all audio ECS components. Runs at priority `-10` (after transforms) to ensure 3D positions are up to date before the listener and source positions are sent to SoLoud.

### Fixed
- **Example**: Simplified `example/example.dart` to a minimal renderer setup for easier onboarding.

---

## [1.2.0] - 2026-03-12

### Added - Ray Casting & Ray Tracing
- **Ray** — 2-D ray descriptor with origin, normalised direction, and maximum travel distance.
  - `Ray.fromPoints()` convenience constructor for aiming between two world positions.
  - `at(t)` helper returns the world-space point at a given distance along the ray.
- **RaycastColliderComponent** — ECS component that marks an entity as hittable by rays.
  - Configurable `radius`, semantic `tag` for filtering, `isBlocker` flag, and `isReflective` / `reflectivity` properties for multi-bounce tracing.
- **RaycastHit** — intersection result containing the hit entity, world-space point, distance, and outward surface normal.
- **RaycastSystem** — query-only ECS system for ray-vs-collider tests.
  - `castRay()` returns the closest hit; `castRayAll()` returns all hits sorted nearest-first.
  - `hasLineOfSight()` performs a line-of-sight / LOS check between two points.
- **RayTracer** — multi-bounce ray tracing against reflective surfaces.
  - Configurable `maxBounces` and `minReflectivity` thresholds.
  - `trace()` returns a `RayTrace` containing every `RayTraceSegment` (path segment + optional hit).

### Added - Ray Renderable
- **RayRenderable** — a `Renderable` that draws a glowing beam / laser / bullet trail in world space.
  - Two-layer visual: a sharp core line and a wider blurred glow halo for a neon/laser effect.
  - Automatic fade-out over a configurable `lifetime`; `isExpired` flag for easy cleanup.
  - Customisable `color`, `width`, `glowWidthMultiplier`, and `glowBlurSigma`.

---

## [1.1.2] - 2026-03-08

### Changed
- **Audio Engine**: Replaced `audioplayers` with `flutter_soloud` (^3.5.0) as the audio backend.
  - SoLoud is a low-latency, C++-based audio engine purpose-built for games.
  - Removed the fixed-size `AudioPlayer` pool; SoLoud handles unlimited concurrent voices natively.
  - `AudioClip` now holds an `AudioSource` + `SoundHandle` instead of an `AudioPlayer`.
  - `AudioEngine.initialize()` is now `async` and calls `SoLoud.instance.init()`; the engine
    properly `await`s it during startup so audio is guaranteed ready before any play calls.
  - Added `isInitialized` guard in `initialize()` to be safe against duplicate init (e.g. hot restart).
  - `playSfx()` and `playMusic()` return early with a debug message if called before initialization.
  - Music fade-in/fade-out now delegates to `SoLoud.instance.fadeVolume()` instead of a manual step loop.
  - `dispose()` calls `SoLoud.instance.deinit()` to fully shut down the engine.

## [1.1.1] - 2026-03-07

- Homepage URL updated in `pubspec.yaml`.
- Added reactive ECS components and signals for improved state management.

## [1.1.0] - 2026-03-01

### Added - Advanced Physics Engine

- **Rigid Body Dynamics**
  - Upgraded physics integration to Semi-Implicit Euler.
  - Added new dynamic properties to `PhysicsBody`: `angularVelocity`, `angle`, `torque`, `inertia`, and `friction`.
  - Added support for static bodies by setting `mass: 0.0`.
- **Advanced Collision Shapes**
  - Implemented `CollisionShape` hierarchy replacing simple `radius`.
  - Added `CircleShape`, `RectangleShape`, and `PolygonShape`.
  - Implemented Separating Axis Theorem (SAT) for true polygon-polygon and circle-polygon collision detection.
- **Impulse-Based Resolution**
  - Added rigorous impulse delivery resolving velocity along collision normals using inverse mass scaling.
  - Included Coulomb friction handling for sliding objects.
- **Broad-Phase Optimization**
  - Implemented $O(n)$ `SpatialGrid` broad-phase for massive performance gains in dense scenes.
  - Added Object Sleeping: resting bodies are excluded from integration until awoken, saving CPU cycles.
- **Physics Caching**
  - Integrated `CacheManager` utilizing `just_storage` and `just_database`.
  - Added `cachePolygonShape` and `getCachedPolygonShape` routines to persist heavy math computations across sessions.

---

## [1.0.1] - 2026-02-24
### Fixed

- **Audio Engine**
  - Fixed `AudioClip.play()` crash caused by `AudioCache` double-prefixing the asset path (`assets/assets/...`) when the caller passed a path already starting with `assets/`. The path is now stripped of the `assets/` prefix before being passed to `AssetSource`.

### Changed

- **License**
  - Changed project license from Apache 2.0 to BSD-3-Clause.

---

## [1.0.0] - 2026-02-16

### Added - Core Systems

- **Engine Core**
  - Main `Engine` singleton class for orchestrating all subsystems
  - `GameLoop` with fixed timestep (60 UPS) and variable rendering
  - `TimeManager` for delta time tracking and FPS calculation
  - `SystemManager` for coordinating subsystems
  - Full lifecycle management (initialize, start, pause, resume, stop, dispose)
  - Engine state machine with 6 states (uninitialized, initializing, initialized, running, paused, error)

- **Rendering Engine**
  - Canvas-based 2D rendering system
  - `Camera` class with pan, zoom, rotation, and lookAt functionality
  - Layer-based rendering with Z-order sorting
  - Built-in renderables: `CircleRenderable`, `RectangleRenderable`, `LineRenderable`, `TextRenderable`, `CustomRenderable`
  - `GameWidget` for Flutter integration with CustomPainter
  - Debug mode with bounding boxes and coordinate grids
  - Background color support
  - FPS display overlay

### Added - Advanced Features

- **Sprite System**
  - `Sprite` class for image rendering with source rectangles
  - `SpriteSheet` for managing sprite atlases
  - `NineSliceSprite` for scalable UI elements
  - Horizontal and vertical flipping support
  - Static `fromAsset` method for easy loading

- **Animation System**
  - Base `Animation` class with play, pause, stop, reset controls
  - `SpriteAnimation` for frame-based sprite animations:
    - Automatic frame cycling based on normalized time
    - `fromSpriteSheet()` factory method for easy creation
    - Support for variable frame counts (any number of frames)
    - Configurable frame dimensions (width/height)
    - Manual frame list support via `List<Rect>` frames parameter
  - Generic `TweenAnimation<T>` with custom lerp functions
  - Property tweens: `PositionTween`, `RotationTween`, `ScaleTween`, `OpacityTween`, `ColorTween`
  - `AnimationSequence` for chaining animations
  - `AnimationGroup` for parallel animations
  - `Easings` class with 15+ easing functions:
    - Linear
    - Quadratic (in, out, in-out)
    - Cubic (in, out, in-out)
    - Quartic (in, out, in-out)
    - Sine (in, out, in-out)
    - Exponential (in, out, in-out)
    - Elastic (in, out, in-out)
    - Bounce (in, out, in-out)
  - Loop and ping-pong support
  - Speed control (0.1x - 5.0x) with dynamic adjustment
  - Normalized time (0.0 - 1.0) for progress tracking
  - Completion callbacks

- **Particle Effects**
  - `ParticleEmitter` with configurable emission rate and lifetime
  - Individual `Particle` class with full lifecycle
  - Size gradient support (start → end)
  - Color gradient support with smooth transitions
  - Gravity and velocity simulation
  - Multiple particle shapes: circle, square, star
  - Built-in effect presets:
    - Explosion (burst of orange/yellow particles)
    - Fire (rising orange flames with flicker)
    - Smoke (upward gray particles with fade)
    - Sparkle (twinkling yellow/white particles)
    - Rain (falling blue droplets)
    - Snow (gentle falling white flakes)
  - Custom particle system creation

- **Physics Engine**
  - `PhysicsBody` rigid body class
  - Circular collision detection
  - Elastic collision resolution with restitution
  - Mass, velocity, drag, and radius properties
  - Gravity simulation (configurable)
  - Debug rendering with:
    - Body visualization (green = active, red = inactive)
    - Velocity vector arrows
    - Collision boundary circles
  - Broad-phase and narrow-phase collision optimization

- **Scene Graph**
  - Hierarchical `SceneNode` structure
  - Parent-child transform relationships
  - Local and world-space coordinate systems
  - Transform propagation (position, rotation, scale)
  - `SceneEditor` for scene management
  - `Scene` container class
  - Node finding by name (recursive search)
  - Active/inactive state per node
  - Depth calculation
  - Custom update callbacks per node
  - Renderable attachment to nodes

- **Entity-Component System (ECS)**
  - `World` class for managing all entities and systems
  - `Entity` class representing game objects with components
  - `Component` base class for pure data containers
  - `System` base class for processing logic
  - Entity lifecycle management (create, destroy, query)
  - Component filtering and queries
  - System priority and ordering
  - Entity statistics and debugging
  - 13 built-in components:
    - `TransformComponent` - Position, rotation, scale with transform methods
    - `VelocityComponent` - Velocity vector with max speed and angle utilities
    - `RenderableComponent` - Links to renderable objects with sync options
    - `PhysicsBodyComponent` - Radius, mass, restitution, drag, collision layers
    - `TagComponent` - Simple string tagging for entity identification
    - `LifetimeComponent` - Time-based entity expiration
    - `HealthComponent` - HP system with damage, heal, and invulnerability
    - `ParentComponent` - Parent reference with local offset and rotation
    - `ChildrenComponent` - Child entity list management
    - `InputComponent` - Movement direction and button state
    - `AnimationStateComponent` - Current animation state tracking
    - `SpriteComponent` - Sprite path, frame, flip flags, and tint color
  - 9 built-in systems:
    - `MovementSystem` - Applies velocity to transform with max speed clamping
    - `RenderSystem` - Renders entities with transform sync
    - `LifetimeSystem` - Updates lifetime and destroys expired entities
    - `PhysicsSystem` - Full physics with gravity, drag, collision detection/resolution, layer-based filtering
    - `HierarchySystem` - Propagates parent transforms to children
    - `HealthSystem` - Health regeneration and death handling
    - `AnimationSystemECS` - Animation time updates
    - `BoundarySystem` - World boundary enforcement with 4 behaviors (clamp, bounce, wrap, destroy)
  - Data-oriented architecture for performance
  - Composition over inheritance design
  - Query system for finding entities by components
  - Example implementation in `ecs_example.dart`

### Added - Supporting Systems

- **Input Management**
  - `InputManager` main coordinator with subsystem access
  - `KeyboardInput` with key press/hold/release detection
  - Key state tracking with previous frame comparison
  - Horizontal and vertical axis support for WASD/Arrow keys
  - `MouseInput` with position, button, and scroll tracking
  - Mouse delta and scroll delta calculation
  - Support for left, right, and middle mouse buttons
  - Screen-to-world coordinate conversion support
  - `TouchInput` with multi-touch support
  - Touch point tracking with pressure and size
  - Touch start/end events per frame
  - `ControllerInput` with gamepad support
  - Analog stick support (left/right sticks)
  - Trigger and button detection
  - Configurable dead zone for analog inputs
  - Event callback system for custom input handling
  - Automatic integration with `GameWidget` via Focus and Listener
  - Input state updates each frame in game loop

- **Audio Engine**
  - `AudioEngine` main coordinator with multi-channel mixing
  - `AudioClip` wrapper for individual audio playback control
  - `SoundEffectManager` for managing sound effects
  - `MusicManager` for background music with fade effects
  - `AudioMixer` for volume and mute control
  - 5 audio channels: Master, Music, SFX, Voice, Ambient
  - Per-channel volume control with independent mute/unmute
  - Unlimited concurrent SFX via SoLoud's native voice management
  - Automatic cleanup of finished audio clips
  - Music fade in/out support (configurable duration)
  - Looping support for music and ambient sounds
  - Built on `audioplayers` package (^6.1.0) *(replaced by flutter_soloud in v1.1.2)*
  - Supports MP3, WAV, OGG, FLAC audio formats
  - State tracking (stopped, playing, paused)
  - Integration methods: `playSfx()`, `playMusic()`, `stopMusic()`, `setMasterVolume()`

- **Asset Management**
  - `AssetManager` for loading and caching game resources
  - `Asset` base class with load/unload lifecycle
  - `ImageAsset` for loading PNG/JPG images with `ui.Image`
  - `AudioAsset` for loading audio files as binary data
  - `TextAsset` for loading plain text files
  - `JsonAsset` for loading and parsing JSON configuration
  - `BinaryAsset` for loading raw binary data
  - `AssetBundle` for grouping related assets
  - Automatic caching system to prevent duplicate loads
  - Memory usage tracking per asset (in bytes)
  - Cache statistics: total assets, images, audio, text, JSON, binary counts
  - Total memory usage calculation
  - Async loading with futures
  - Integration with Flutter's rootBundle
  - Support for atlas/sprite sheet metadata
  - Unload functionality to free memory
  - Type-safe asset retrieval methods

- **Networking** (Placeholder)
  - Structure for multiplayer support
  - Client-server communication

### Examples

- `core_system_example.dart` - Complete engine setup example
- `ecs_example.dart` - Entity-Component System with physics and collisions
- `input_test_example.dart` - Comprehensive input system demo with keyboard, mouse, and touch

### Technical Details

- Minimum Flutter SDK: 3.11.0
- Minimum Dart SDK: 3.0.0
- External dependencies:
  - `audioplayers: ^6.1.0` (for Audio Engine) *(replaced by flutter_soloud in v1.1.2)*
- Singleton pattern for Engine
- Observer pattern for lifecycle events
- Component-based architecture
- Fixed timestep game loop (60 UPS)
- Variable rendering for smooth visuals
- Efficient collision detection with spatial awareness

### Performance

- Maintains 60 FPS with 20+ objects
- Handles 100+ particles simultaneously
- Real-time collision detection for multiple bodies
- Optimized rendering pipeline
- Low memory footprint

---

## Version History

- **1.4.2** - Performance improvements
- **1.4.1** - Documentation overhaul and example consolidation
- **1.4.0** - Parallax Background System, Virtual Joystick Widget, and showcase app improvements
- **1.3.0** - Tiled Map ECS integration (TiledMapFactory, TileMapRenderSystem, TiledCollisionSystem) and Audio ECS integration (AudioSourceComponent, AudioSystem)
- **1.2.1** - GameWidget ECS rendering integration and example cleanup
- **1.2.0** - Ray Casting, Ray Tracing, and Ray Renderable systems
- **1.1.0** - Complete Physics Engine overhaul (Rigid Body Dynamics, SAT Shapes, Spatial Grid, and Impulse Resolution)
- **1.0.1** - Bug fix for audio asset path and license update to BSD-3-Clause
- **1.0.0** - Full production release with all core features
