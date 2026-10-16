/// System Manager
///
/// Manages and coordinates all engine subsystems.
/// Provides system registration, retrieval, and lifecycle management.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'lifecycle.dart';

/// Callback used by the frame scheduler for update tasks.
typedef UpdateTask = void Function(double deltaTime);

/// Callback used by the frame scheduler for per-frame tasks: [deltaTime] is
/// the frame's length, [alpha] how far it lies between the last two fixed
/// updates.
typedef FrameTask = void Function(double deltaTime, double alpha);

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

  /// Ordered per-frame tasks, run after a frame's fixed updates.
  final Map<String, FrameTask> _frameTasks = {};
  final List<String> _frameOrder = <String>[];
  final Map<String, double> _lastTaskTimesMs = <String, double>{};
  double _lastFrameMs = 0.0;

  // Persistent Stopwatch instances — reused every frame to avoid heap allocation.
  final Stopwatch _frameStopwatch = Stopwatch();
  final Stopwatch _taskStopwatch = Stopwatch();

  // Persistent unmodifiable view of _lastTaskTimesMs — avoids per-call copy.
  late final UnmodifiableMapView<String, double> _unmodifiableTaskTimesView =
      UnmodifiableMapView(_lastTaskTimesMs);

  /// Whether [runUpdateCycle] times each task ([lastTaskTimesMs],
  /// [lastFrameMs]).
  ///
  /// On by default in debug and profile builds and off in release, where
  /// the stopwatch reads cost time for numbers nothing reads. Switched
  /// off, the timings stay empty and 0.
  bool profiling = !kReleaseMode;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Get the number of registered systems
  int get systemCount => _systems.length;

  /// Latest scheduler timing snapshot, made when read: `systemCount`,
  /// `updateTaskCount`, `lastFrameMs` and `taskTimesMs` (a live view of
  /// [lastTaskTimesMs]). The timings are measured only while [profiling].
  Map<String, dynamic> get schedulerStats => {
    'systemCount': _systems.length,
    'updateTaskCount': _updateOrder.length,
    'lastFrameMs': _lastFrameMs,
    'taskTimesMs': _unmodifiableTaskTimesView,
  };

  /// Latest task timings in milliseconds.
  ///
  /// Backed by a persistent [UnmodifiableMapView] — no copy on each access.
  UnmodifiableMapView<String, double> get lastTaskTimesMs =>
      _unmodifiableTaskTimesView;

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

  /// The declared type each name was registered under.
  final Map<String, Type> _typeByName = {};

  /// Register a system with the manager
  ///
  /// [name] - Unique name for the system
  /// [system] - System instance to register
  ///
  /// The system is keyed by its **declared** type [T] — the type argument,
  /// inferred from the static type of [system] when not given — not by its
  /// runtime type: `registerSystem<RenderingEngine>('rendering', custom)`
  /// is found by `getSystem<RenderingEngine>()` even when `custom` is a
  /// subclass.
  void registerSystem<T>(String name, T system) {
    if (_systems.containsKey(name)) {
      throw StateError('System with name "$name" is already registered');
    }

    _systems[name] = system;
    _systemsByType[T] = system;
    _typeByName[name] = T;

    if (kDebugMode) debugPrint('System registered: $name (${T.toString()})');
  }

  /// Unregister a system by name
  ///
  /// Returns true if the system was found and removed. Its typed entry goes
  /// with it — the one [registerSystem] made under the declared type — as
  /// long as that entry is still this system.
  bool unregisterSystem(String name) {
    if (!_systems.containsKey(name)) {
      return false;
    }

    final system = _systems.remove(name);
    final type = _typeByName.remove(name);
    if (type != null && identical(_systemsByType[type], system)) {
      _systemsByType.remove(type);
    }

    if (kDebugMode) debugPrint('System unregistered: $name');
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

  /// Register an ordered per-frame task (see [runFrameCycle]).
  void registerFrameTask(String name, FrameTask task) {
    if (_frameTasks.containsKey(name)) {
      throw StateError('Frame task with name "$name" is already registered');
    }
    _frameTasks[name] = task;
    _frameOrder.add(name);
  }

  /// Remove a per-frame task from the scheduler.
  bool unregisterFrameTask(String name) {
    final removed = _frameTasks.remove(name);
    _frameOrder.remove(name);
    return removed != null;
  }

  /// Runs every per-frame task once, in registration order: once per
  /// rendered frame, after its fixed updates.
  void runFrameCycle(double deltaTime, double alpha) {
    for (final name in _frameOrder) {
      _frameTasks[name]?.call(deltaTime, alpha);
    }
  }

  /// Execute one scheduled update cycle in registration order.
  void runUpdateCycle(double deltaTime) {
    if (_lastTaskTimesMs.isNotEmpty) _lastTaskTimesMs.clear();
    if (!profiling) {
      for (final name in _updateOrder) {
        _updateTasks[name]?.call(deltaTime);
      }
      _lastFrameMs = 0.0;
      return;
    }

    _frameStopwatch
      ..reset()
      ..start();

    for (final name in _updateOrder) {
      final task = _updateTasks[name];
      if (task == null) continue;

      _taskStopwatch
        ..reset()
        ..start();
      try {
        task(deltaTime);
      } finally {
        _taskStopwatch.stop();
        _lastTaskTimesMs[name] = _taskStopwatch.elapsedMicroseconds / 1000.0;
      }
    }

    _frameStopwatch.stop();
    _lastFrameMs = _frameStopwatch.elapsedMicroseconds / 1000.0;
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
    _typeByName.clear();
    _updateTasks.clear();
    _updateOrder.clear();
    _frameTasks.clear();
    _frameOrder.clear();
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
    if (kDebugMode) debugPrint('System manager disposed');
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
