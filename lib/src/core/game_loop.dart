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

/// Called once per rendered frame, after its fixed updates: [deltaTime] is
/// the frame's length in seconds (scaled by the time scale), [alpha] how far
/// the frame lies between the last two fixed updates (0..1).
typedef FrameCallback = void Function(double deltaTime, double alpha);

/// Main game loop implementation
///
/// This class manages the game's update-render cycle with proper timing.
/// It uses a fixed timestep for updates and variable timestep for rendering.
///
/// The loop is *externally driven* — call [tick] once per frame (typically
/// from a `Ticker` in [GameWidget]).  For headless / server scenarios you can
/// call [tick] from your own timer or test harness.
class GameLoop {
  /// Update callback function
  final UpdateCallback onUpdate;

  /// Render callback function (kept for headless compatibility — a no-op when
  /// rendering is handled by Flutter's `CustomPainter`).
  final RenderCallback? onRender;

  /// Called once per frame after the fixed updates, while not paused: the
  /// per-frame phase (a camera following between physics steps, a look that
  /// reads this frame's mouse movement).
  final FrameCallback? onFrame;

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

  /// Monotonic clock for frame timing.
  final Stopwatch _clock = Stopwatch();

  /// Last frame timestamp in microseconds from [_clock].
  int _lastFrameMicros = 0;

  /// The frame timestamp the last [tick] was given, in microseconds; null
  /// before the first such tick and after [start] or [resume].
  int? _lastTickMicros;

  /// Frame counter for FPS calculation
  int _frameCount = 0;

  /// Accumulated frame time for FPS calculation.
  int _fpsElapsedMicros = 0;

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
  /// [onFrame] - Optional per-frame callback, after the fixed updates
  /// [timeManager] - Time manager instance
  /// [targetUPS] - Target updates per second (default: 60)
  GameLoop({
    required this.onUpdate,
    this.onRender,
    this.onFrame,
    required this.timeManager,
    this.targetUPS = 60,
  }) {
    _fixedDeltaTime = 1.0 / targetUPS;
  }

  /// Mark the game loop as running and reset timing state.
  ///
  /// No internal timer is created — the loop must be driven externally via
  /// [tick] (e.g. from a vsync `Ticker` in the rendering widget).
  void start() {
    if (_isRunning) {
      debugPrint('Game loop is already running');
      return;
    }

    _isRunning = true;
    _isPaused = false;
    _accumulator = 0.0;
    _frameCount = 0;
    _fpsElapsedMicros = 0;
    _currentFPS = 0;
    _clock
      ..reset()
      ..start();
    _lastFrameMicros = 0;
    _lastTickMicros = null;

    if (kDebugMode) debugPrint('Game loop started (Target UPS: $targetUPS)');
  }

  /// Pause the game loop
  void pause() {
    if (!_isRunning || _isPaused) {
      return;
    }

    _isPaused = true;
    if (kDebugMode) debugPrint('Game loop paused');
  }

  /// Resume the game loop
  void resume() {
    if (!_isRunning || !_isPaused) {
      return;
    }

    _isPaused = false;
    _lastFrameMicros = _clock.elapsedMicroseconds;
    _lastTickMicros = null;
    // Reset accumulator to prevent a burst of fixed-timestep updates after
    // a long pause.
    _accumulator = 0.0;
    if (kDebugMode) debugPrint('Game loop resumed');
  }

  /// Stop the game loop
  void stop() {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _isPaused = false;
    _clock.stop();

    if (kDebugMode) debugPrint('Game loop stopped');
  }

  /// Advance the game loop by one frame.
  ///
  /// Call this once per vsync frame from the rendering widget's `Ticker`,
  /// or from a manual timer / test harness for headless usage.
  ///
  /// [frameTime] is the frame's timestamp — the ticker's `elapsed` — and
  /// the frame lasts from the previous one's to it. Without it the loop
  /// times the frame with its own stopwatch, read when [tick] is called.
  /// Pass it when you have it: vsync timestamps are exact, and the time a
  /// callback happens to run is not — on the web `performance.now()` is
  /// coarsened, and a stopwatch-timed 60 Hz frame there alternates between
  /// none and two fixed updates.
  void tick([Duration? frameTime]) {
    if (!_isRunning) return;

    final nowMicros = _clock.elapsedMicroseconds;
    final int frameMicros;
    if (frameTime != null) {
      final stamp = frameTime.inMicroseconds;
      final last = _lastTickMicros;
      // The first stamped frame, or a new ticker counting from zero again,
      // has nothing to measure from.
      frameMicros = last == null || stamp < last ? 0 : stamp - last;
      _lastTickMicros = stamp;
    } else {
      frameMicros = _lastFrameMicros == 0 ? 0 : nowMicros - _lastFrameMicros;
      _lastTickMicros = null;
    }
    _lastFrameMicros = nowMicros;
    final frameSeconds = frameMicros / 1000000.0;

    // Update time manager
    timeManager.update(frameSeconds);

    // Calculate FPS
    _calculateFPS(frameMicros);

    // Don't update game logic if paused
    if (!_isPaused) {
      // Accumulate frame time
      _accumulator += frameSeconds;

      // Clamp accumulator to prevent spiral of death
      if (_accumulator > _fixedDeltaTime * 3) {
        _accumulator = _fixedDeltaTime * 3;
      }

      // Update at fixed timestep. A step is taken when the accumulator is
      // within [_stepSlack] of one: frame stamps come rounded (to whole
      // microseconds natively, far coarser on the web), so a 60 Hz frame
      // measures a hair under or over 1/60 s, and a strict comparison left
      // the accumulator straddling the step — none, then two, updates in a
      // row. The slack borrows from the next frame and is paid back.
      while (_accumulator >= _fixedDeltaTime * (1 - _stepSlack)) {
        // Use scaled delta so TimeManager.timeScale affects simulation speed.
        onUpdate(_fixedDeltaTime * timeManager.timeScale);
        _accumulator -= _fixedDeltaTime;
      }

      onFrame?.call(frameSeconds * timeManager.timeScale, interpolation);
    }

    // Optional render callback (no-op when CustomPainter renders).
    onRender?.call();
  }

  /// Calculate frames per second
  void _calculateFPS(int frameMicros) {
    _frameCount++;
    _fpsElapsedMicros += frameMicros;

    if (_fpsElapsedMicros >= 1000000) {
      _currentFPS = (_frameCount * 1000000 / _fpsElapsedMicros).round();
      _frameCount = 0;
      _fpsElapsedMicros = 0;
    }
  }

  /// How early, as a share of a step, a fixed step may be taken; see [tick].
  static const double _stepSlack = 0.01;

  /// Get the current interpolation factor for rendering
  ///
  /// This can be used for smooth rendering between update steps. Always in
  /// `[0, 1]`: a step taken a little early leaves the accumulator just below
  /// zero.
  double get interpolation => (_accumulator / _fixedDeltaTime).clamp(0.0, 1.0);

  /// The length of one fixed step in seconds, before time scale.
  ///
  /// What real time a step stands for — the input clock advances by this,
  /// so a hold still takes its time while the game runs slowed or stopped.
  double get fixedDeltaTime => _fixedDeltaTime;
}
