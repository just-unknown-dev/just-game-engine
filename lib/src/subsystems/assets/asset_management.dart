import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import '../../core/engine.dart';

part 'base/asset.dart';
part 'impl/image_asset.dart';
part 'impl/audio_asset.dart';
part 'impl/text_asset.dart';
part 'impl/json_asset.dart';
part 'impl/binary_asset.dart';
part 'impl/asset_loaders.dart';
part 'impl/asset_bundle.dart';

/// Main asset manager class
///
/// Supports two usage patterns:
/// 1. **Simple** — [load] / [unload] for direct management.
/// 2. **Reference-counted** — [acquire] / [release] paired with [AssetScope]
///    for automatic scene-based lifecycle management.
class AssetManager {
  /// Asset cache
  final Map<String, Asset> _assets = {};

  /// Reference counts (only tracked for assets obtained via [acquire]).
  final Map<String, int> _refCounts = {};

  /// Loading tasks in progress
  final Map<String, Future<Asset>> _loadingTasks = {};

  /// Asset loaders by type
  final Map<AssetType, AssetLoader> _loaders = {};

  /// Total memory used by assets
  int _totalMemoryUsage = 0;

  /// Get total memory usage
  int get totalMemoryUsage => _totalMemoryUsage;

  /// Get number of loaded assets
  int get assetCount => _assets.length;

  /// Check if an asset is loaded
  bool isLoaded(String path) =>
      _assets.containsKey(path) && _assets[path]!.isLoaded;

  /// Get the current reference count for an asset (0 if not tracked).
  int refCount(String path) => _refCounts[path] ?? 0;

  /// Initialize the asset manager
  void initialize() {
    // Register default asset loaders
    _loaders[AssetType.image] = ImageAssetLoader();
    _loaders[AssetType.audio] = AudioAssetLoader();
    _loaders[AssetType.text] = TextAssetLoader();
    _loaders[AssetType.json] = JsonAssetLoader();
    _loaders[AssetType.binary] = BinaryAssetLoader();
  }

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

  /// Load an asset of specified type
  Future<Asset> load<T extends Asset>(String path, AssetType type) async {
    // Check if already loaded
    if (_assets.containsKey(path)) {
      return _assets[path]!;
    }

    // Check if loading is in progress
    if (_loadingTasks.containsKey(path)) {
      return await _loadingTasks[path]!;
    }

    // Start loading
    final loadingTask = _loadAsset(path, type);
    _loadingTasks[path] = loadingTask;

    try {
      final asset = await loadingTask;
      _assets[path] = asset;
      _updateMemoryUsage();
      return asset;
    } finally {
      _loadingTasks.remove(path);
    }
  }

  /// Internal asset loading
  Future<Asset> _loadAsset(String path, AssetType type) async {
    final loader = _loaders[type];
    if (loader == null) {
      throw AssetLoadException('No loader registered for asset type: $type');
    }

    final asset = loader.createAsset(path);
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
  /// via an [AssetScope].
  Future<Asset> acquire(String path, AssetType type) async {
    final asset = await load(path, type);
    _refCounts[path] = (_refCounts[path] ?? 0) + 1;
    return asset;
  }

  /// Typed convenience for [acquire].
  Future<ImageAsset> acquireImage(String path) async =>
      await acquire(path, AssetType.image) as ImageAsset;

  /// Typed convenience for [acquire].
  Future<AudioAsset> acquireAudio(String path) async =>
      await acquire(path, AssetType.audio) as AudioAsset;

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

  /// Unload an asset
  void unload(String path) {
    final asset = _assets.remove(path);
    if (asset != null) {
      _refCounts.remove(path);
      asset.unload();
      _updateMemoryUsage();
    }
  }

  /// Unload all assets
  void unloadAll() {
    for (final asset in _assets.values) {
      asset.unload();
    }
    _assets.clear();
    _refCounts.clear();
    _updateMemoryUsage();
  }

  // ── Getters ────────────────────────────────────────────────────────────

  /// Get a loaded asset
  T? get<T extends Asset>(String path) {
    return _assets[path] as T?;
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
