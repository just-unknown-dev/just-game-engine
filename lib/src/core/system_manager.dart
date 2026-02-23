/// System Manager
///
/// Manages and coordinates all engine subsystems.
/// Provides system registration, retrieval, and lifecycle management.
library;

import 'package:flutter/foundation.dart';

import 'lifecycle.dart';

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

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Get the number of registered systems
  int get systemCount => _systems.length;

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
  }

  /// Dispose all systems and cleanup
  @override
  void dispose() {
    // Dispose systems that implement ILifecycle
    for (final system in _systems.values) {
      if (system is ILifecycle) {
        try {
          system.dispose();
        } catch (e) {
          debugPrint('Error disposing system: $e');
        }
      }
    }

    clear();
    _isInitialized = false;
    debugPrint('System manager disposed');
  }

  /// Print information about all registered systems
  void printSystemInfo() {
    debugPrint('=== Registered Systems ===');
    debugPrint('Total systems: ${_systems.length}');
    for (final entry in _systems.entries) {
      debugPrint('  - ${entry.key}: ${entry.value.runtimeType}');
    }
    debugPrint('========================');
  }
}
