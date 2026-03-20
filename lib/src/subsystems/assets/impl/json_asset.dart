part of '../asset_management.dart';

/// JSON asset
class JsonAsset extends Asset {
  dynamic _data;

  /// Get parsed JSON data
  dynamic get data => _data;

  /// Constructor
  JsonAsset(String path) : super(path, AssetType.json);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final cache = Engine.instance.cache;
      if (cache.isInitialized) {
        final cachedData = await cache.getJson(path);
        if (cachedData != null) {
          _data = cachedData;
          _isLoaded = true;
          return;
        }
      }

      final content = await rootBundle.loadString(path);
      _data = jsonDecode(content);

      if (cache.isInitialized && _data != null) {
        await cache.setJson(path, _data);
      }

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load JSON asset: $path', e);
    }
  }

  @override
  void unload() {
    _data = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    return jsonEncode(_data).length;
  }
}
