/// System Manager
///
/// Manages and coordinates all engine subsystems.
/// Provides system registration, retrieval, and lifecycle management.
library;

import 'package:flutter/foundation.dart';

import 'lifecycle.dart';

/// Callback used by the frame scheduler for update tasks.
typedef UpdateTask = void Function(double deltaTime);

/// System manager for coordinating engine subsystems
///
/// This class acts as a registry for all engine subsystems, allowing
/// them to be accessed by name or type. It also manages their lifecycle.
///
/// Example usage:
/// ```dart
/// final systemManager = SystemManager();
/// systemManager.registerSystem('physics', physicsEngine);
/// final physics = systemManager.getSystem<PhysicsEngine>();
/// ```
class SystemManager implements ILifecycle {
  /// Map of system names to system instances
  final Map<String, dynamic> _systems = {};

  /// Map of system types to system instances
  final Map<Type, dynamic> _systemsByType = {};

  /// Whether the system manager is initialized
  bool _isInitialized = false;

  /// Ordered update tasks owned by the scheduler.
  final Map<String, UpdateTask> _updateTasks = {};
  final List<String> _updateOrder = <String>[];
  final Map<String, double> _lastTaskTimesMs = <String, double>{};
  double _lastFrameMs = 0.0;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Get the number of registered systems
  int get systemCount => _systems.length;

  /// Latest scheduler timing snapshot.
  Map<String, dynamic> get schedulerStats => {
    'systemCount': _systems.length,
    'updateTaskCount': _updateOrder.length,
    'lastFrameMs': _lastFrameMs,
    'taskTimesMs': Map<String, double>.unmodifiable(_lastTaskTimesMs),
  };

  /// Latest task timings in milliseconds.
  Map<String, double> get lastTaskTimesMs =>
      Map<String, double>.unmodifiable(_lastTaskTimesMs);

  /// Total scheduler frame time in milliseconds.
  double get lastFrameMs => _lastFrameMs;

  /// Initialize the system manager
  @override
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }

    _isInitialized = true;
    return true;
  }

  /// Register a system with the manager
  ///
  /// [name] - Unique name for the system
  /// [system] - System instance to register
  void registerSystem<T>(String name, T system) {
    if (_systems.containsKey(name)) {
      throw StateError('System with name "$name" is already registered');
    }

    _systems[name] = system;
    _systemsByType[T] = system;

    debugPrint('System registered: $name (${T.toString()})');
  }

  /// Unregister a system by name
  ///
  /// Returns true if the system was found and removed.
  bool unregisterSystem(String name) {
    if (!_systems.containsKey(name)) {
      return false;
    }

    final system = _systems[name];
    _systems.remove(name);
    _systemsByType.remove(system.runtimeType);

    debugPrint('System unregistered: $name');
    return true;
  }

  /// Get a system by name
  ///
  /// Returns null if the system is not found.
  dynamic getSystemByName(String name) {
    return _systems[name];
  }

  /// Get a system by type
  ///
  /// Returns null if the system is not found.
  T? getSystem<T>() {
    return _systemsByType[T] as T?;
  }

  /// Check if a system is registered by name
  bool hasSystem(String name) {
    return _systems.containsKey(name);
  }

  /// Check if a system type is registered
  bool hasSystemOfType<T>() {
    return _systemsByType.containsKey(T);
  }

  /// Register an ordered frame update task.
  void registerUpdateTask(String name, UpdateTask task) {
    if (_updateTasks.containsKey(name)) {
      throw StateError('Update task with name "$name" is already registered');
    }

    _updateTasks[name] = task;
    _updateOrder.add(name);
  }

  /// Remove an update task from the scheduler.
  bool unregisterUpdateTask(String name) {
    final removed = _updateTasks.remove(name);
    _updateOrder.remove(name);
    return removed != null;
  }

  /// Execute one scheduled update cycle in registration order.
  void runUpdateCycle(double deltaTime) {
    final frameStopwatch = Stopwatch()..start();
    final taskStopwatch = Stopwatch();
    _lastTaskTimesMs.clear();

    for (final name in _updateOrder) {
      final task = _updateTasks[name];
      if (task == null) continue;

      taskStopwatch
        ..reset()
        ..start();
      try {
        task(deltaTime);
      } finally {
        taskStopwatch.stop();
        _lastTaskTimesMs[name] = taskStopwatch.elapsedMicroseconds / 1000.0;
      }
    }

    frameStopwatch.stop();
    _lastFrameMs = frameStopwatch.elapsedMicroseconds / 1000.0;
  }

  /// Get all registered system names
  List<String> getSystemNames() {
    return _systems.keys.toList();
  }

  /// Get all registered systems
  List<dynamic> getSystems() {
    return _systems.values.toList();
  }

  /// Clear all registered systems
  void clear() {
    _systems.clear();
    _systemsByType.clear();
    _updateTasks.clear();
    _updateOrder.clear();
    _lastTaskTimesMs.clear();
    _lastFrameMs = 0.0;
  }

  /// Dispose the registry/scheduler state.
  ///
  /// Concrete subsystem lifecycle is owned by the `Engine`, which prevents
  /// accidental double-disposal when the engine shuts down.
  @override
  void dispose() {
    clear();
    _isInitialized = false;
    debugPrint('System manager disposed');
  }

  /// Print information about all registered systems
  void printSystemInfo() {
    debugPrint('=== Registered Systems ===');
    debugPrint('Total systems: ${_systems.length}');
    debugPrint('Scheduled update tasks: ${_updateOrder.length}');
    for (final entry in _systems.entries) {
      debugPrint('  - ${entry.key}: ${entry.value.runtimeType}');
    }
    if (_updateOrder.isNotEmpty) {
      debugPrint('Update order: ${_updateOrder.join(' -> ')}');
    }
    debugPrint('========================');
  }
}
