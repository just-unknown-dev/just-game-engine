/// Game Loop
///
/// Implements the main game loop with fixed timestep and variable rendering.
/// This loop is driven externally by the rendering widget's vsync Ticker
/// (or by a manual caller for headless / test scenarios).
library;

import 'package:flutter/foundation.dart';

import 'system_manager.dart' show FrameTask, UpdateTask;
import 'time_manager.dart';

/// Main game loop implementation
///
/// This class manages the game's update-render cycle with proper timing.
/// It uses a fixed timestep for updates and variable timestep for rendering.
///
/// The loop is *externally driven* — call [tick] once per frame (typically
/// from a `Ticker` in [GameWidget]).  For headless / server scenarios you can
/// call [tick] from your own timer or test harness.
///
/// Several drivers may tick one loop — two `GameWidget`s showing one engine
/// — as long as they pass the frame's own timestamp: a second tick with the
/// stamp of the last is the same frame and is ignored.
class GameLoop {
  /// One fixed step of game logic, given the step's length in seconds
  /// (scaled by the time scale).
  final UpdateTask onUpdate;

  /// Called at the end of every [tick], also while paused: what runs on
  /// real time — the engine's plugins (an editor), camera post effects, and
  /// input and audio while paused. Drawing itself is Flutter's
  /// `CustomPainter`'s.
  final VoidCallback? onRender;

  /// Called once per frame after the fixed updates, while not paused: the
  /// per-frame phase (a camera following between physics steps, a look that
  /// reads this frame's mouse movement). It gets the frame's length in
  /// seconds — at most [TimeManager.maxDeltaTime], then scaled by the time
  /// scale — and how far the frame lies between the last two fixed updates
  /// (0..1).
  final FrameTask? onFrame;

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

  /// The frame timestamp the next frame is measured from, in microseconds;
  /// null before the first stamped tick and after [start] or [resume].
  int? _lastTickMicros;

  /// The frame timestamp of the last stamped [tick], in microseconds — kept
  /// through [resume], so a frame ticked by two drivers counts once.
  int? _lastStampMicros;

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
  /// [onRender] - Optional callback at the end of every tick, paused or not
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
    _lastStampMicros = null;

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
  /// [frameTime] is the frame's timestamp on a clock every caller shares —
  /// the vsync frame's `SchedulerBinding.currentFrameTimeStamp`, which is
  /// what [GameWidget] passes — and the frame lasts from the previous one's
  /// to it. A tick with the same stamp as the last is the same frame, asked
  /// for again by another driver, and does nothing. Without a stamp the
  /// loop times the frame with its own stopwatch, read when [tick] is
  /// called. Pass it when you have it: vsync timestamps are exact, and the
  /// time a callback happens to run is not — on the web `performance.now()`
  /// is coarsened, and a stopwatch-timed 60 Hz frame there alternates
  /// between none and two fixed updates.
  ///
  /// A fixed step that throws ends the frame's steps — the error is
  /// rethrown — but [onFrame] and [onRender] still run, and the steps the
  /// frame had left are dropped rather than run in a burst later.
  void tick([Duration? frameTime]) {
    if (!_isRunning) return;

    final nowMicros = _clock.elapsedMicroseconds;
    final int frameMicros;
    if (frameTime != null) {
      final stamp = frameTime.inMicroseconds;
      // This frame has been ticked already, by another view of the engine.
      if (stamp == _lastStampMicros) return;
      _lastStampMicros = stamp;
      final last = _lastTickMicros;
      // The first stamped frame, or a new clock counting from zero again,
      // has nothing to measure from.
      frameMicros = last == null || stamp < last ? 0 : stamp - last;
      _lastTickMicros = stamp;
    } else {
      frameMicros = _lastFrameMicros == 0 ? 0 : nowMicros - _lastFrameMicros;
      _lastTickMicros = null;
      _lastStampMicros = null;
    }
    _lastFrameMicros = nowMicros;
    final frameSeconds = frameMicros / 1000000.0;

    // Game time stands still while paused; real time goes on.
    timeManager.update(frameSeconds, paused: _isPaused);

    // Calculate FPS
    _calculateFPS(frameMicros);

    try {
      // Don't update game logic if paused
      if (!_isPaused) _step(frameSeconds);
    } finally {
      try {
        // Clamped like the time manager's: after a hitch the per-frame phase
        // gets a long frame, not seconds of one.
        if (!_isPaused) onFrame?.call(timeManager.deltaTime, interpolation);
      } finally {
        onRender?.call();
      }
    }
  }

  /// The frame's fixed steps, for [frameSeconds] more of game time.
  void _step(double frameSeconds) {
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
      // Taken before the step runs: one that throws is not owed again.
      _accumulator -= _fixedDeltaTime;
      try {
        // Use scaled delta so TimeManager.timeScale affects simulation speed.
        onUpdate(_fixedDeltaTime * timeManager.timeScale);
      } catch (_) {
        // The frame's other steps go with it — no burst of catch-up steps
        // once the step stops throwing.
        if (_accumulator > 0) _accumulator %= _fixedDeltaTime;
        rethrow;
      }
    }
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
