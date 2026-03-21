part of '../asset_management.dart';

/// Binary asset
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
      final cache = Engine.instance.cache;
      if (cache.isInitialized) {
        final cachedData = await cache.getBinary(path);
        if (cachedData != null) {
          _data = cachedData;
          _isLoaded = true;
          return;
        }
      }

      final byteData = await rootBundle.load(path);
      _data = byteData.buffer.asUint8List();

      if (cache.isInitialized && _data != null) {
        await cache.setBinary(path, _data!);
      }

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load binary asset: $path', e);
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
