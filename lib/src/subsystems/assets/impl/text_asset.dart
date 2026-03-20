part of '../asset_management.dart';

/// Text asset
class TextAsset extends Asset {
  String? _content;

  /// Get text content
  String? get content => _content;

  /// Constructor
  TextAsset(String path) : super(path, AssetType.text);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final cache = Engine.instance.cache;
      if (cache.isInitialized) {
        final cachedContent = await cache.getString(path);
        if (cachedContent != null) {
          _content = cachedContent;
          _isLoaded = true;
          return;
        }
      }

      _content = await rootBundle.loadString(path);

      if (cache.isInitialized && _content != null) {
        await cache.setString(path, _content!);
      }

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load text asset: $path', e);
    }
  }

  @override
  void unload() {
    _content = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    return _content?.length ?? 0;
  }
}
