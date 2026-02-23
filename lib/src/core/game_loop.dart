/// Game Loop
///
/// Implements the main game loop with fixed timestep and variable rendering.
/// Manages frame timing and calls update/render callbacks.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'time_manager.dart';

/// Type definition for update callback
typedef UpdateCallback = void Function(double deltaTime);

/// Type definition for render callback
typedef RenderCallback = void Function();

/// Main game loop implementation
///
/// This class manages the game's update-render cycle with proper timing.
/// It uses a fixed timestep for updates and variable timestep for rendering.
///
/// The game loop runs continuously, calling update at a fixed rate and
/// render as fast as possible (limited by vsync when available).
class GameLoop {
  /// Update callback function
  final UpdateCallback onUpdate;

  /// Render callback function
  final RenderCallback onRender;

  /// Time manager for tracking time
  final TimeManager timeManager;

  /// Target updates per second (fixed timestep)
  final int targetUPS;

  /// Whether the loop is currently running
  bool _isRunning = false;

  /// Whether the loop is paused
  bool _isPaused = false;

  /// Timer for the game loop
  Timer? _timer;

  /// Fixed timestep in seconds
  late final double _fixedDeltaTime;

  /// Time accumulator for fixed timestep
  double _accumulator = 0.0;

  /// Last frame timestamp
  DateTime _lastFrameTime = DateTime.now();

  /// Frame counter for FPS calculation
  int _frameCount = 0;

  /// Timer for FPS calculation
  DateTime _fpsTimer = DateTime.now();

  /// Current frames per second
  int _currentFPS = 0;

  /// Get current FPS
  int get currentFPS => _currentFPS;

  /// Check if loop is running
  bool get isRunning => _isRunning;

  /// Check if loop is paused
  bool get isPaused => _isPaused;

  /// Create a game loop
  ///
  /// [onUpdate] - Called at fixed intervals for game logic
  /// [onRender] - Called every frame for rendering
  /// [timeManager] - Time manager instance
  /// [targetUPS] - Target updates per second (default: 60)
  GameLoop({
    required this.onUpdate,
    required this.onRender,
    required this.timeManager,
    this.targetUPS = 60,
  }) {
    _fixedDeltaTime = 1.0 / targetUPS;
  }

  /// Start the game loop
  void start() {
    if (_isRunning) {
      debugPrint('Game loop is already running');
      return;
    }

    _isRunning = true;
    _isPaused = false;
    _lastFrameTime = DateTime.now();
    _fpsTimer = DateTime.now();
    _frameCount = 0;

    // Start the loop with a periodic timer
    // This runs at approximately 120Hz to allow smooth updates
    _timer = Timer.periodic(
      const Duration(microseconds: 8333), // ~120Hz
      (_) => _tick(),
    );

    debugPrint('Game loop started (Target UPS: $targetUPS)');
  }

  /// Pause the game loop
  void pause() {
    if (!_isRunning || _isPaused) {
      return;
    }

    _isPaused = true;
    debugPrint('Game loop paused');
  }

  /// Resume the game loop
  void resume() {
    if (!_isRunning || !_isPaused) {
      return;
    }

    _isPaused = false;
    _lastFrameTime = DateTime.now();
    debugPrint('Game loop resumed');
  }

  /// Stop the game loop
  void stop() {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _isPaused = false;
    _timer?.cancel();
    _timer = null;

    debugPrint('Game loop stopped');
  }

  /// Main loop tick
  void _tick() {
    if (!_isRunning) {
      return;
    }

    final now = DateTime.now();
    final frameTime = now.difference(_lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = now;

    // Update time manager
    timeManager.update(frameTime);

    // Calculate FPS
    _calculateFPS(now);

    // Don't update game logic if paused
    if (!_isPaused) {
      // Accumulate frame time
      _accumulator += frameTime;

      // Clamp accumulator to prevent spiral of death
      if (_accumulator > _fixedDeltaTime * 5) {
        _accumulator = _fixedDeltaTime * 5;
      }

      // Update at fixed timestep
      while (_accumulator >= _fixedDeltaTime) {
        onUpdate(_fixedDeltaTime);
        _accumulator -= _fixedDeltaTime;
      }
    }

    // Always render (even when paused)
    onRender();
  }

  /// Calculate frames per second
  void _calculateFPS(DateTime now) {
    _frameCount++;

    final elapsed = now.difference(_fpsTimer).inMilliseconds;
    if (elapsed >= 1000) {
      _currentFPS = (_frameCount * 1000 / elapsed).round();
      _frameCount = 0;
      _fpsTimer = now;
    }
  }

  /// Get the current interpolation factor for rendering
  ///
  /// This can be used for smooth rendering between update steps.
  double get interpolation => _accumulator / _fixedDeltaTime;
}
