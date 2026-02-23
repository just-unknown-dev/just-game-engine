/// Time Manager
///
/// Manages time-related functionality for the game engine.
/// Provides delta time, total time, time scale, and other timing utilities.
library;

/// Time management system for the game engine
///
/// This class tracks various time metrics useful for game development:
/// - Delta time: Time since last frame
/// - Total time: Time since engine started
/// - Time scale: Slow motion / fast forward effects
/// - Frame count: Total frames rendered
///
/// Example usage:
/// ```dart
/// final time = engine.time;
/// final deltaTime = time.deltaTime;
/// position += velocity * deltaTime;
/// ```
class TimeManager {
  /// Time since last frame in seconds
  double _deltaTime = 0.0;

  /// Total time since engine started in seconds
  double _totalTime = 0.0;

  /// Time scale multiplier (1.0 = normal speed)
  double _timeScale = 1.0;

  /// Unscaled delta time (not affected by time scale)
  double _unscaledDeltaTime = 0.0;

  /// Total frames rendered
  int _frameCount = 0;

  /// Maximum allowed delta time (prevents huge jumps)
  double _maxDeltaTime = 0.1; // 100ms

  /// Start time
  final DateTime _startTime = DateTime.now();

  /// Get delta time (affected by time scale)
  double get deltaTime => _deltaTime;

  /// Get unscaled delta time
  double get unscaledDeltaTime => _unscaledDeltaTime;

  /// Get total elapsed time
  double get totalTime => _totalTime;

  /// Get time scale
  double get timeScale => _timeScale;

  /// Set time scale (0 = paused, 1 = normal, 2 = double speed)
  set timeScale(double value) {
    if (value < 0) {
      throw ArgumentError('Time scale cannot be negative');
    }
    _timeScale = value;
  }

  /// Get total frame count
  int get frameCount => _frameCount;

  /// Get maximum delta time
  double get maxDeltaTime => _maxDeltaTime;

  /// Set maximum delta time
  set maxDeltaTime(double value) {
    if (value <= 0) {
      throw ArgumentError('Max delta time must be positive');
    }
    _maxDeltaTime = value;
  }

  /// Get frames per second (based on delta time)
  double get fps => _deltaTime > 0 ? 1.0 / _deltaTime : 0.0;

  /// Get elapsed time since engine start
  double get elapsedTime {
    final now = DateTime.now();
    return now.difference(_startTime).inMicroseconds / 1000000.0;
  }

  /// Update the time manager (called by game loop)
  void update(double frameTime) {
    // Clamp frame time to max delta time
    _unscaledDeltaTime = frameTime.clamp(0.0, _maxDeltaTime);

    // Apply time scale
    _deltaTime = _unscaledDeltaTime * _timeScale;

    // Update total time
    _totalTime += _deltaTime;

    // Increment frame count
    _frameCount++;
  }

  /// Pause time (sets time scale to 0)
  void pause() {
    _timeScale = 0.0;
  }

  /// Resume time (sets time scale to 1)
  void resume() {
    _timeScale = 1.0;
  }

  /// Slow down time
  void slowMotion([double scale = 0.5]) {
    _timeScale = scale;
  }

  /// Speed up time
  void fastForward([double scale = 2.0]) {
    _timeScale = scale;
  }

  /// Reset time manager
  void reset() {
    _deltaTime = 0.0;
    _totalTime = 0.0;
    _timeScale = 1.0;
    _unscaledDeltaTime = 0.0;
    _frameCount = 0;
  }

  /// Get smooth delta time (exponential moving average)
  ///
  /// This provides a smoother delta time value that's less affected by
  /// individual frame spikes. Useful for camera movement and other
  /// time-sensitive operations that need to be smooth.
  double getSmoothDeltaTime([double smoothing = 0.1]) {
    // TODO: Implement exponential moving average
    return _deltaTime;
  }
}
