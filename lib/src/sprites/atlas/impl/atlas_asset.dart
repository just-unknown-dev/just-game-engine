part of '../sprite_atlas_subsystem.dart';

/// An [Asset] wrapping a fully-parsed and texture-loaded [SpriteAtlas].
///
/// Managed by the engine [AssetManager] under [AssetType.atlas].  The
/// asset is cached by path so repeated calls to [SpriteAtlas.fromAsset]
/// with the same path return the same instance without re-parsing JSON or
/// re-uploading GPU textures.
///
/// ## Standard usage (recommended)
///
/// ```dart
/// // Self-registers the loader and uses AssetManager caching automatically.
/// final atlas = await SpriteAtlas.fromAsset(
///   'assets/data/heroes.json',
///   assets: engine.assets,
/// );
/// ```
///
/// ## Advanced AssetManager usage
///
/// ```dart
/// // Manual registration (only needed if you bypass SpriteAtlas.fromAsset).
/// engine.assets.registerLoader(AssetType.atlas, AtlasAssetLoader());
///
/// final asset = await engine.assets.load<AtlasAsset>(
///     'assets/data/heroes.json', AssetType.atlas) as AtlasAsset;
/// final atlas = asset.atlas!;
/// ```
class AtlasAsset extends Asset {
  SpriteAtlas? _atlas;

  /// The loaded atlas.  `null` until [load] completes successfully.
  SpriteAtlas? get atlas => _atlas;

  /// The atlas described by the JSON file at [path], not loaded yet. It
  /// loads only through an [AssetManager]; [load] throws otherwise.
  AtlasAsset(String path) : super(path, AssetType.atlas);

  @override
  Future<void> load() async {
    if (isLoaded) return;

    final assets =
        manager ??
        (throw StateError(
          'An AtlasAsset loads through an AssetManager: use '
          'SpriteAtlas.fromAsset(path, assets: engine.assets).',
        ));
    // Load the JSON via AssetManager (cached, deduped with other json loads).
    final jsonAsset = await assets.loadJson(path);
    final json = jsonAsset.data as Map<String, dynamic>;

    // Parse + load page textures (each image also goes through AssetManager).
    _atlas = await SpriteAtlas._buildFromJson(json, path, assets);
    markAsLoaded();
  }

  @override
  void unload() {
    // Each page holds its own handle (a clone of the ImageAsset's image),
    // released here; the ImageAssets themselves are the AssetManager's.
    for (final page in _atlas?.pages ?? const <SpriteAtlasPage>[]) {
      page.dispose();
    }
    _atlas = null;
    markAsUnloaded();
  }

  @override
  int getMemoryUsage() {
    // Page GPU memory is tracked by the underlying ImageAssets already.
    // Charge a flat overhead for the region / clip map entries.
    return (_atlas?.regionCount ?? 0) * 128 +
        (_atlas?.clipNames.length ?? 0) * 256;
  }
}

/// [AssetLoader] that creates [AtlasAsset] instances.
///
/// Registered automatically by [SpriteAtlas.fromAsset] on first call.
/// Can also be registered manually:
///
/// ```dart
/// engine.assets.registerLoader(AssetType.atlas, AtlasAssetLoader());
/// ```
class AtlasAssetLoader extends AssetLoader {
  @override
  Asset createAsset(String path) => AtlasAsset(path);
}

// Internal alias used by SpriteAtlas.fromAsset to avoid exposing a public
// class with a leading underscore in the library surface.
typedef _AtlasAssetLoader = AtlasAssetLoader;
