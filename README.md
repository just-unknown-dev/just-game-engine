# Just Game Engine

A comprehensive 2D game engine built for Flutter, providing everything you need to create high-performance games with rich visual effects, animations, and physics.

## 📚 Documentation

- **[Quick Start Guide](QUICKSTART.md)** - Get started in 5 minutes
- **[API Reference](API.md)** - Detailed API documentation for all classes
- **[Changelog](CHANGELOG.md)** - Version history and release notes

## Features

Just Game Engine is a complete game development framework with 11 major subsystems:

### 🎮 Core Engine
- **Game Loop**: Fixed timestep (60 UPS) with variable rendering for consistent gameplay
- **State Management**: Full lifecycle management (initialize, start, pause, resume, stop)
- **Time Management**: Delta time, time scaling, FPS tracking
- **System Coordination**: Centralized management of all subsystems

### 🎨 Rendering Engine
- **2D Canvas-Based Rendering**: High-performance drawing with Flutter's Canvas API
- **Renderable Objects**: Circles, rectangles, lines, text, and custom renderables
- **Camera System**: Pan, zoom, and rotation with smooth transforms
- **Layer Management**: Z-order sorting for proper depth rendering
- **Debug Visualization**: Bounding boxes, coordinate grids, and performance metrics

### 🖼️ Sprite System
- **Image Rendering**: Load and display images with easy asset management
- **Sprite Sheets**: Efficiently manage multiple sprites in a single texture
- **Nine-Slice Scaling**: Scalable UI elements that maintain corner details
- **Flipping**: Horizontal and vertical sprite flipping

### ✨ Animation System
- **Sprite Animations**: Frame-based animations from sprite sheets with customizable frame rates
  - `SpriteAnimation` class for sprite sheet playback
  - `fromSpriteSheet()` factory for easy sprite animation creation
  - Independent frame count and duration per animation
  - Automatic frame calculation from sprite dimensions
- **Property Tweening**: Animate position, rotation, scale, opacity, and color
- **Easing Functions**: 15+ built-in easing curves (linear, quad, cubic, elastic, bounce, etc.)
- **Animation Sequences**: Chain animations to play one after another
- **Animation Groups**: Run multiple animations in parallel
- **Loop and Ping-Pong**: Repeat animations infinitely or bounce back and forth
- **Speed Control**: Adjust animation playback speed dynamically (0.1x - 5.0x)

### 💥 Particle Effects
- **Particle Emitters**: Configurable emission rate, lifetime, and spawning
- **Visual Properties**: Size gradients, color gradients, velocity, and gravity
- **Particle Shapes**: Circles, squares, and stars
- **Built-in Presets**: Explosion, fire, smoke, sparkle, rain, and snow effects
- **Custom Particles**: Create your own particle systems

### ⚛️ Physics Engine
- **Rigid Body Dynamics**: Semi-implicit Euler integration for reliable mass, drag, torque, and inertia simulation
- **Advanced Collision Shapes**: Circles, Rectangles, and arbitrary complex Polygons via SAT calculation
- **True Impulse Resolution**: Elastic collisions resolving linear constraints and Coulomb surface friction
- **Broad-Phase Optimization**: Performant $O(n)$ Spatial Grid queries with Object Sleeping features
- **Physics Caching**: Triangulation and expensive geometry processing can be reliably disk-cached

### 🌳 Scene Graph
- **Hierarchical Structure**: Parent-child node relationships
- **Transform Propagation**: Automatic world-space transform calculation
- **Scene Management**: Create, load, and manage multiple scenes
- **Node Queries**: Find nodes by name or traverse the tree
- **Attachable Renderables**: Link visual objects to scene nodes

### 🧩 Entity-Component System (ECS)
- **Data-Oriented Architecture**: Composition over inheritance for flexible entity design
- **Entity Management**: Create and destroy entities with unique IDs
- **Component System**: 13 built-in components (Transform, Velocity, Physics, Health, etc.)
- **System Processing**: 9 built-in systems for movement, rendering, physics, and more
- **Query System**: Find entities by component types
- **World Management**: Centralized entity and system coordination
- **Hierarchy Support**: Parent-child entity relationships

### � Input Management
- **Keyboard Input**: Key press, hold, and release detection with axis support
- **Mouse Input**: Position tracking, button states, scroll wheel, and delta movement
- **Touch Input**: Multi-touch support with pressure and size tracking
- **Controller/Gamepad**: Analog sticks, triggers, buttons, and D-pad support
- **Event System**: Callbacks for custom input handling
- **Dead Zone**: Configurable dead zones for analog inputs
- **Integrated**: Automatic event capture through GameWidget with Focus and Listener

### 🎵 Additional Systems
- **Audio Engine**: Complete audio playback system with multi-channel mixing
  - **Multi-Channel**: Master, Music, SFX, Voice, and Ambient channels with independent volume control
  - **Sound Effects**: Player pooling (10 concurrent SFX) with automatic cleanup
  - **Music**: Background music with fade in/out effects and seamless looping
  - **Audio Mixer**: Per-channel volume control, mute/unmute, and master volume
  - **Integration**: Built on audioplayers package for cross-platform support

- **Asset Management**: Efficient loading and caching of game resources
  - **Image Assets**: Load PNG/JPG images with memory tracking
  - **Audio Assets**: Load MP3/WAV/OGG/FLAC audio files as binary data
  - **Text Assets**: Load plain text files from asset bundle
  - **JSON Assets**: Load and parse JSON configuration files
  - **Binary Assets**: Load raw binary data for custom formats
  - **Caching**: Automatic asset caching with memory usage statistics
  - **Asset Bundles**: Group multiple assets for batch loading/unloading

- **Networking**: Multiplayer and server communication (Not Implemented Yet)

## Just Game Engine vs. Flame Engine

While [Flame](https://flame-engine.org/) is the most popular 2D game engine for Flutter, Just Game Engine takes a different architectural approach tailored for developers who want more explicit control over their game loop, physics, and state. 

| Feature | Just Game Engine | Flame Engine |
| :--- | :--- | :--- |
| **Architecture** | Pure Entity-Component-System (ECS) combined with a flexible Scene Graph. | Component-based system (FCS), heavily relying on OOP inheritance. |
| **Game Loop** | True Fixed-Timestep update loop preventing physics "spiral of death". | Variable delta-time loop natively. |
| **Physics** | Custom-built, lightweight impulse-based 2D physics with SAT. | Wraps the mature (but heavier) Box2D / Forge2D engine. |
| **Performance** | Highly optimized for 2D with $O(n)$ Spatial Grid physics broadcast, zero-allocation game loops, and direct `dart:ui` Canvas draws. Predictable execution due to fixed-timestep. | Solid general performance, but heavy component trees or Forge2D physics can introduce overhead and GC pressure. Natively relies on variable delta-time. |
| **Input Handling** | Unified polling system (`input.keyboard.isKeyDown()`) handled in the update loop. | Event-driven callbacks via Mixins (`KeyboardEvents`, etc.). |
| **Dependencies** | Extremely lightweight; relies primarily on raw `dart:ui` Canvas operations. | Modular but large ecosystem pulling in numerous external dependencies. |
| **Learning Curve** | Explicit, linear data flows. Excellent for fully understanding engine internals. | Massive community, but highly opinionated and sometimes "magical". |

## Getting Started

### Prerequisites

- Flutter SDK 3.11.0 or higher
- Dart 3.0.0 or higher

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  just_game_engine:
    path: ../packages/just_game_engine  # Adjust path as needed
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Setup

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the engine
  final engine = Engine();
  await engine.initialize();

  // Set up your game
  setupGame(engine);

  // Start the engine
  engine.start();

  // Run your Flutter app
  runApp(MyGameApp(engine: engine));
}

void setupGame(Engine engine) {
  // Add renderables
  engine.rendering.addRenderable(
    CircleRenderable(
      radius: 50,
      fillColor: Colors.blue,
      position: Offset.zero,
    ),
  );
}
```

### Creating Animations

```dart
// Sprite animation from sprite sheet
final sprite = Sprite();
sprite.image = spriteSheetImage;
sprite.renderSize = const Size(64, 64);
sprite.position = const Offset(0, 0);

final spriteAnim = SpriteAnimation.fromSpriteSheet(
  sprite: sprite,
  frameCount: 8,        // 8 frames
  frameWidth: 64,       // Each frame 64px wide
  frameHeight: 64,      // Each frame 64px tall
  duration: 1.0,        // Total duration: 1 second
  loop: true,
);
engine.animation.addAnimation(spriteAnim);
spriteAnim.play();

// Position tween
final moveAnim = PositionTween(
  target: myRenderable,
  start: Offset(-100, 0),
  end: Offset(100, 0),
  duration: 2.0,
  easing: Easings.easeInOutQuad,
  loop: true,
);
moveAnim.play();

// Rotation animation
final rotateAnim = RotationTween(
  target: myRenderable,
  start: 0,
  end: math.pi * 2,
  duration: 3.0,
  easing: Easings.linear,
  loop: true,
);
rotateAnim.play();

// Animation sequence
final sequence = AnimationSequence(
  animations: [animation1, animation2, animation3],
  loop: true,
);
sequence.play();

// Control animation speed
moveAnim.speed = 2.0;  // 2x speed
spriteAnim.speed = 0.5; // Half speed
```

### Adding Particle Effects

```dart
// Create a fire effect
final fireEmitter = ParticleEffects.fire(
  position: Offset(100, 200),
)..emissionRate = 30;

particles.add(fireEmitter);

// Create an explosion
final explosion = ParticleEffects.explosion(
  position: Offset(0, 0),
);
particles.add(explosion);

// Render particles
rendering.addRenderable(
  CustomRenderable(
    onRender: (canvas, size) {
      for (final emitter in particles) {
        emitter.update(deltaTime);
        emitter.render(canvas, size);
      }
    },
  ),
);
```

### Using the Scene Graph

```dart
// Create a scene
final scene = engine.sceneEditor.createScene('Level1');

// Create parent node
final parentNode = SceneNode('parent')
  ..localPosition = Offset(100, 100);
scene.addNode(parentNode);

// Create child node
final childNode = SceneNode('child')
  ..localPosition = Offset(50, 0)
  ..renderable = myCircle;
parentNode.addChild(childNode);

// Child automatically inherits parent's transform
```

### Using the Entity-Component System

```dart
// Access the ECS World
final world = engine.world;

// Add systems
world.addSystem(MovementSystem());
world.addSystem(RenderSystem());
world.addSystem(PhysicsSystem()..gravity = const Offset(0, 100));

// Create an entity
final player = world.createEntity(name: 'Player');

// Add components
player.addComponent(TransformComponent(
  position: const Offset(0, 0),
));
player.addComponent(VelocityComponent(
  velocity: const Offset(100, 0),
  maxSpeed: 200,
));
player.addComponent(RenderableComponent(
  renderable: CircleRenderable(
    radius: 30,
    fillColor: Colors.blue,
  ),
));
player.addComponent(PhysicsBodyComponent(
  radius: 30,
  mass: 1.0,
  restitution: 0.8,
));
player.addComponent(HealthComponent(maxHealth: 100));

// Query entities by components
final movingEntities = world.query([TransformComponent, VelocityComponent]);
for (final entity in movingEntities) {
  print('Entity ${entity.name} can move!');
}

// Find specific entity
final enemy = world.findEntityByName('Enemy');
if (enemy != null) {
  enemy.getComponent<HealthComponent>()?.damage(10);
}
```

### Physics Simulation

```dart
// Create physics bodies
final body1 = PhysicsBody(
  position: Offset(-100, 0),
  velocity: Offset(50, 0),
  shape: CircleShape(30),
  mass: 1.0,
  restitution: 0.8,
  friction: 0.2,
);

engine.physics.addBody(body1);

// Enable debug rendering
rendering.addRenderable(
  CustomRenderable(
    onRender: (canvas, size) {
      engine.physics.renderDebug(canvas, size);
    },
  ),
);
```

### Camera Controls

```dart
// Move camera
engine.rendering.camera.moveBy(Offset(10, 0));

// Zoom
engine.rendering.camera.zoomBy(1.1);

// Reset camera
engine.rendering.camera.reset();

// Look at position
engine.rendering.camera.lookAt(Offset(100, 100));
```

### Using Input System

```dart
final input = engine.input;

// Keyboard input
if (input.keyboard.isKeyDown(LogicalKeyboardKey.keyW)) {
  // W key is currently held down
  player.moveUp();
}

if (input.keyboard.isKeyPressed(LogicalKeyboardKey.space)) {
  // Space was just pressed this frame
  player.jump();
}

// Get axis input for smooth movement
final horizontal = input.keyboard.horizontal; // -1, 0, or 1
final vertical = input.keyboard.vertical;     // -1, 0, or 1
player.move(Offset(horizontal, vertical) * speed);

// Mouse input
final mousePos = input.mouse.position;
final worldPos = engine.rendering.camera.screenToWorld(mousePos, screenSize);

if (input.mouse.isLeftButtonDown) {
  // Left mouse button is held
  player.shootAt(worldPos);
}

if (input.mouse.isButtonPressed(MouseButton.right)) {
  // Right mouse button was just clicked
  spawnObject(worldPos);
}

// Mouse wheel zoom
if (input.mouse.scrollDelta.dy != 0) {
  engine.rendering.camera.zoomBy(1.0 - input.mouse.scrollDelta.dy * 0.001);
}

// Touch input
for (final touch in input.touch.touches) {
  // Handle each active touch point
  print('Touch at ${touch.position}');
}

// Gamepad input
final leftStick = input.controller.leftStick;
player.move(leftStick * speed);

if (input.controller.isButtonPressed(GamepadButton.a)) {
  player.jump();
}
```

### Loading Assets

```dart
// Create asset manager
final assetManager = AssetManager();

// Load different asset types
final playerImage = await assetManager.loadImage('assets/images/player.png');
final backgroundMusic = await assetManager.loadAudio('assets/audio/music.mp3');
final gameConfig = await assetManager.loadJson('assets/data/config.json');
final levelData = await assetManager.loadText('assets/data/level1.txt');

// Access loaded data
final sprite = Sprite();
sprite.image = playerImage.image;

final configMap = gameConfig.data as Map<String, dynamic>;
final playerSpeed = configMap['player']['speed'];

// Check cache stats
final stats = assetManager.getCacheStats();
print('Loaded ${stats['totalAssets']} assets');
print('Memory usage: ${stats['totalMemory']} bytes');

// Load asset bundles
final levelBundle = AssetBundle(
  name: 'Level1',
  assets: [
    ImageAsset(path: 'assets/level1/bg.png'),
    AudioAsset(path: 'assets/level1/music.mp3'),
    JsonAsset(path: 'assets/level1/data.json'),
  ],
);
await levelBundle.load(assetManager);

// Unload when done
levelBundle.unload(assetManager);
```

### Playing Audio

```dart
// Initialize audio engine
final audioEngine = AudioEngine();
await audioEngine.initialize();

// Play background music with fade in
await audioEngine.playMusic(
  'assets/audio/background.mp3',
  volume: 0.7,
  loop: true,
  fadeInDuration: 2.0,
);

// Play sound effects
audioEngine.playSfx('assets/audio/jump.wav', volume: 0.8);
audioEngine.playSfx('assets/audio/shoot.wav');
audioEngine.playSfx('assets/audio/explosion.wav', volume: 1.0);

// Control volume
audioEngine.setMasterVolume(0.8);
audioEngine.setChannelVolume(AudioChannel.music, 0.5);
audioEngine.setChannelVolume(AudioChannel.sfx, 1.0);

// Mute/unmute
audioEngine.muteChannel(AudioChannel.music);
audioEngine.toggleMute();  // Toggle master mute

// Stop music with fade out
audioEngine.stopMusic(fadeOutDuration: 1.5);

// Pause and resume
audioEngine.pauseMusic();
audioEngine.resumeMusic();
```

## Architecture

```
Just Game Engine
├── Core Engine
│   ├── Engine (Main orchestrator)
│   ├── GameLoop (Fixed timestep loop)
│   ├── TimeManager (Delta time tracking)
│   └── SystemManager (Subsystem coordination)
├── Rendering Engine
│   ├── RenderingEngine (Canvas rendering)
│   ├── Camera (View transformation)
│   ├── Renderable (Base class)
│   └── GameWidget (Flutter integration)
├── Sprite System
│   ├── Sprite (Image rendering)
│   ├── SpriteSheet (Texture atlas)
│   └── NineSliceSprite (Scalable UI)
├── Animation System
│   ├── Animation (Base class)
│   ├── SpriteAnimation (Frame-based)
│   ├── TweenAnimation (Property lerp)
│   └── Easings (Curve functions)
├── Particle Effects
│   ├── ParticleEmitter (Emission control)
│   ├── Particle (Individual particle)
│   └── ParticleEffects (Presets)
├── Physics Engine
│   ├── PhysicsEngine (Simulation)
│   └── PhysicsBody (Rigid body)
├── Scene Graph
│   ├── SceneEditor (Scene management)
│   ├── Scene (Node container)
│   └── SceneNode (Transform hierarchy)
├── Entity-Component System
│   ├── World (Entity management)
│   ├── Entity (Component container)
│   ├── Component (Data storage)
│   ├── System (Processing logic)
│   ├── Built-in Components:
│   │   ├── TransformComponent
│   │   ├── VelocityComponent
│   │   ├── RenderableComponent
│   │   ├── PhysicsBodyComponent
│   │   ├── HealthComponent
│   │   └── 8 more...
│   └── Built-in Systems:
│       ├── MovementSystem
│       ├── RenderSystem
│       ├── PhysicsSystem
│       └── 6 more...
├── Input Management
│   ├── InputManager (Main coordinator)
│   ├── KeyboardInput (Key states)
│   ├── MouseInput (Position, buttons, scroll)
│   ├── TouchInput (Multi-touch)
│   └── ControllerInput (Gamepad support)
├── Asset Management
│   ├── AssetManager (Loading & caching)
│   ├── ImageAsset (PNG/JPG)
│   ├── AudioAsset (MP3/WAV/OGG/FLAC)
│   ├── TextAsset (Plain text)
│   ├── JsonAsset (JSON config)
│   ├── BinaryAsset (Raw data)
│   └── AssetBundle (Grouped loading)
├── Audio Engine
│   ├── AudioEngine (Multi-channel mixer)
│   ├── AudioClip (Playback control)
│   ├── SoundEffectManager (SFX)
│   ├── MusicManager (Background music)
│   └── AudioMixer (Volume control)
└── Additional Systems
    └── Networking (Not Implemented)
```

## Performance Tips

1. **Use Object Pooling**: Reuse particles and projectiles instead of creating new ones
2. **Limit Renderables**: Only render what's visible on screen
3. **Batch Rendering**: Group similar draw calls together
4. **Profile Regularly**: Use Flutter DevTools to identify bottlenecks
5. **Optimize Collision Detection**: Use spatial partitioning for many objects
6. **Cache Calculations**: Store frequently used values like cos/sin results

## Examples

Check out the `example/` folder for complete examples:

- `core_system_example.dart` - Basic engine setup and usage
- `ecs_example.dart` - Entity-Component System with physics and collisions
- `input_test_example.dart` - Complete input system demo (keyboard, mouse, touch)

## API Reference

### Core Classes

- `Engine` - Main engine singleton
- `GameLoop` - Game loop with fixed timestep
- `TimeManager` - Time tracking and delta time

### Rendering Classes

- `RenderingEngine` - 2D rendering system
- `Camera` - Camera transformation and controls
- `Renderable` - Base class for all renderables
- `CircleRenderable`, `RectangleRenderable`, `LineRenderable`, `TextRenderable`, `CustomRenderable`

### Animation Classes

- `Animation` - Base animation class
- `SpriteAnimation` - Frame-based sprite animation
- `PositionTween`, `RotationTween`, `ScaleTween`, `OpacityTween`, `ColorTween`
- `AnimationSequence` - Sequential animations
- `AnimationGroup` - Parallel animations
- `Easings` - Easing function library

### Particle Classes

- `ParticleEmitter` - Particle emission controller
- `Particle` - Individual particle instance
- `ParticleEffects` - Built-in effect presets

### Physics Classes

- `PhysicsEngine` - Physics simulation
- `PhysicsBody` - Rigid body with collision

### Scene Classes

- `SceneEditor` - Scene management
- `Scene` - Scene container
- `SceneNode` - Hierarchical transform node

### ECS Classes

- `World` - Entity and system manager
- `Entity` - Component container with unique ID
- `Component` - Base class for data components
- `System` - Base class for processing systems
- **Built-in Components**: `TransformComponent`, `VelocityComponent`, `RenderableComponent`, `PhysicsBodyComponent`, `HealthComponent`, `LifetimeComponent`, `TagComponent`, `ParentComponent`, `ChildrenComponent`, `InputComponent`, `AnimationStateComponent`, `SpriteComponent`
- **Built-in Systems**: `MovementSystem`, `RenderSystem`, `PhysicsSystem`, `LifetimeSystem`, `HierarchySystem`, `HealthSystem`, `AnimationSystemECS`, `BoundarySystem`

### Input Classes

- `InputManager` - Main input coordinator with keyboard, mouse, touch, and controller access
- `KeyboardInput` - Key press/hold/release detection with axis support
- `MouseInput` - Mouse position, buttons, scroll, and delta tracking
- `TouchInput` - Multi-touch support with touch points
- `ControllerInput` - Gamepad analog sticks, triggers, and buttons
- `MouseButton` - Mouse button constants (left, right, middle)
- `GamepadButton` - Gamepad button constants (A, B, X, Y, etc.)
- `GamepadAxis` - Gamepad axis identifiers (left stick, right stick, triggers)

### Asset Management Classes

- `AssetManager` - Asset loading and caching coordinator
- `Asset` - Base class for all asset types
- `ImageAsset` - Image asset loader (PNG/JPG)
- `AudioAsset` - Audio asset loader (MP3/WAV/OGG/FLAC)
- `TextAsset` - Plain text file loader
- `JsonAsset` - JSON configuration file loader
- `BinaryAsset` - Raw binary data loader
- `AssetBundle` - Grouped asset loading/unloading

### Audio Engine Classes

- `AudioEngine` - Multi-channel audio playback coordinator
- `AudioClip` - Individual audio source controller
- `SoundEffectManager` - Sound effect playback wrapper
- `MusicManager` - Background music control with fade effects
- `AudioMixer` - Volume and mute control interface
- `AudioChannel` - Audio channel enum (master, music, sfx, voice, ambient)
- `AudioState` - Playback state enum (stopped, playing, paused)

## Dependencies

- **Flutter SDK**: 3.11.0 or higher
- **Dart SDK**: 3.0.0 or higher
- **audioplayers**: ^6.1.0 (for Audio Engine)

## Contributing

Contributions are welcome! This engine is in active development.

## License

This project is licensed under the BSD-3-Clause License - see the LICENSE file for details.

## Acknowledgments

- Built with Flutter
- Inspired by Unity, Godot, and Flame engines
