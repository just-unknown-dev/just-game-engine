part of '../asset_management.dart';

/// Base asset loader interface
abstract class AssetLoader {
  /// Create an asset instance for the given path
  Asset createAsset(String path);
}

/// Image asset loader
class ImageAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => ImageAsset(path);
}

/// Audio asset loader
class AudioAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => AudioAsset(path);
}

/// Text asset loader
class TextAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => TextAsset(path);
}

/// JSON asset loader
class JsonAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => JsonAsset(path);
}

/// Binary asset loader
class BinaryAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => BinaryAsset(path);
}
