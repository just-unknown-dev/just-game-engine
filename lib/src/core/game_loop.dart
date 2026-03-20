/// Game Loop
///
/// Implements the main game loop with fixed timestep and variable rendering.
/// This loop is driven externally by the rendering widget's vsync Ticker
/// (or by a manual caller for headless / test scenarios).
library;

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
/// The loop is *externally driven* — call [tick] once per frame (typically
/// from a [Ticker] in [GameWidget]).  For headless / server scenarios you can
/// call [tick] from your own timer or test harness.
class GameLoop {
  /// Update callback function
  final UpdateCallback onUpdate;

  /// Render callback function (kept for headless compatibility — a no-op when
  /// rendering is handled by Flutter's [CustomPainter]).
  final RenderCallback? onRender;

  /// Time manager for tracking time
  final TimeManager timeManager;

  /// Target updates per second (fixed timestep)
  final int targetUPS;

  /// Whether the loop is currently running
  bool _isRunning = false;

  /// Whether the loop is paused
  bool _isPaused = false;

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
  /// [onRender] - Optional render callback (no-op when a widget drives rendering)
  /// [timeManager] - Time manager instance
  /// [targetUPS] - Target updates per second (default: 60)
  GameLoop({
    required this.onUpdate,
    this.onRender,
    required this.timeManager,
    this.targetUPS = 60,
  }) {
    _fixedDeltaTime = 1.0 / targetUPS;
  }

  /// Mark the game loop as running and reset timing state.
  ///
  /// No internal timer is created — the loop must be driven externally via
  /// [tick] (e.g. from a vsync [Ticker] in the rendering widget).
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
    // Reset accumulator to prevent a burst of fixed-timestep updates after
    // a long pause.
    _accumulator = 0.0;
    debugPrint('Game loop resumed');
  }

  /// Stop the game loop
  void stop() {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _isPaused = false;

    debugPrint('Game loop stopped');
  }

  /// Advance the game loop by one frame.
  ///
  /// Call this once per vsync frame from the rendering widget's [Ticker],
  /// or from a manual timer / test harness for headless usage.
  void tick() {
    if (!_isRunning) return;

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
        // Use scaled delta so TimeManager.timeScale affects simulation speed.
        onUpdate(_fixedDeltaTime * timeManager.timeScale);
        _accumulator -= _fixedDeltaTime;
      }
    }

    // Optional render callback (no-op when CustomPainter renders).
    onRender?.call();
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
