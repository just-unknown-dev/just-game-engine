part of '../asset_management.dart';

/// Binary asset
///
/// Read straight from the asset bundle and kept in memory by [AssetManager]
/// until unloaded — never copied into the engine's persistent cache.
class BinaryAsset extends Asset {
  Uint8List? _data;

  /// Get binary data
  Uint8List? get data => _data;

  /// Constructor
  BinaryAsset(String path) : super(path, AssetType.binary);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final byteData = await _bundle.load(path);
      _data = _bytesOf(byteData);
      _isLoaded = true;
    } catch (e, stack) {
      Error.throwWithStackTrace(
        AssetLoadException('Failed to load binary asset: $path', e),
        stack,
      );
    }
  }

  @override
  void unload() {
    _data = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    return _data?.length ?? 0;
  }
}
