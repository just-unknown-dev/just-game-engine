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
enum AssetType { image, audio, text, json, binary, font, shader, model }

/// Asset loading exception
class AssetLoadException implements Exception {
  final String message;
  final dynamic cause;

  AssetLoadException(this.message, [this.cause]);

  @override
  String toString() =>
      'AssetLoadException: $message${cause != null ? '\nCaused by: $cause' : ''}';
}
