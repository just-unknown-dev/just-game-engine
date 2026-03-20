/// Cache Management
///
/// Implements caching for game assets and data using just_storage and just_database.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_database/just_database.dart';

/// Manages caching of various game resources.
class CacheManager {
  JustStandardStorage? _keyValueCache;
  JustDatabase? _databaseCache;
  bool _initialized = false;

  /// Check if cache manager is initialized
  bool get isInitialized => _initialized;

  /// Initialize the caching system
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('Initializing CacheManager...');

      // Initialize fast key-value storage
      _keyValueCache = await JustStorage.standard();

      // Initialize structured database storage for heavier data
      // For now, using standard database mode.
      _databaseCache = await JustDatabase.open(
        'just_game_engine_cache',
        mode: DatabaseMode.writeFast,
      );

      // Create necessary tables if they don't exist
      await _initDatabaseSchema();

      _initialized = true;
      debugPrint('CacheManager initialized successfully.');
    } catch (e) {
      debugPrint('Error initializing CacheManager: $e');
    }
  }

  Future<void> _initDatabaseSchema() async {
    if (_databaseCache == null) return;
    try {
      await _databaseCache!.execute('''
        CREATE TABLE IF NOT EXISTS binary_cache (
          key TEXT PRIMARY KEY,
          data BLOB,
          timestamp INTEGER
        );
      ''');
    } catch (e) {
      debugPrint('Error creating binary_cache table: $e');
    }
  }

  /// Store a string value
  Future<void> setString(String key, String value) async {
    if (!_initialized || _keyValueCache == null) return;
    try {
      await _keyValueCache!.write(key, value);
    } catch (e) {
      debugPrint('Error setting string in cache: $e');
    }
  }

  /// Retrieve a string value
  Future<String?> getString(String key) async {
    if (!_initialized || _keyValueCache == null) return null;
    try {
      return await _keyValueCache!.read(key);
    } catch (e) {
      debugPrint('Error getting string from cache: $e');
      return null;
    }
  }

  /// Store JSON data
  Future<void> setJson(String key, dynamic data) async {
    try {
      final jsonString = jsonEncode(data);
      await setString(key, jsonString);
    } catch (e) {
      debugPrint('Error setting JSON in cache: $e');
    }
  }

  /// Retrieve JSON data
  Future<dynamic> getJson(String key) async {
    try {
      final jsonString = await getString(key);
      if (jsonString != null) {
        return jsonDecode(jsonString);
      }
    } catch (e) {
      debugPrint('Error getting JSON from cache: $e');
    }
    return null;
  }

  /// Store binary data
  Future<void> setBinary(String key, Uint8List data) async {
    if (!_initialized || _databaseCache == null) return;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encodedStr = base64Encode(data);
      final safeKey = key.replaceAll("'", "''");

      await _databaseCache!.execute(
        "DELETE FROM binary_cache WHERE key = '$safeKey'",
      );

      await _databaseCache!.execute(
        "INSERT INTO binary_cache (key, data, timestamp) "
        "VALUES ('$safeKey', '$encodedStr', $timestamp)",
      );
    } catch (e) {
      debugPrint('Error setting binary data in database cache: $e');
    }
  }

  /// Retrieve binary data
  Future<Uint8List?> getBinary(String key) async {
    if (!_initialized || _databaseCache == null) return null;
    try {
      final safeKey = key.replaceAll("'", "''");
      final result = await _databaseCache!.query(
        "SELECT data FROM binary_cache WHERE key = '$safeKey'",
      );
      if (result.rows.isNotEmpty) {
        final dataStr = result.rows.first['data'];
        if (dataStr is String) {
          return base64Decode(dataStr);
        }
      }
    } catch (e) {
      debugPrint('Error getting binary data from database cache: $e');
    }
    return null;
  }

  /// Clear a specific cache entry (from both storages for simplicity)
  Future<void> remove(String key) async {
    if (!_initialized) return;
    try {
      if (_keyValueCache != null) {
        await _keyValueCache!.delete(key);
      }
      if (_databaseCache != null) {
        final safeKey = key.replaceAll("'", "''");
        await _databaseCache!.execute(
          "DELETE FROM binary_cache WHERE key = '$safeKey'",
        );
      }
    } catch (e) {
      debugPrint('Error removing cache entry $key: $e');
    }
  }

  /// Clear all cache entries
  Future<void> clearAll() async {
    if (!_initialized) return;
    try {
      if (_keyValueCache != null) {
        await _keyValueCache!.clear();
      }
      if (_databaseCache != null) {
        await _databaseCache!.execute('DELETE FROM binary_cache');
      }
      debugPrint('Cache cleared.');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Dispose of the cache manager and close resources
  void dispose() {
    if (!_initialized) return;
    // _keyValueCache does not have a formal dispose
    if (_databaseCache != null) {
      _databaseCache!.close();
    }
    _initialized = false;
  }
}
