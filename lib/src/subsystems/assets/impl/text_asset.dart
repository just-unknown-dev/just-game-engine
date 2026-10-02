part of '../asset_management.dart';

/// Text asset
///
/// Read straight from the asset bundle and kept in memory by [AssetManager]
/// until unloaded — never copied into the engine's persistent cache.
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
      // Not cached by the bundle as well: the string held here is the copy
      // the game uses, and a second one would outlive unload().
      _content = await _bundle.loadString(path, cache: false);
      _isLoaded = true;
    } catch (e, stack) {
      Error.throwWithStackTrace(
        AssetLoadException('Failed to load text asset: $path', e),
        stack,
      );
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
