/// Lifecycle Interface
///
/// Defines the standard lifecycle interface for engine systems.
/// All major systems should implement this interface for consistent management.
library;

/// Interface for objects with lifecycle management
///
/// This interface defines the standard lifecycle methods that all major
/// engine systems should implement. This ensures consistent initialization
/// and cleanup across the engine.
///
/// Example implementation:
/// ```dart
/// class MySystem implements ILifecycle {
///   @override
///   Future<bool> initialize() async {
///     // Initialize resources
///     return true;
///   }
///
///   @override
///   void dispose() {
///     // Clean up resources
///   }
/// }
/// ```
abstract class ILifecycle {
  /// Initialize the system
  ///
  /// This method should be called before using the system.
  /// Returns true if initialization was successful, false otherwise.
  Future<bool> initialize();

  /// Dispose of system resources
  ///
  /// This method should clean up all resources used by the system.
  /// After calling dispose, the system should not be used anymore.
  void dispose();
}

/// Interface for systems that can be updated every frame
///
/// Systems that need to perform per-frame updates should implement this interface.
abstract class IUpdatable {
  /// Update the system
  ///
  /// [deltaTime] - Time elapsed since last update in seconds
  void update(double deltaTime);
}

/// Interface for systems that can be rendered
///
/// Systems that need to render visuals should implement this interface.
abstract class IRenderable {
  /// Render the system
  void render();
}

/// Interface for systems that can be paused
///
/// Systems that support pausing should implement this interface.
abstract class IPausable {
  /// Pause the system
  void pause();

  /// Resume the system
  void resume();

  /// Check if the system is paused
  bool get isPaused;
}

/// Interface for systems that can be enabled/disabled
///
/// Systems that can be toggled on and off should implement this interface.
abstract class IEnableable {
  /// Enable the system
  void enable();

  /// Disable the system
  void disable();

  /// Check if the system is enabled
  bool get isEnabled;
}

/// Mixin for adding lifecycle state tracking
///
/// This mixin provides common state tracking for lifecycle management.
mixin LifecycleStateMixin {
  /// Whether the object is initialized
  bool _isInitialized = false;

  /// Whether the object is disposed
  bool _isDisposed = false;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Check if disposed
  bool get isDisposed => _isDisposed;

  /// Mark as initialized
  void markInitialized() {
    _isInitialized = true;
    _isDisposed = false;
  }

  /// Mark as disposed
  void markDisposed() {
    _isDisposed = true;
    _isInitialized = false;
  }

  /// Ensure the object is initialized
  void ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Object must be initialized before use');
    }
  }

  /// Ensure the object is not disposed
  void ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Object has been disposed and cannot be used');
    }
  }
}
