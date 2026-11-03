part of '../asset_management.dart';

/// Base class for all assets
abstract class Asset {
  /// Asset identifier/path
  final String path;

  /// Asset type
  final AssetType type;

  /// Whether the asset is loaded
  bool _isLoaded = false;

  /// Get load status
  bool get isLoaded => _isLoaded;

  /// Mark the asset as successfully loaded.
  ///
  /// Call this at the end of [load] in subclasses that live outside the
  /// `asset_management.dart` library (and therefore cannot access the private
  /// field [_isLoaded] directly).
  void markAsLoaded() => _isLoaded = true;

  /// Mark the asset as unloaded.  Call this from [unload] in such subclasses.
  void markAsUnloaded() => _isLoaded = false;

  /// Constructor
  Asset(this.path, this.type);

  AssetManager? _manager;

  /// The manager loading this asset — set before [load] runs — or null for
  /// an asset loaded on its own. An asset that loads others (an atlas its
  /// JSON and page images) loads them through it.
  AssetManager? get manager => _manager;

  /// Where a built-in asset reads its bytes: its manager's bundle, else the
  /// app's.
  AssetBundle get _bundle => _manager?.bundle ?? rootBundle;

  /// Load the asset
  Future<void> load();

  /// Unload the asset and free resources
  void unload();

  /// Get memory usage in bytes
  int getMemoryUsage();
}

/// Asset types supported by the engine
///
/// [AssetManager] has loaders for [image], [audio], [text], [json] and
/// [binary] from the start; [atlas] gets one the first time an atlas is
/// loaded through `SpriteAtlas.fromAsset`. [font], [shader] and [model]
/// have none: loading one throws [AssetLoadException] until a loader is
/// registered with [AssetManager.registerLoader].
enum AssetType {
  /// A decoded picture, loaded as an [ImageAsset].
  image,

  /// A sound file's bytes, loaded as an [AudioAsset].
  audio,

  /// A UTF-8 text file, loaded as a [TextAsset].
  text,

  /// A JSON file, loaded and decoded as a [JsonAsset].
  json,

  /// Raw bytes, loaded as a [BinaryAsset].
  binary,

  /// A font file; no built-in loader.
  font,

  /// A shader program; no built-in loader.
  shader,

  /// A 3-D model; no built-in loader.
  model,

  /// A sprite atlas (its JSON and page images), loaded as an `AtlasAsset`.
  atlas,
}

/// Asset loading exception
class AssetLoadException implements Exception {
  /// What failed, usually naming the asset's path.
  final String message;

  /// The error that made the load fail, or null when there was none (no
  /// loader registered for the type).
  final dynamic cause;

  /// A failure described by [message], caused by [cause] when given;
  /// [toString] prints both.
  AssetLoadException(this.message, [this.cause]);

  @override
  String toString() =>
      'AssetLoadException: $message${cause != null ? '\nCaused by: $cause' : ''}';
}
