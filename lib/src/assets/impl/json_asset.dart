part of '../asset_management.dart';

/// JSON asset
///
/// Read straight from the asset bundle and kept in memory by [AssetManager]
/// until unloaded — never copied into the engine's persistent cache.
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
      // Not cached by the bundle as well: the parsed data held here is the
      // copy the game uses, and a second one would outlive unload().
      final content = await _bundle.loadString(path, cache: false);
      _data = jsonDecode(content);
      _isLoaded = true;
    } catch (e, stack) {
      Error.throwWithStackTrace(
        AssetLoadException('Failed to load JSON asset: $path', e),
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
    return jsonEncode(_data).length;
  }
}
