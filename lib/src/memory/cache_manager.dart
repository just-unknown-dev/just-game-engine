import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_database/just_database.dart';

/// Validate and sanitize a cache key.
///
/// Keys must be non-empty, printable-ASCII-only strings no longer than 512
/// characters. This prevents SQL injection by rejecting keys with special
/// characters rather than trying to escape them.
final RegExp _validKeyPattern = RegExp(r'^[a-zA-Z0-9_.\-/]{1,512}$');

String _validateKey(String key) {
  if (!_validKeyPattern.hasMatch(key)) {
    throw ArgumentError(
      'Invalid cache key: keys must be 1-512 alphanumeric/underscore/dash/dot/slash characters.',
    );
  }
  return key;
}

/// Escape a value for inclusion in a single-quoted SQL string literal.
///
/// Doubles single quotes (standard SQL escaping), strips null bytes, and
/// escapes backslashes to prevent truncation or escape-sequence attacks.
String _sqlEscape(String value) {
  return value
      .replaceAll('\x00', '')
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "''");
}

/// Manages caching of various game resources.
///
/// The binary cache supports optional LRU eviction via [maxBinaryEntries].
/// When the limit is reached, the oldest entries (by timestamp) are removed
/// to make room for new ones.
class CacheManager {
  JustStandardStorage? _keyValueCache;
  JustDatabase? _databaseCache;
  bool _initialized = false;
  bool _memoryFallback = false;

  final Map<String, String> _memoryStringCache = <String, String>{};
  final Map<String, Uint8List> _memoryBinaryCache = <String, Uint8List>{};

  /// Maximum number of entries in the binary cache before LRU eviction.
  /// `null` means unbounded (default for backward compatibility).
  final int? maxBinaryEntries;

  /// Create a cache manager.
  ///
  /// [maxBinaryEntries] — optional upper bound on binary cache rows.
  CacheManager({this.maxBinaryEntries});

  /// Check if cache manager is initialized
  bool get isInitialized => _initialized;

  /// Whether the cache is running in headless/test memory-only mode.
  bool get isUsingMemoryFallback => _memoryFallback;

  /// Initialize the caching system
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('Initializing CacheManager...');

    try {
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

      _memoryFallback = false;
      _initialized = true;
      debugPrint('CacheManager initialized successfully.');
    } catch (e) {
      _keyValueCache = null;
      _databaseCache = null;
      _memoryFallback = true;
      _initialized = true;
      debugPrint('CacheManager fallback to in-memory storage: $e');
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
    if (!_initialized) return;

    if (_memoryFallback || _keyValueCache == null) {
      _memoryStringCache[key] = value;
      return;
    }

    try {
      await _keyValueCache!.write(key, value);
    } catch (e) {
      debugPrint('Error setting string in cache: $e');
      _memoryStringCache[key] = value;
    }
  }

  /// Retrieve a string value
  Future<String?> getString(String key) async {
    if (!_initialized) return null;

    if (_memoryFallback || _keyValueCache == null) {
      return _memoryStringCache[key];
    }

    try {
      return await _keyValueCache!.read(key);
    } catch (e) {
      debugPrint('Error getting string from cache: $e');
      return _memoryStringCache[key];
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
    if (!_initialized) return;

    final validKey = _validateKey(key);
    if (_memoryFallback || _databaseCache == null) {
      _memoryBinaryCache[validKey] = Uint8List.fromList(data);
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encodedStr = base64Encode(data);
      final safeKey = _sqlEscape(validKey);

      await _databaseCache!.execute(
        "DELETE FROM binary_cache WHERE key = '$safeKey'",
      );

      await _databaseCache!.execute(
        "INSERT INTO binary_cache (key, data, timestamp) "
        "VALUES ('$safeKey', '$encodedStr', $timestamp)",
      );

      // LRU eviction: remove oldest entries if over the limit.
      if (maxBinaryEntries != null) {
        await _evictOldestBinaryEntries();
      }
    } catch (e) {
      debugPrint('Error setting binary data in database cache: $e');
      _memoryBinaryCache[validKey] = Uint8List.fromList(data);
    }
  }

  /// Retrieve binary data
  Future<Uint8List?> getBinary(String key) async {
    if (!_initialized) return null;

    final validKey = _validateKey(key);
    if (_memoryFallback || _databaseCache == null) {
      return _memoryBinaryCache[validKey];
    }

    try {
      final safeKey = _sqlEscape(validKey);
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
    return _memoryBinaryCache[validKey];
  }

  /// Clear a specific cache entry (from both storages for simplicity)
  Future<void> remove(String key) async {
    if (!_initialized) return;
    try {
      _memoryStringCache.remove(key);
      _memoryBinaryCache.remove(key);

      if (_keyValueCache != null) {
        await _keyValueCache!.delete(key);
      }
      if (_databaseCache != null) {
        final validKey = _validateKey(key);
        final safeKey = _sqlEscape(validKey);
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
      _memoryStringCache.clear();
      _memoryBinaryCache.clear();

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
    _memoryStringCache.clear();
    _memoryBinaryCache.clear();

    // _keyValueCache does not have a formal dispose
    if (_databaseCache != null) {
      _databaseCache!.close();
    }
    _databaseCache = null;
    _keyValueCache = null;
    _memoryFallback = false;
    _initialized = false;
  }

  /// Return the number of entries in the binary cache.
  Future<int> getBinaryCacheSize() async {
    if (!_initialized) return 0;
    if (_memoryFallback || _databaseCache == null) {
      return _memoryBinaryCache.length;
    }
    try {
      final result = await _databaseCache!.query(
        'SELECT COUNT(*) as cnt FROM binary_cache',
      );
      if (result.rows.isNotEmpty) {
        return (result.rows.first['cnt'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('Error getting binary cache size: $e');
    }
    return _memoryBinaryCache.length;
  }

  /// Remove the oldest binary cache entries to stay within [maxBinaryEntries].
  Future<void> _evictOldestBinaryEntries() async {
    if (_databaseCache == null || maxBinaryEntries == null) return;
    try {
      final count = await getBinaryCacheSize();
      if (count <= maxBinaryEntries!) return;
      final excess = count - maxBinaryEntries!;
      await _databaseCache!.execute(
        'DELETE FROM binary_cache WHERE key IN '
        '(SELECT key FROM binary_cache ORDER BY timestamp ASC LIMIT $excess)',
      );
    } catch (e) {
      debugPrint('Error evicting binary cache entries: $e');
    }
  }
}
