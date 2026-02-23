# Just Game Engine - Core System Architecture

## Overview

The core system is the heart of the Just Game Engine. It provides the foundational infrastructure for managing the game loop, timing, and coordinating all engine subsystems.

## Architecture Components

### 1. Engine (`engine.dart`)

The main engine class that orchestrates all subsystems and manages the overall engine lifecycle.

**Key Features:**
- Singleton pattern for global access
- State management (uninitialized, initializing, initialized, running, paused, error)
- Subsystem coordination
- Lifecycle management

**Usage Example:**
```dart
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  final engine = Engine();
  
  // Initialize the engine
  await engine.initialize();
  
  // Start the game loop
  engine.start();
  
  // Access subsystems
  final physics = engine.physics;
  final rendering = engine.rendering;
  
  // Pause the engine
  engine.pause();
  
  // Resume
  engine.resume();
  
  // Stop and cleanup
  engine.stop();
  engine.dispose();
}
```

**Engine States:**
- `uninitialized` - Engine has not been initialized
- `initializing` - Engine is currently initializing
- `initialized` - Engine is initialized but not running
- `running` - Engine is running and updating
- `paused` - Engine is paused
- `error` - Engine encountered an error

### 2. Game Loop (`game_loop.dart`)

Implements the main game loop with fixed timestep for updates and variable timestep for rendering.

**Key Features:**
- Fixed timestep updates (default: 60 UPS)
- Variable timestep rendering
- Frame accumulation to handle frame rate variations
- FPS calculation
- Spiral of death prevention

**Technical Details:**
- Uses a periodic timer running at ~120Hz
- Accumulates frame time for fixed timestep updates
- Clamps accumulator to prevent excessive catch-up
- Provides interpolation factor for smooth rendering

**Usage Example:**
```dart
final gameLoop = GameLoop(
  onUpdate: (deltaTime) {
    // Update game logic
    physics.update(deltaTime);
  },
  onRender: () {
    // Render the frame
    rendering.render();
  },
  timeManager: timeManager,
  targetUPS: 60, // 60 updates per second
);

gameLoop.start();
```

### 3. Time Manager (`time_manager.dart`)

Manages all time-related functionality for the engine.

**Key Features:**
- Delta time tracking (scaled and unscaled)
- Total elapsed time
- Time scale for slow motion / fast forward effects
- Frame counting
- FPS calculation
- Maximum delta time clamping

**Usage Example:**
```dart
final time = engine.time;

// Get delta time for frame-independent movement
position += velocity * time.deltaTime;

// Slow motion effect
time.slowMotion(0.5); // Half speed

// Fast forward
time.fastForward(2.0); // Double speed

// Pause time
time.pause();

// Resume normal time
time.resume();

// Get unscaled delta time (not affected by time scale)
final realDeltaTime = time.unscaledDeltaTime;
```

### 4. System Manager (`system_manager.dart`)

Manages and coordinates all engine subsystems.

**Key Features:**
- System registration by name and type
- Type-safe system retrieval
- Lifecycle management for registered systems
- System enumeration

**Usage Example:**
```dart
final systemManager = SystemManager();

// Register systems
systemManager.registerSystem('physics', physicsEngine);
systemManager.registerSystem('rendering', renderingEngine);

// Retrieve by type
final physics = systemManager.getSystem<PhysicsEngine>();

// Retrieve by name
final rendering = systemManager.getSystemByName('rendering');

// Check if system exists
if (systemManager.hasSystem('networking')) {
  // Do something
}

// Cleanup
systemManager.dispose();
```

### 5. Lifecycle Interface (`lifecycle.dart`)

Defines standard interfaces for engine systems.

**Interfaces:**

#### `ILifecycle`
Basic lifecycle management with initialize() and dispose()

#### `IUpdatable`
For systems that need per-frame updates with update(deltaTime)

#### `IRenderable`
For systems that need to render with render()

#### `IPausable`
For systems that support pausing with pause(), resume(), and isPaused

#### `IEnableable`
For systems that can be toggled with enable(), disable(), and isEnabled

#### `LifecycleStateMixin`
Mixin providing state tracking (initialized, disposed) with validation

**Usage Example:**
```dart
class MySystem implements ILifecycle, IUpdatable {
  @override
  Future<bool> initialize() async {
    // Initialize resources
    return true;
  }
  
  @override
  void update(double deltaTime) {
    // Update logic
  }
  
  @override
  void dispose() {
    // Cleanup
  }
}

// Using the mixin
class MyOtherSystem with LifecycleStateMixin implements ILifecycle {
  @override
  Future<bool> initialize() async {
    markInitialized();
    return true;
  }
  
  void doSomething() {
    ensureInitialized(); // Throws if not initialized
    ensureNotDisposed(); // Throws if disposed
    // ... do work
  }
  
  @override
  void dispose() {
    markDisposed();
  }
}
```

## Design Patterns

### 1. Singleton Pattern
The `Engine` class uses the singleton pattern to ensure only one instance exists globally.

### 2. Service Locator Pattern
The `SystemManager` acts as a service locator, providing centralized access to all subsystems.

### 3. Game Loop Pattern
The `GameLoop` implements the classic game loop pattern with fixed timestep for deterministic updates.

### 4. Observer Pattern
Can be extended with event systems for loose coupling between systems.

## Performance Considerations

### Fixed Timestep Benefits
- Deterministic physics simulation
- Consistent gameplay across different hardware
- Easier to implement replays and networking

### Frame Time Clamping
- Prevents spiral of death scenarios
- Maintains stability on low-performance devices
- Configurable maximum delta time

### Interpolation
- Provides smooth rendering between update steps
- Available via `gameLoop.interpolation` property
- Useful for physics-driven rendering

## Extension Points

### Adding New Subsystems

1. Create your subsystem class implementing `ILifecycle`:
```dart
class MySubsystem implements ILifecycle {
  @override
  Future<bool> initialize() async {
    // Initialize
    return true;
  }
  
  @override
  void dispose() {
    // Cleanup
  }
}
```

2. Register it in the Engine initialization:
```dart
final mySubsystem = MySubsystem();
await mySubsystem.initialize();
systemManager.registerSystem('mySubsystem', mySubsystem);
```

3. Update in the game loop if needed:
```dart
if (mySubsystem is IUpdatable) {
  mySubsystem.update(deltaTime);
}
```

## Best Practices

1. **Always initialize before use**: Call `engine.initialize()` before `engine.start()`
2. **Handle errors**: Check return values from initialize() methods
3. **Proper cleanup**: Always call `engine.dispose()` when done
4. **Use delta time**: All movement should be multiplied by `deltaTime` for frame independence
5. **Respect engine state**: Check `engine.state` before performing operations
6. **Time scale awareness**: Use `unscaledDeltaTime` for UI and effects that shouldn't be affected by time manipulation

## Future Enhancements

- Event system for inter-system communication
- Plugin architecture for extending engine functionality
- Profiling and debugging tools
- Save/load state functionality
- Multi-threading support for heavy computations
- Custom update priorities for systems
