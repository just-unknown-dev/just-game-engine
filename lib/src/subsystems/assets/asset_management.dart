import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:just_dart/just_dart.dart' show Aabb3;
import 'package:just_memory/just_memory.dart';

part 'base/asset.dart';
part 'impl/image_asset.dart';
part 'impl/audio_asset.dart';
part 'impl/text_asset.dart';
part 'impl/json_asset.dart';
part 'impl/binary_asset.dart';
part 'impl/asset_loaders.dart';
part 'impl/asset_bundle.dart';
part 'impl/model_asset.dart';

/// Main asset manager class
///
/// Supports two usage patterns:
/// 1. **Simple** — [load] / [unload] for direct management.
/// 2. **Reference-counted** — [acquire] / [release] paired with [MemoryScope]
///    for automatic scene-based lifecycle management.
///
/// Each engine has one, in its context (`engine.assets`,
/// `engine.context.assets`); assets it loads read from its [bundle].
class AssetManager {
  /// A manager reading from [bundle] — the app's `rootBundle` when null —
  /// with the built-in loaders registered.
  AssetManager({AssetBundle? bundle}) : bundle = bundle ?? rootBundle {
    initialize();
  }

  /// Where the built-in assets read their bytes from.
  final AssetBundle bundle;

  /// Asset cache, by path and type: one file can be two assets (an atlas
  /// and the JSON it is read from).
  final Map<(String, AssetType), Asset> _assets = {};

  /// Reference counts (only tracked for assets obtained via [acquire]).
  final Map<String, int> _refCounts = {};

  /// Loading tasks in progress
  final Map<(String, AssetType), ({Future<Asset> task, Object token})>
  _loadingTasks = {};

  /// Asset loaders by type
  final Map<AssetType, AssetLoader> _loaders = {};

  /// Total memory used by assets
  int _totalMemoryUsage = 0;

  /// Get total memory usage
  int get totalMemoryUsage => _totalMemoryUsage;

  /// Get number of loaded assets
  int get assetCount => _assets.length;

  /// Check if an asset is loaded
  bool isLoaded(String path) {
    for (final MapEntry(:key, :value) in _assets.entries) {
      if (key.$1 == path && value.isLoaded) return true;
    }
    return false;
  }

  /// Get the current reference count for an asset (0 if not tracked).
  int refCount(String path) => _refCounts[path] ?? 0;

  /// Registers the built-in loaders (image, audio, text, JSON, binary),
  /// replacing any registered for those types. The constructor has done
  /// this already; call it again after [dispose] to use the manager again.
  void initialize() {
    // Register default asset loaders
    _loaders[AssetType.image] = ImageAssetLoader();
    _loaders[AssetType.audio] = AudioAssetLoader();
    _loaders[AssetType.text] = TextAssetLoader();
    _loaders[AssetType.json] = JsonAssetLoader();
    _loaders[AssetType.binary] = BinaryAssetLoader();
    // AtlasAssetLoader is registered on-demand by SpriteAtlas.fromAsset.
  }

  /// Register (or replace) an [AssetLoader] for [type].
  ///
  /// Called automatically by [SpriteAtlas.fromAsset] for [AssetType.atlas];
  /// you can also call this to register custom loaders for new asset types.
  void registerLoader(AssetType type, AssetLoader loader) =>
      _loaders[type] = loader;

  /// Removes the loader registered for [type] — only when it is [loader],
  /// if that is given, so one registered since is left alone.
  void unregisterLoader(AssetType type, [AssetLoader? loader]) {
    if (loader == null || identical(_loaders[type], loader)) {
      _loaders.remove(type);
    }
  }

  /// Returns `true` if a loader is registered for [type].
  bool hasLoader(AssetType type) => _loaders.containsKey(type);

  // ── Convenience loaders ────────────────────────────────────────────────

  /// Load an image asset
  Future<ImageAsset> loadImage(String path) async {
    return await load<ImageAsset>(path, AssetType.image) as ImageAsset;
  }

  /// Load an audio asset
  Future<AudioAsset> loadAudio(String path) async {
    return await load<AudioAsset>(path, AssetType.audio) as AudioAsset;
  }

  /// Load a text asset
  Future<TextAsset> loadText(String path) async {
    return await load<TextAsset>(path, AssetType.text) as TextAsset;
  }

  /// Load a JSON asset
  Future<JsonAsset> loadJson(String path) async {
    return await load<JsonAsset>(path, AssetType.json) as JsonAsset;
  }

  /// Load a binary asset
  Future<BinaryAsset> loadBinary(String path) async {
    return await load<BinaryAsset>(path, AssetType.binary) as BinaryAsset;
  }

  /// Load an asset of specified type.
  ///
  /// Assets are kept by path and type, so one file can be loaded as two
  /// (an atlas and its JSON). A load that [unload], [unloadAll] or
  /// [dispose] overtakes is not kept: the asset is unloaded again and the
  /// load throws an [AssetLoadException].
  Future<Asset> load<T extends Asset>(String path, AssetType type) {
    final key = (path, type);
    final loaded = _assets[key];
    if (loaded != null) return Future.value(loaded);

    final pending = _loadingTasks[key];
    if (pending != null) return pending.task;

    final token = Object();
    final task = _loadAndKeep(key, token);
    _loadingTasks[key] = (task: task, token: token);
    return task;
  }

  /// Loads [key] and keeps it, unless it was unloaded meanwhile — then the
  /// asset is let go again.
  Future<Asset> _loadAndKeep((String, AssetType) key, Object token) async {
    try {
      final asset = await _loadAsset(key.$1, key.$2);
      if (!identical(_loadingTasks[key]?.token, token)) {
        asset.unload();
        throw AssetLoadException('"${key.$1}" was unloaded while it loaded.');
      }
      _assets[key] = asset;
      _updateMemoryUsage();
      return asset;
    } finally {
      if (identical(_loadingTasks[key]?.token, token)) {
        _loadingTasks.remove(key);
      }
    }
  }

  /// Internal asset loading
  Future<Asset> _loadAsset(String path, AssetType type) async {
    final loader = _loaders[type];
    if (loader == null) {
      throw AssetLoadException('No loader registered for asset type: $type');
    }

    final asset = loader.createAsset(path).._manager = this;
    await asset.load();
    return asset;
  }

  /// Load multiple assets
  Future<List<Asset>> loadMultiple(List<String> paths, AssetType type) async {
    final futures = paths.map((path) => load(path, type));
    return await Future.wait(futures);
  }

  // ── Reference-counted API ──────────────────────────────────────────────

  /// Load (or reuse) an asset and increment its reference count.
  ///
  /// Pair every [acquire] with a corresponding [release] — either directly or
  /// via an [AssetScope]. The count is taken at once, so a [release] while
  /// the asset is still loading counts (and, as the last one, cancels the
  /// load); a load that fails gives its count back.
  Future<Asset> acquire(String path, AssetType type) async {
    _refCounts[path] = (_refCounts[path] ?? 0) + 1;
    try {
      return await load(path, type);
    } catch (_) {
      final count = _refCounts[path];
      if (count != null) {
        if (count <= 1) {
          _refCounts.remove(path);
        } else {
          _refCounts[path] = count - 1;
        }
      }
      rethrow;
    }
  }

  /// Typed convenience for [acquire].
  Future<ImageAsset> acquireImage(String path) async =>
      await acquire(path, AssetType.image) as ImageAsset;

  /// Typed convenience for [acquire].
  Future<AudioAsset> acquireAudio(String path) async =>
      await acquire(path, AssetType.audio) as AudioAsset;

  /// Load or reuse an asset and automatically release it when [scope] is disposed.
  Future<Asset> acquireScoped(
    String path,
    AssetType type,
    MemoryScope scope,
  ) async {
    final asset = await acquire(path, type);
    scope.own(() => release(path));
    return asset;
  }

  /// Convenience for [acquireScoped].
  Future<ImageAsset> acquireImageScoped(String path, MemoryScope scope) async =>
      await acquireScoped(path, AssetType.image, scope) as ImageAsset;

  /// Convenience for [acquireScoped].
  Future<AudioAsset> acquireAudioScoped(String path, MemoryScope scope) async =>
      await acquireScoped(path, AssetType.audio, scope) as AudioAsset;

  /// Convenience for [acquireScoped].
  Future<TextAsset> acquireTextScoped(String path, MemoryScope scope) async =>
      await acquireScoped(path, AssetType.text, scope) as TextAsset;

  /// Convenience for [acquireScoped].
  Future<JsonAsset> acquireJsonScoped(String path, MemoryScope scope) async =>
      await acquireScoped(path, AssetType.json, scope) as JsonAsset;

  /// Convenience for [acquireScoped].
  Future<BinaryAsset> acquireBinaryScoped(
    String path,
    MemoryScope scope,
  ) async => await acquireScoped(path, AssetType.binary, scope) as BinaryAsset;

  /// Creates a reusable memory scope for scene or subsystem lifetime tracking.
  MemoryScope createScope({String? debugLabel}) =>
      MemoryScope(debugLabel: debugLabel);

  /// Decrement the reference count for [path].
  ///
  /// When the count reaches zero the asset is automatically unloaded.
  void release(String path) {
    final count = _refCounts[path];
    if (count == null) return;

    if (count <= 1) {
      _refCounts.remove(path);
      unload(path);
    } else {
      _refCounts[path] = count - 1;
    }
  }

  // ── Direct unload API ──────────────────────────────────────────────────

  /// Unload the assets at [path], of every type. One still loading is let
  /// go when it arrives.
  void unload(String path) {
    _loadingTasks.removeWhere((key, _) => key.$1 == path);
    _refCounts.remove(path);
    final gone = [
      for (final key in _assets.keys)
        if (key.$1 == path) key,
    ];
    for (final key in gone) {
      _assets.remove(key)!.unload();
    }
    if (gone.isNotEmpty) _updateMemoryUsage();
  }

  /// Unload all assets, and let go of those still loading when they arrive.
  void unloadAll() {
    _loadingTasks.clear();
    for (final asset in _assets.values) {
      asset.unload();
    }
    _assets.clear();
    _refCounts.clear();
    _updateMemoryUsage();
  }

  // ── Getters ────────────────────────────────────────────────────────────

  /// The [T] loaded at [path], or null.
  T? get<T extends Asset>(String path) {
    for (final MapEntry(:key, :value) in _assets.entries) {
      if (key.$1 == path && value is T) return value;
    }
    return null;
  }

  /// Get an image asset
  ImageAsset? getImage(String path) => get<ImageAsset>(path);

  /// Get an audio asset
  AudioAsset? getAudio(String path) => get<AudioAsset>(path);

  /// Get a text asset
  TextAsset? getText(String path) => get<TextAsset>(path);

  /// Get a JSON asset
  JsonAsset? getJson(String path) => get<JsonAsset>(path);

  /// Get a binary asset
  BinaryAsset? getBinary(String path) => get<BinaryAsset>(path);

  /// Update total memory usage
  void _updateMemoryUsage() {
    _totalMemoryUsage = 0;
    for (final asset in _assets.values) {
      _totalMemoryUsage += asset.getMemoryUsage();
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'totalAssets': _assets.length,
      'assetCount': _assets.length,
      'memoryUsage': _totalMemoryUsage,
      'memoryUsageMB': (_totalMemoryUsage / (1024 * 1024)).toStringAsFixed(2),
      'assetsByType': _getAssetCountByType(),
    };
  }

  /// Get asset count by type
  Map<AssetType, int> _getAssetCountByType() {
    final counts = <AssetType, int>{};
    for (final asset in _assets.values) {
      counts[asset.type] = (counts[asset.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Clean up all assets
  void dispose() {
    unloadAll();
    _loaders.clear();
  }
}
