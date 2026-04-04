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

  /// Load the asset
  Future<void> load();

  /// Unload the asset and free resources
  void unload();

  /// Get memory usage in bytes
  int getMemoryUsage();
}

/// Asset types supported by the engine
enum AssetType { image, audio, text, json, binary, font, shader, model, atlas }

/// Asset loading exception
class AssetLoadException implements Exception {
  final String message;
  final dynamic cause;

  AssetLoadException(this.message, [this.cause]);

  @override
  String toString() =>
      'AssetLoadException: $message${cause != null ? '\nCaused by: $cause' : ''}';
}
