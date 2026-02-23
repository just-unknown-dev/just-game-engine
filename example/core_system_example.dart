// Example: Basic Engine Usage
//
// This example demonstrates how to initialize and use the Just Game Engine core system.

import 'package:flutter/foundation.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  debugPrint('=== Just Game Engine - Core System Example ===\n');

  // Example 1: Basic initialization and lifecycle
  await basicUsageExample();

  debugPrint('\n');

  // Example 2: Time management
  await timeManagementExample();

  debugPrint('\n');

  // Example 3: Engine states
  await engineStatesExample();
}

/// Example 1: Basic engine initialization and lifecycle
Future<void> basicUsageExample() async {
  debugPrint('--- Example 1: Basic Usage ---');

  // Get the engine instance (singleton)
  final engine = Engine();

  // Initialize the engine
  debugPrint('Initializing engine...');
  final initialized = await engine.initialize();

  if (!initialized) {
    debugPrint('Failed to initialize engine!');
    return;
  }

  debugPrint('Engine initialized successfully');
  debugPrint('Engine state: ${engine.state}');

  // Start the engine
  debugPrint('Starting engine...');
  engine.start();

  // Simulate running for a short time
  await Future.delayed(const Duration(seconds: 2));

  // Pause the engine
  debugPrint('Pausing engine...');
  engine.pause();
  debugPrint('Engine state: ${engine.state}');

  await Future.delayed(const Duration(seconds: 1));

  // Resume the engine
  debugPrint('Resuming engine...');
  engine.resume();

  await Future.delayed(const Duration(seconds: 1));

  // Stop the engine
  debugPrint('Stopping engine...');
  engine.stop();
  debugPrint('Engine state: ${engine.state}');

  // Cleanup
  debugPrint('Disposing engine...');
  engine.dispose();
  debugPrint('Engine disposed');
}

/// Example 2: Time management features
Future<void> timeManagementExample() async {
  debugPrint('--- Example 2: Time Management ---');

  final engine = Engine();
  await engine.initialize();

  // Access the time manager
  final time = engine.time;

  debugPrint('Time scale: ${time.timeScale}');
  debugPrint('Delta time: ${time.deltaTime}');
  debugPrint('Total time: ${time.totalTime}');
  debugPrint('Frame count: ${time.frameCount}');

  // Slow motion effect
  debugPrint('\nApplying slow motion (0.5x speed)');
  time.slowMotion(0.5);
  debugPrint('Time scale: ${time.timeScale}');

  // Fast forward effect
  debugPrint('\nApplying fast forward (2.0x speed)');
  time.fastForward(2.0);
  debugPrint('Time scale: ${time.timeScale}');

  // Pause time
  debugPrint('\nPausing time');
  time.pause();
  debugPrint('Time scale: ${time.timeScale}');

  // Resume normal time
  debugPrint('\nResuming normal time');
  time.resume();
  debugPrint('Time scale: ${time.timeScale}');

  engine.dispose();
}

/// Example 3: Working with engine states
Future<void> engineStatesExample() async {
  debugPrint('--- Example 3: Engine States ---');

  final engine = Engine();

  // Check initial state
  debugPrint('Initial state: ${engine.state}');
  debugPrint('Is initialized: ${engine.isInitialized}');
  debugPrint('Is running: ${engine.isRunning}');

  // Initialize
  await engine.initialize();
  debugPrint('\nAfter initialization:');
  debugPrint('State: ${engine.state}');
  debugPrint('Is initialized: ${engine.isInitialized}');
  debugPrint('Is running: ${engine.isRunning}');

  // Start
  engine.start();
  debugPrint('\nAfter start:');
  debugPrint('State: ${engine.state}');
  debugPrint('Is running: ${engine.isRunning}');

  // Pause
  engine.pause();
  debugPrint('\nAfter pause:');
  debugPrint('State: ${engine.state}');
  debugPrint('Is paused: ${engine.isPaused}');

  // Resume
  engine.resume();
  debugPrint('\nAfter resume:');
  debugPrint('State: ${engine.state}');
  debugPrint('Is running: ${engine.isRunning}');

  // Stop
  engine.stop();
  debugPrint('\nAfter stop:');
  debugPrint('State: ${engine.state}');
  debugPrint('Is running: ${engine.isRunning}');

  engine.dispose();
}

/// Example 4: Accessing subsystems
void subsystemExample() {
  debugPrint('--- Example 4: Accessing Subsystems ---');

  final engine = Engine();

  // Access subsystems directly
  final physics = engine.physics;
  final rendering = engine.rendering;
  final input = engine.input;
  final audio = engine.audio;

  debugPrint('Physics engine: ${physics.runtimeType}');
  debugPrint('Rendering engine: ${rendering.runtimeType}');
  debugPrint('Input manager: ${input.runtimeType}');
  debugPrint('Audio engine: ${audio.runtimeType}');

  // Or use the generic getSystem method
  final physicsSystem = engine.getSystem<PhysicsEngine>();
  debugPrint('\nPhysics via getSystem: ${physicsSystem?.runtimeType}');
}

/// Example 5: Custom update loop
class GameExample {
  final Engine engine;

  GameExample(this.engine);

  Future<void> run() async {
    debugPrint('--- Example 5: Custom Game Loop ---');

    await engine.initialize();

    // Custom initialization
    debugPrint('Loading game assets...');
    // engine.assets.loadAsset('path/to/asset');

    debugPrint('Initializing game world...');
    // Setup game world, spawn entities, etc.

    // Start the engine
    engine.start();
    debugPrint('Game started!');

    // Simulate game running
    await Future.delayed(const Duration(seconds: 3));

    // Cleanup
    engine.stop();
    engine.dispose();
    debugPrint('Game ended!');
  }

  void update(double deltaTime) {
    // Game-specific update logic
    // Update game objects
    // player.update(deltaTime);
    // enemies.update(deltaTime);

    // Check win/lose conditions
    // if (player.isDead) { gameOver(); }
  }

  void render() {
    // Game-specific rendering
    // renderWorld();
    // renderUI();
  }
}

/// Example 6: Using lifecycle interfaces
class CustomSystem implements ILifecycle, IUpdatable {
  bool _initialized = false;

  @override
  Future<bool> initialize() async {
    debugPrint('CustomSystem: Initializing...');
    // Perform initialization
    await Future.delayed(const Duration(milliseconds: 100));
    _initialized = true;
    debugPrint('CustomSystem: Initialized');
    return true;
  }

  @override
  void update(double deltaTime) {
    if (!_initialized) return;
    // Update logic here
    // debugPrint('CustomSystem: Update (dt: ${deltaTime.toStringAsFixed(3)})');
  }

  @override
  void dispose() {
    debugPrint('CustomSystem: Disposing...');
    _initialized = false;
    debugPrint('CustomSystem: Disposed');
  }
}
