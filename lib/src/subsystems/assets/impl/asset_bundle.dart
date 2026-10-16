part of '../asset_management.dart';

/// A named group of assets that load and unload together.
class GameAssetBundle {
  /// What the group is called; the bundle itself does not use it.
  final String name;

  /// The assets' paths, loaded in parallel by [load].
  final List<String> assetPaths;

  /// Each asset's type, in the same order as [assetPaths].
  final List<AssetType> assetTypes;

  /// A group named [name] of the assets at [assetPaths], each of the type
  /// at the same index of [assetTypes]; the two lists must be the same
  /// length (asserted).
  GameAssetBundle({
    required this.name,
    required this.assetPaths,
    required this.assetTypes,
  }) : assert(
         assetPaths.length == assetTypes.length,
         'Asset paths and types must have same length',
       );

  /// Load all assets in this bundle
  Future<void> load(AssetManager manager) async {
    final futures = <Future>[];
    for (int i = 0; i < assetPaths.length; i++) {
      futures.add(manager.load(assetPaths[i], assetTypes[i]));
    }
    await Future.wait(futures);
  }

  /// Unload all assets in this bundle
  void unload(AssetManager manager) {
    for (final path in assetPaths) {
      manager.unload(path);
    }
  }
}

/// A scoped handle for reference-counted asset management.
///
/// Use one [AssetScope] per scene / level / screen. All assets acquired
/// through the scope are automatically released when [dispose] is called,
/// preventing leaks on scene transitions.
///
/// ```dart
/// final scope = AssetScope(engine.assets);
/// final bg = await scope.acquireImage('assets/images/bg.png');
/// // ... use bg ...
/// scope.dispose(); // releases all assets acquired via this scope
/// ```
class AssetScope {
  final AssetManager _manager;
  final List<String> _ownedPaths = [];
  bool _disposed = false;

  /// Create a scope backed by `manager`.
  AssetScope(this._manager);

  /// Acquire an asset, incrementing its reference count. One that arrives
  /// after the scope was disposed is released at once.
  Future<Asset> acquire(String path, AssetType type) async {
    final asset = await _manager.acquire(path, type);
    if (_disposed) {
      _manager.release(path);
    } else {
      _ownedPaths.add(path);
    }
    return asset;
  }

  /// Typed convenience for loading an image through this scope.
  Future<ImageAsset> acquireImage(String path) async =>
      await acquire(path, AssetType.image) as ImageAsset;

  /// Typed convenience for loading audio through this scope.
  Future<AudioAsset> acquireAudio(String path) async =>
      await acquire(path, AssetType.audio) as AudioAsset;

  /// Typed convenience for loading text through this scope.
  Future<TextAsset> acquireText(String path) async =>
      await acquire(path, AssetType.text) as TextAsset;

  /// Typed convenience for loading JSON through this scope.
  Future<JsonAsset> acquireJson(String path) async =>
      await acquire(path, AssetType.json) as JsonAsset;

  /// Release all assets acquired through this scope.
  ///
  /// Assets still held by other scopes will remain loaded; only the
  /// reference count from *this* scope is decremented.
  void dispose() {
    _disposed = true;
    for (final path in _ownedPaths) {
      _manager.release(path);
    }
    _ownedPaths.clear();
  }
}
