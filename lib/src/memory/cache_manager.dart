import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:just_database/just_database.dart';
import 'package:just_memory/just_memory.dart';
import 'package:just_storage/just_storage.dart';

import 'engine_storage.dart' as engine_storage;

/// The longest key the binary table stores as it is, once encoded. A longer
/// key keeps this much of its start, ending in a hash of the whole key.
const int _maxEncodedKeyLength = 512;

/// Whether [unit] stays as it is in an encoded key: letters, digits and
/// `_ . - /` — every character a key could hold before 2.0.
bool _isPlainKeyUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) || // 0-9
    (unit >= 0x41 && unit <= 0x5A) || // A-Z
    (unit >= 0x61 && unit <= 0x7A) || // a-z
    unit == 0x5F || // _
    unit == 0x2E || // .
    unit == 0x2D || // -
    unit == 0x2F; // /

/// Turns any cache key into one that is safe inside a single-quoted SQL
/// literal, which is how the binary table is addressed.
///
/// Letters, digits and `_ . - /` are kept, so a key the cache accepted before
/// 2.0 maps to itself and still finds its row. Anything else — a space, `@`,
/// `+`, a bracket, a quote, an accented letter — becomes `%XX` for each of
/// its UTF-8 bytes (a `%` too, so no two keys meet). A key still longer than
/// [_maxEncodedKeyLength] keeps its start and ends in `#` and a hash of the
/// whole key, so two long keys sharing a start stay apart.
///
/// Keys used to be checked against that short list instead and rejected with
/// an [ArgumentError] — thrown outside any `try`, so an asset named
/// `Player Idle.png` failed to load.
String _encodeKey(String key) {
  var encoded = key;
  if (!key.codeUnits.every(_isPlainKeyUnit)) {
    final out = StringBuffer();
    for (final byte in utf8.encode(key)) {
      if (_isPlainKeyUnit(byte)) {
        out.writeCharCode(byte);
      } else {
        out
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    encoded = out.toString();
  }
  if (encoded.length <= _maxEncodedKeyLength) return encoded;
  final hash = _keyHash(key);
  return '${encoded.substring(0, _maxEncodedKeyLength - hash.length - 1)}'
      '#$hash';
}

/// 64 bits of hash over [key]'s UTF-8 bytes, as 16 hex digits: two 32-bit
/// FNV-1a passes from different starting points. Stable across runs and
/// platforms, which `String.hashCode` is not — the key is stored on disk.
String _keyHash(String key) {
  var a = 0x811C9DC5;
  var b = 0x01000193 ^ 0x9E3779B9;
  for (final byte in utf8.encode(key)) {
    a = _fnvStep(a, byte);
    b = _fnvStep(b, byte);
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

/// One FNV-1a step, kept to 32 bits in pieces small enough that the web's
/// 53-bit integers multiply them exactly.
int _fnvStep(int hash, int byte) {
  final h = (hash ^ byte) & 0xFFFFFFFF;
  const prime = 0x01000193;
  final low = (h & 0xFFFF) * prime;
  final high = (((h >>> 16) * prime) & 0xFFFF) << 16;
  return (low + high) & 0xFFFFFFFF;
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
/// Strings and JSON go to the engine's own key-value store, binary data to
/// the engine's own database. On desktop and mobile the key-value store is
/// a file of its own, `just_game_engine/just_storage.json` in the app's
/// support directory — not the `just_storage.json` app code opens with
/// [JustStorage.standard], because `just_storage` rewrites a whole file from
/// the copy each instance loaded, and two instances on one file drop each
/// other's keys. On the web it is browser storage under the engine's own key
/// prefix. Everything the cache writes sits under [keyPrefix], so [clearAll]
/// removes only the cache's own entries — never the engine settings kept
/// beside them (such as players' key bindings).
///
/// Before 2.0 the engine wrote into the app's `just_storage.json`. The first
/// run moves what it left there — its prefixed entries, and players'
/// bindings saved before 2.0 — into its own store, and removes them and any
/// pre-2.0 copies of bundle assets from the app's file. Nothing else there
/// is touched.
///
/// When a store cannot be opened or stops accepting writes, the entries it
/// should have held are kept in memory for the rest of the run instead.
///
/// Assets from the app's bundle are not cached here: the bundle is already
/// on the device, and a copy kept across runs outlived the asset it was
/// made from — an update shipping a new image went on drawing the old one.
///
/// The binary cache supports optional eviction via [maxBinaryEntries]. When
/// the limit is reached, the oldest entries (by write time) are removed to
/// make room for new ones.
class CacheManager {
  JustStandardStorage? _keyValueCache;
  JustDatabase? _databaseCache;
  bool _initialized = false;
  bool _memoryFallback = false;

  /// Entries a store should hold but does not — it is unavailable, or the
  /// write to it failed. Read before the store, so a failed write is not
  /// followed by a read of the stale value underneath.
  final BudgetedCache<String, String> _memoryStringCache;
  final BudgetedCache<String, Uint8List> _memoryBinaryCache;

  /// Engine settings, when the key-value store is unavailable. Kept apart
  /// from [_memoryStringCache] because [clearAll] leaves settings alone.
  final Map<String, String> _memorySettings = {};

  late final MemoryProfiler _profiler;

  /// Prefix of every key the cache writes into the app's key-value store.
  static const String keyPrefix = 'just_game_engine.cache/';

  /// Prefix of the engine settings kept in the same store, which [clearAll]
  /// leaves alone.
  static const String _settingsPrefix = 'just_game_engine.settings/';

  /// Marks a store whose pre-2.0 leftovers have been dealt with.
  static const String _storageVersionKey =
      'just_game_engine.meta/storage_version';
  static const String _storageVersion = '2';

  /// Marks the engine's own store once the engine's entries have been moved
  /// out of the store it shared with the app.
  static const String _movedOutKey = 'just_game_engine.meta/shared_store';
  static const String _movedOut = 'moved';

  /// What the engine wrote into the shared store under its own prefixes.
  static const List<String> _ownPrefixes = [
    keyPrefix,
    _settingsPrefix,
    'just_game_engine.meta/',
  ];

  /// Settings the engine wrote without a prefix before 2.0: players' key
  /// bindings (`input.overrides.<asset>.p<n>`, by `CacheInputOverrideStore`).
  /// Moved under [_settingsPrefix], as [readSetting] adopts them.
  static const String _legacyBindingsPrefix = 'input.overrides.';

  static const String _defaultDatabaseName = 'just_game_engine_cache';

  /// Maximum number of entries in the binary cache before eviction.
  /// `null` means effectively unbounded in in-memory fallback mode.
  final int? maxBinaryEntries;

  /// Forces the cache to use only the shared in-memory fast path.
  final bool forceMemoryFallback;

  final Future<JustStandardStorage> Function()? _openStorage;
  final Future<JustDatabase> Function()? _openDatabase;
  final Future<JustStandardStorage?> Function()? _openSharedStorage;

  /// Create a cache manager.
  ///
  /// [maxBinaryEntries] — optional upper bound on binary cache rows.
  /// [forceMemoryFallback] — bypasses platform storage and uses only the
  /// shared in-memory cache layer.
  /// [openStorage] / [openDatabase] — open the key-value store and the
  /// binary database somewhere other than the platform defaults (a test's
  /// temporary folder, an in-memory database).
  /// [openSharedStorage] — the store the engine shared with the app before
  /// 2.0, which the engine's entries are moved out of on the first run. It
  /// defaults to [JustStorage.standard] when [openStorage] is not given, and
  /// to none (nothing moved) when it is.
  CacheManager({
    this.maxBinaryEntries,
    this.forceMemoryFallback = false,
    Future<JustStandardStorage> Function()? openStorage,
    Future<JustDatabase> Function()? openDatabase,
    Future<JustStandardStorage?> Function()? openSharedStorage,
  }) : _openStorage = openStorage,
       _openDatabase = openDatabase,
       _openSharedStorage =
           openSharedStorage ??
           (openStorage == null ? engine_storage.openSharedStorage : null),
       _memoryStringCache = BudgetedCache<String, String>(
         maxCost: 4096,
         estimateCost: (key, value) => 1,
       ),
       _memoryBinaryCache = BudgetedCache<String, Uint8List>(
         maxCost: maxBinaryEntries ?? (1 << 20),
         estimateCost: (key, value) => 1,
       ) {
    _profiler = MemoryProfiler()
      ..trackCache('cache.strings', _memoryStringCache)
      ..trackCache('cache.binary', _memoryBinaryCache);
  }

  /// Check if cache manager is initialized
  bool get isInitialized => _initialized;

  /// Whether the cache is running in headless/test memory-only mode.
  bool get isUsingMemoryFallback => _memoryFallback;

  /// Whether binary data is kept in memory only — the database could not be
  /// opened or set up — while strings may still reach the key-value store.
  bool get isBinaryInMemory => _initialized && _databaseCache == null;

  /// Initialize the caching system
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('Initializing CacheManager...');

    if (forceMemoryFallback) {
      _memoryFallback = true;
      _initialized = true;
      debugPrint('CacheManager using forced in-memory fallback.');
      return;
    }

    // Fast key-value storage. Without it there is no app storage at all on
    // this platform (tests, a headless run): everything stays in memory.
    try {
      _keyValueCache =
          await (_openStorage?.call() ?? engine_storage.openEngineStorage());
    } catch (e) {
      _keyValueCache = null;
      _memoryFallback = true;
      _initialized = true;
      debugPrint('CacheManager fallback to in-memory storage: $e');
      return;
    }

    // Structured database storage for binary data. Opened on its own: a
    // database that fails leaves the working key-value store in place, so
    // strings — and the settings beside them — still persist.
    try {
      _databaseCache =
          await (_openDatabase?.call() ??
              JustDatabase.open(
                _defaultDatabaseName,
                mode: DatabaseMode.writeFast,
              ));
      await _initDatabaseSchema();
    } catch (e) {
      _dropDatabase('could not be opened ($e)');
    }

    _memoryFallback = false;
    _initialized = true;
    await _moveOutOfSharedStore();
    await _forgetLegacyAssetCopies();
    debugPrint('CacheManager initialized successfully.');
  }

  /// Moves what the engine left in the store it shared with the app before
  /// 2.0 into its own store, and removes it from the shared one — once:
  /// afterwards the shared store is never opened again.
  ///
  /// Moved: every key under the engine's prefixes, and players' bindings
  /// saved without one ([_legacyBindingsPrefix]). A key the engine's own
  /// store already has keeps its value there (it is the newer); the shared
  /// copy is removed all the same. Removed without moving: copies of bundle
  /// assets made before 2.0 (see [_forgetLegacyAssetCopies]), unless the
  /// shared store says they were cleared already. Every other key — the
  /// app's — is left as it is.
  ///
  /// The shared store is opened, read and written in one go and let go of,
  /// so the engine never holds a copy of the app's file that could go
  /// stale. A step that fails is logged and the whole move tried again next
  /// run; it is safe to repeat.
  Future<void> _moveOutOfSharedStore() async {
    final own = _keyValueCache;
    final open = _openSharedStorage;
    if (own == null || open == null) return;
    try {
      if (await own.read(_movedOutKey) == _movedOut) return;
      final shared = await open();
      if (shared != null && !identical(shared, own)) {
        final entries = await shared.readAll();

        // Prefixed keys first, so a binding already adopted (under the
        // settings prefix) wins over a bare copy of it.
        final prefixed = <String>[];
        final bare = <String>[];
        for (final key in entries.keys) {
          if (_ownPrefixes.any(key.startsWith)) {
            prefixed.add(key);
          } else if (key.startsWith(_legacyBindingsPrefix)) {
            bare.add(key);
          }
        }
        for (final key in prefixed) {
          await _moveEntry(shared, own, key, key, entries[key]!);
        }
        for (final key in bare) {
          await _moveEntry(
            shared,
            own,
            key,
            '$_settingsPrefix$key',
            entries[key]!,
          );
        }

        if (entries[_storageVersionKey] != _storageVersion) {
          final assets = (await AssetManifest.loadFromAssetBundle(
            rootBundle,
          )).listAssets().toSet();
          for (final key in entries.keys) {
            if (assets.contains(key)) await shared.delete(key);
          }
        }
      }
      await own.write(_movedOutKey, _movedOut);
    } catch (e) {
      debugPrint(
        'CacheManager: could not move entries out of the shared store ($e) '
        '— tried again next run',
      );
    }
  }

  /// [key] from [shared] to [into] under [ownKey], unless [into] has it.
  static Future<void> _moveEntry(
    JustStandardStorage shared,
    JustStandardStorage into,
    String key,
    String ownKey,
    String value,
  ) async {
    if (!await into.containsKey(ownKey)) await into.write(ownKey, value);
    await shared.delete(key);
  }

  /// Creates the binary table, or gives up on the database — logged — when
  /// that fails, so binary data is kept in memory rather than written to a
  /// table that does not exist.
  Future<void> _initDatabaseSchema() async {
    final db = _databaseCache;
    if (db == null) return;
    final result = await db.execute('''
        CREATE TABLE IF NOT EXISTS binary_cache (
          key TEXT PRIMARY KEY,
          data BLOB,
          timestamp INTEGER
        );
      ''');
    if (!result.success) {
      _dropDatabase('has no binary_cache table (${result.errorMessage})');
    }
  }

  void _dropDatabase(String reason) {
    final db = _databaseCache;
    _databaseCache = null;
    debugPrint(
      'CacheManager: the binary cache database $reason — binary data is '
      'kept in memory for this run.',
    );
    if (db != null && db.isOpen) {
      unawaited(
        db.close().catchError((Object e) {
          debugPrint('CacheManager: closing the database failed ($e)');
        }),
      );
    }
  }

  /// Before 2.0 every text, JSON, image, audio and binary asset loaded was
  /// copied into the cache under its asset path, and read back from there
  /// on the next run in preference to the bundle. Nothing reads those copies
  /// now; this removes them once, so they stop weighing down the store —
  /// which is read whole at startup and rewritten whole on every write.
  ///
  /// Only entries named exactly like an asset in this app's bundle go, so
  /// the app's own keys are safe.
  Future<void> _forgetLegacyAssetCopies() async {
    final store = _keyValueCache;
    if (store == null) return;
    try {
      if (await store.read(_storageVersionKey) == _storageVersion) return;
      final assets = (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets().toSet();

      final entries = await store.readAll();
      for (final key in entries.keys) {
        if (assets.contains(key)) await store.delete(key);
      }

      final db = _databaseCache;
      if (db != null) {
        final rows = await db.query('SELECT key FROM binary_cache');
        for (final row in rows.rows) {
          final key = row['key'];
          if (key is String && assets.contains(key)) {
            await db.execute(
              "DELETE FROM binary_cache WHERE key = '${_sqlEscape(key)}'",
            );
          }
        }
      }

      await store.write(_storageVersionKey, _storageVersion);
    } catch (e) {
      // Tried again next run; nothing depends on it meanwhile.
      debugPrint('CacheManager: could not clear pre-2.0 asset copies ($e)');
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
      await _keyValueCache!.write('$keyPrefix$key', value);
      _memoryStringCache.remove(key);
    } catch (e) {
      debugPrint('Error setting string in cache: $e');
      _memoryStringCache[key] = value;
    }
  }

  /// Retrieve a string value
  Future<String?> getString(String key) async {
    if (!_initialized) return null;

    final pending = _memoryStringCache[key];
    if (pending != null) return pending;
    if (_memoryFallback || _keyValueCache == null) return null;

    try {
      return await _keyValueCache!.read('$keyPrefix$key');
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

  /// Store binary data.
  ///
  /// Any string is a valid [key]: it is encoded before it reaches the
  /// database, so spaces, symbols and non-ASCII letters are all fine.
  Future<void> setBinary(String key, Uint8List data) async {
    if (!_initialized) return;

    final db = _databaseCache;
    if (_memoryFallback || db == null) {
      _memoryBinaryCache[key] = Uint8List.fromList(data);
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encodedStr = base64Encode(data);
      final safeKey = _sqlEscape(_encodeKey(key));

      await db.execute("DELETE FROM binary_cache WHERE key = '$safeKey'");

      final inserted = await db.execute(
        "INSERT INTO binary_cache (key, data, timestamp) "
        "VALUES ('$safeKey', '$encodedStr', $timestamp)",
      );
      if (!inserted.success) {
        throw StateError(inserted.errorMessage ?? 'insert failed');
      }
      _memoryBinaryCache.remove(key);

      // Eviction: remove oldest entries if over the limit.
      if (maxBinaryEntries != null) {
        await _evictOldestBinaryEntries();
      }
    } catch (e) {
      debugPrint('Error setting binary data in database cache: $e');
      _memoryBinaryCache[key] = Uint8List.fromList(data);
    }
  }

  /// Retrieve binary data
  Future<Uint8List?> getBinary(String key) async {
    if (!_initialized) return null;

    final pending = _memoryBinaryCache[key];
    if (pending != null) return pending;
    final db = _databaseCache;
    if (_memoryFallback || db == null) return null;

    try {
      final safeKey = _sqlEscape(_encodeKey(key));
      final result = await db.query(
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
      _memoryStringCache.remove(key);
      _memoryBinaryCache.remove(key);

      if (_keyValueCache != null) {
        await _keyValueCache!.delete('$keyPrefix$key');
      }
      if (_databaseCache != null) {
        final safeKey = _sqlEscape(_encodeKey(key));
        await _databaseCache!.execute(
          "DELETE FROM binary_cache WHERE key = '$safeKey'",
        );
      }
    } catch (e) {
      debugPrint('Error removing cache entry $key: $e');
    }
  }

  /// Clear all cache entries.
  ///
  /// Only the cache's own: the rest of the app's key-value store — including
  /// engine settings such as players' key bindings — is left as it is.
  Future<void> clearAll() async {
    if (!_initialized) return;
    try {
      _memoryStringCache.clear();
      _memoryBinaryCache.clear();

      final store = _keyValueCache;
      if (store != null) {
        final entries = await store.readAll();
        for (final key in entries.keys) {
          if (key.startsWith(keyPrefix)) await store.delete(key);
        }
      }
      if (_databaseCache != null) {
        await _databaseCache!.execute('DELETE FROM binary_cache');
      }
      debugPrint('Cache cleared.');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  // ── Engine settings ─────────────────────────────────────────────────────

  /// Reads the engine setting [key]: kept in the same store as the cache,
  /// but under its own prefix, which [clearAll] never touches.
  ///
  /// With [adoptLegacy], a value saved before 2.0 — when settings shared the
  /// cache's keys, and [clearAll] erased them — is moved across the first
  /// time it is read. (Bindings left in the app's store are moved when the
  /// cache is initialized; this finds one in the engine's own store.)
  @internal
  Future<String?> readSetting(String key, {bool adoptLegacy = false}) async {
    if (!_initialized) return null;
    final store = _keyValueCache;
    if (_memoryFallback || store == null) return _memorySettings[key];

    final pending = _memorySettings[key];
    if (pending != null) return pending;
    try {
      final value = await store.read('$_settingsPrefix$key');
      if (value != null || !adoptLegacy) return value;
      final legacy = await store.read(key);
      if (legacy == null) return null;
      await store.write('$_settingsPrefix$key', legacy);
      await store.delete(key);
      return legacy;
    } catch (e) {
      debugPrint('CacheManager: could not read setting $key ($e)');
      return null;
    }
  }

  /// Saves the engine setting [key]. See [readSetting]. With [dropLegacy],
  /// a copy left from before 2.0 is removed, so it cannot come back.
  @internal
  Future<void> writeSetting(
    String key,
    String value, {
    bool dropLegacy = false,
  }) async {
    if (!_initialized) return;
    final store = _keyValueCache;
    if (_memoryFallback || store == null) {
      _memorySettings[key] = value;
      return;
    }
    try {
      await store.write('$_settingsPrefix$key', value);
      _memorySettings.remove(key);
      if (dropLegacy && await store.containsKey(key)) await store.delete(key);
    } catch (e) {
      debugPrint('CacheManager: could not save setting $key ($e)');
      _memorySettings[key] = value;
    }
  }

  /// Removes the engine setting [key]. See [readSetting] and [writeSetting].
  @internal
  Future<void> removeSetting(String key, {bool dropLegacy = false}) async {
    if (!_initialized) return;
    _memorySettings.remove(key);
    final store = _keyValueCache;
    if (_memoryFallback || store == null) return;
    try {
      await store.delete('$_settingsPrefix$key');
      if (dropLegacy && await store.containsKey(key)) await store.delete(key);
    } catch (e) {
      debugPrint('CacheManager: could not remove setting $key ($e)');
    }
  }

  /// Dispose of the cache manager and close resources
  void dispose() {
    if (!_initialized) return;
    _memoryStringCache.clear();
    _memoryBinaryCache.clear();
    _memorySettings.clear();

    // _keyValueCache does not have a formal dispose
    final db = _databaseCache;
    if (db != null && db.isOpen) {
      unawaited(
        db.close().catchError((Object e) {
          debugPrint('CacheManager: closing the database failed ($e)');
        }),
      );
    }
    _databaseCache = null;
    _keyValueCache = null;
    _memoryFallback = false;
    _initialized = false;
  }

  /// Returns a lightweight profiling snapshot for runtime tuning.
  MemoryProfileSnapshot captureProfile() => _profiler.capture();

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
