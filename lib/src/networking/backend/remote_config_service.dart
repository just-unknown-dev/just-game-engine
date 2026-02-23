/// Remote Config Service
///
/// Abstract interface and data models for remote configuration / LiveOps.
/// Implement [IRemoteConfigService] to pull game parameters from any backend
/// (Firebase Remote Config, LaunchDarkly, custom REST, etc.).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A snapshot of remote configuration values.
class RemoteConfig {
  /// The raw key-value store fetched from the backend.
  final Map<String, dynamic> _values;

  /// UTC timestamp when this config was fetched.
  final DateTime fetchedAt;

  RemoteConfig({Map<String, dynamic>? values, DateTime? fetchedAt})
    : _values = Map.unmodifiable(values ?? {}),
      fetchedAt = fetchedAt ?? DateTime.now().toUtc();

  /// Retrieve a value by [key], returning [defaultValue] if absent or
  /// if the stored value cannot be cast to [T].
  T getValue<T>(String key, T defaultValue) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  /// Return the entire config map as an unmodifiable copy.
  Map<String, dynamic> getAll() => Map.unmodifiable(_values);

  /// Whether [key] exists in this config snapshot.
  bool containsKey(String key) => _values.containsKey(key);

  @override
  String toString() =>
      'RemoteConfig(keys=${_values.keys.join(", ")}, fetchedAt=$fetchedAt)';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Backend-agnostic remote-config service.
///
/// Inject a concrete implementation to pull LiveOps configuration from
/// your preferred backend.
abstract class IRemoteConfigService {
  /// Stream that emits a new [RemoteConfig] whenever the backend config changes.
  Stream<RemoteConfig> get onConfigUpdated;

  /// Fetch the latest config from the backend. Must be called before
  /// [getValue] returns meaningful data.
  Future<RemoteConfig> fetch();

  /// Retrieve a typed value by [key] from the last fetched config.
  /// Returns [defaultValue] when the key is absent or the type mismatches.
  T getValue<T>(String key, T defaultValue);

  /// Return all config entries from the last fetch.
  Map<String, dynamic> getAll();

  /// Activate the fetched config so it becomes the active config used by
  /// [getValue]. Useful for backends that separate fetch from activate
  /// (e.g. Firebase Remote Config).
  Future<bool> activate();

  /// Fetch and immediately activate in one call.
  Future<RemoteConfig> fetchAndActivate();

  /// Register a callback for config updates (alternative to the stream API).
  void onUpdated(void Function(RemoteConfig config) callback);
}

// ---------------------------------------------------------------------------
// In-memory implementation
// ---------------------------------------------------------------------------

/// A local in-memory [IRemoteConfigService] for development and testing.
///
/// Seed it with default values using [setDefaults] and customise them by
/// calling [overrideValues] at runtime.
class LocalRemoteConfigService implements IRemoteConfigService {
  RemoteConfig _config = RemoteConfig();
  final _controller = StreamController<RemoteConfig>.broadcast();
  final List<void Function(RemoteConfig)> _listeners = [];

  @override
  Stream<RemoteConfig> get onConfigUpdated => _controller.stream;

  /// Seed the default configuration values. These are used until [fetch] or
  /// [override] is called.
  void setDefaults(Map<String, dynamic> defaults) {
    _config = RemoteConfig(values: {..._config.getAll(), ...defaults});
    debugPrint('LocalRemoteConfig: defaults set — ${defaults.keys.join(", ")}');
  }

  /// Programmatically override one or more config values at runtime.
  void overrideValues(Map<String, dynamic> values) {
    _config = RemoteConfig(values: {..._config.getAll(), ...values});
    _notify();
  }

  @override
  Future<RemoteConfig> fetch() async {
    debugPrint('LocalRemoteConfig: fetch() — returning in-memory config');
    return _config;
  }

  @override
  T getValue<T>(String key, T defaultValue) =>
      _config.getValue(key, defaultValue);

  @override
  Map<String, dynamic> getAll() => _config.getAll();

  @override
  Future<bool> activate() async {
    // In-memory config is always active.
    return true;
  }

  @override
  Future<RemoteConfig> fetchAndActivate() async => fetch();

  @override
  void onUpdated(void Function(RemoteConfig config) callback) {
    _listeners.add(callback);
  }

  void _notify() {
    _controller.add(_config);
    for (final cb in List.of(_listeners)) {
      cb(_config);
    }
  }

  /// Release all resources.
  void dispose() {
    _controller.close();
    _listeners.clear();
    debugPrint('LocalRemoteConfigService: disposed');
  }
}
