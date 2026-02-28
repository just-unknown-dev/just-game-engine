# Changelog

All notable changes to the Just Game Engine will be documented in this file.

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
  - Sound effect pooling with 10 concurrent players
  - Automatic cleanup of finished audio clips
  - Music fade in/out support (configurable duration)
  - Looping support for music and ambient sounds
  - Built on `audioplayers` package (^6.1.0)
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
  - `audioplayers: ^6.1.0` (for Audio Engine)
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

## [0.0.1] - 2026-02-15

### Added

- Initial project structure
- Package scaffolding
- Basic placeholder classes for all 8 subsystems

---

## Version History

- **1.0.1** - Bug fix for audio asset path and license update to BSD-3-Clause
- **1.0.0** - Full production release with all core features
- **0.0.1** - Initial project setup
