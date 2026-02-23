/// Core Engine
///
/// The main engine class that coordinates all subsystems and manages the game loop.
/// This is the entry point for initializing and running the game engine.
library;

import 'package:flutter/foundation.dart';

import 'game_loop.dart';
import 'time_manager.dart';
import 'system_manager.dart';
import 'lifecycle.dart';
import '../rendering/rendering_engine.dart';
import '../physics/physics_engine.dart';
import '../input/input_management.dart';
import '../audio/audio_engine.dart';
import '../editor/scene_editor.dart';
import '../animation/animation_system.dart';
import '../assets/asset_management.dart';
import '../networking/networking.dart';
import '../ecs/ecs.dart';

/// Main game engine class that orchestrates all subsystems
///
/// This is the primary interface for interacting with the Just Game Engine.
/// It manages initialization, update cycles, rendering, and cleanup of all subsystems.
///
/// Example usage:
/// ```dart
/// final engine = Engine();
/// await engine.initialize();
/// engine.start();
/// ```
class Engine implements ILifecycle {
  /// Singleton instance of the engine
  static Engine? _instance;

  /// Get the singleton instance
  static Engine get instance {
    _instance ??= Engine._internal();
    return _instance!;
  }

  /// Private constructor for singleton pattern
  Engine._internal();

  /// Factory constructor
  factory Engine() => instance;

  /// Reset the singleton instance (use in tests only)
  @visibleForTesting
  static void resetInstance() => _instance = null;

  /// System manager for coordinating subsystems
  late final SystemManager _systemManager;

  /// Game loop controller
  late final GameLoop _gameLoop;

  /// Time management
  late final TimeManager _timeManager;

  /// Current engine state
  EngineState _state = EngineState.uninitialized;

  /// Get current engine state
  EngineState get state => _state;

  /// Check if engine is initialized
  bool get isInitialized => _state != EngineState.uninitialized;

  /// Check if engine is running
  bool get isRunning => _state == EngineState.running;

  /// Check if engine is paused
  bool get isPaused => _state == EngineState.paused;

  // Subsystem references
  late final RenderingEngine rendering;
  late final PhysicsEngine physics;
  late final InputManager input;
  late final AudioEngine audio;
  late final SceneEditor sceneEditor;
  late final AnimationSystem animation;
  late final AssetManager assets;
  late final NetworkManager network;
  late final World world; // ECS World

  /// Initialize the game engine and all subsystems
  ///
  /// This must be called before starting the engine.
  /// Returns true if initialization was successful.
  @override
  Future<bool> initialize() async {
    if (_state != EngineState.uninitialized) {
      debugPrint('Engine is already initialized');
      return false;
    }

    _state = EngineState.initializing;
    debugPrint('Initializing Just Game Engine...');

    try {
      // Initialize core systems
      _timeManager = TimeManager();
      _systemManager = SystemManager();
      _gameLoop = GameLoop(
        onUpdate: _update,
        onRender: _render,
        timeManager: _timeManager,
      );

      // Initialize subsystems
      await _initializeSubsystems();

      // Register subsystems with system manager
      _registerSystems();

      _state = EngineState.initialized;
      debugPrint('Engine initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to initialize engine: $e');
      _state = EngineState.error;
      return false;
    }
  }

  /// Initialize all engine subsystems
  Future<void> _initializeSubsystems() async {
    debugPrint('Initializing subsystems...');

    // Create subsystem instances
    rendering = RenderingEngine();
    physics = PhysicsEngine();
    input = InputManager();
    audio = AudioEngine();
    sceneEditor = SceneEditor();
    animation = AnimationSystem();
    assets = AssetManager();
    network = NetworkManager();
    world = World(); // ECS World

    // Initialize each subsystem
    assets.initialize(); // Initialize asset manager first
    rendering.initialize();
    physics.initialize();
    input.initialize();
    audio.initialize();
    sceneEditor.initialize();
    animation.initialize();
    network.initialize();
    world.initialize(); // Initialize ECS

    debugPrint('All subsystems initialized');
  }

  /// Register all systems with the system manager
  void _registerSystems() {
    _systemManager.registerSystem('rendering', rendering);
    _systemManager.registerSystem('physics', physics);
    _systemManager.registerSystem('input', input);
    _systemManager.registerSystem('audio', audio);
    _systemManager.registerSystem('editor', sceneEditor);
    _systemManager.registerSystem('animation', animation);
    _systemManager.registerSystem('assets', assets);
    _systemManager.registerSystem('network', network);
    _systemManager.registerSystem('ecs', world);
  }

  /// Start the game engine and begin the game loop
  ///
  /// The engine must be initialized before calling this.
  void start() {
    if (_state != EngineState.initialized) {
      debugPrint('Engine must be initialized before starting');
      return;
    }

    debugPrint('Starting game engine...');
    _state = EngineState.running;
    _gameLoop.start();
  }

  /// Pause the game engine
  ///
  /// This will pause the update loop but continue rendering.
  void pause() {
    if (_state != EngineState.running) {
      debugPrint('Engine is not running');
      return;
    }

    debugPrint('Pausing engine...');
    _state = EngineState.paused;
    _gameLoop.pause();
  }

  /// Resume the game engine from paused state
  void resume() {
    if (_state != EngineState.paused) {
      debugPrint('Engine is not paused');
      return;
    }

    debugPrint('Resuming engine...');
    _state = EngineState.running;
    _gameLoop.resume();
  }

  /// Stop the game engine
  void stop() {
    if (_state != EngineState.running && _state != EngineState.paused) {
      debugPrint('Engine is not running');
      return;
    }

    debugPrint('Stopping engine...');
    _gameLoop.stop();
    _state = EngineState.initialized;
  }

  /// Update the engine state (called every frame)
  void _update(double deltaTime) {
    if (_state != EngineState.running) return;

    // Update subsystems in order
    input.update();
    physics.update(deltaTime);
    animation.update(deltaTime);
    audio.update();
    world.update(deltaTime); // Update ECS

    // Update active scene if available
    // TODO: Implement scene update when scene system is ready
  }

  /// Render the current frame
  ///
  /// Note: Rendering is handled by GameWidget through Flutter's CustomPainter.
  /// This method is called by the game loop but does nothing since Flutter
  /// manages the render cycle through the widget tree.
  void _render() {
    if (_state != EngineState.running) return;

    // Rendering is handled by GameWidget's CustomPainter
    // which calls rendering.render(canvas, size) directly
  }

  /// Dispose of all engine resources and shutdown
  @override
  void dispose() {
    if (_state == EngineState.uninitialized) {
      return;
    }

    debugPrint('Shutting down engine...');

    // Stop the game loop if running
    if (_state == EngineState.running || _state == EngineState.paused) {
      stop();
    }

    // Dispose subsystems in reverse order
    network.dispose();
    animation.dispose();
    sceneEditor.dispose();
    audio.dispose();
    input.dispose();
    physics.dispose();
    rendering.dispose();
    assets.dispose();
    world.dispose(); // Dispose ECS

    _systemManager.dispose();

    _state = EngineState.uninitialized;
    debugPrint('Engine shutdown complete');
  }

  /// Get a reference to a specific subsystem
  ///
  /// Returns null if the system is not found.
  T? getSystem<T>() {
    return _systemManager.getSystem<T>();
  }

  /// Get the current time manager
  TimeManager get time => _timeManager;
}

/// Engine state enumeration
enum EngineState {
  /// Engine has not been initialized
  uninitialized,

  /// Engine is currently initializing
  initializing,

  /// Engine is initialized but not running
  initialized,

  /// Engine is running and updating
  running,

  /// Engine is paused
  paused,

  /// Engine encountered an error
  error,
}
