/// Asset Management
///
/// Manages and imports game assets like 3D models, textures, and sounds.
/// This module provides asset loading, caching, and resource management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;

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

/// Image/Texture asset
class ImageAsset extends Asset {
  ui.Image? _image;
  Uint8List? _imageData;

  /// Get the loaded image
  ui.Image? get image => _image;

  /// Get raw image data
  Uint8List? get data => _imageData;

  /// Image width
  int get width => _image?.width ?? 0;

  /// Image height
  int get height => _image?.height ?? 0;

  /// Constructor
  ImageAsset(String path) : super(path, AssetType.image);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      // Load image data from assets
      final data = await rootBundle.load(path);
      _imageData = data.buffer.asUint8List();

      // Decode image
      final codec = await ui.instantiateImageCodec(_imageData!);
      final frame = await codec.getNextFrame();
      _image = frame.image;

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load image asset: $path', e);
    }
  }

  @override
  void unload() {
    _image?.dispose();
    _image = null;
    _imageData = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    if (_image != null) {
      return _image!.width * _image!.height * 4; // RGBA
    }
    return _imageData?.length ?? 0;
  }
}

/// Audio asset (placeholder for audio data)
class AudioAsset extends Asset {
  Uint8List? _audioData;
  AudioFormat? _format;
  Duration? _duration;

  /// Get raw audio data
  Uint8List? get data => _audioData;

  /// Get audio format
  AudioFormat? get format => _format;

  /// Get audio duration
  Duration? get duration => _duration;

  /// Constructor
  AudioAsset(String path) : super(path, AssetType.audio);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      // Load audio data from assets
      final data = await rootBundle.load(path);
      _audioData = data.buffer.asUint8List();

      // Detect format from extension
      if (path.endsWith('.mp3')) {
        _format = AudioFormat.mp3;
      } else if (path.endsWith('.wav')) {
        _format = AudioFormat.wav;
      } else if (path.endsWith('.ogg')) {
        _format = AudioFormat.ogg;
      }

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load audio asset: $path', e);
    }
  }

  @override
  void unload() {
    _audioData = null;
    _format = null;
    _duration = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    return _audioData?.length ?? 0;
  }
}

/// Audio format types
enum AudioFormat { mp3, wav, ogg, flac }

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
      _content = await rootBundle.loadString(path);
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
      final content = await rootBundle.loadString(path);
      _data = jsonDecode(content);
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
      final byteData = await rootBundle.load(path);
      _data = byteData.buffer.asUint8List();
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

/// Asset loading exception
class AssetLoadException implements Exception {
  final String message;
  final dynamic cause;

  AssetLoadException(this.message, [this.cause]);

  @override
  String toString() =>
      'AssetLoadException: $message${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Main asset manager class
class AssetManager {
  /// Asset cache
  final Map<String, Asset> _assets = {};

  /// Loading tasks in progress
  final Map<String, Future<Asset>> _loadingTasks = {};

  /// Asset loaders by type
  final Map<AssetType, AssetLoader> _loaders = {};

  /// Total memory used by assets
  int _totalMemoryUsage = 0;

  /// Get total memory usage
  int get totalMemoryUsage => _totalMemoryUsage;

  /// Get number of loaded assets
  int get assetCount => _assets.length;

  /// Check if an asset is loaded
  bool isLoaded(String path) =>
      _assets.containsKey(path) && _assets[path]!.isLoaded;

  /// Initialize the asset manager
  void initialize() {
    // Register default asset loaders
    _loaders[AssetType.image] = ImageAssetLoader();
    _loaders[AssetType.audio] = AudioAssetLoader();
    _loaders[AssetType.text] = TextAssetLoader();
    _loaders[AssetType.json] = JsonAssetLoader();
    _loaders[AssetType.binary] = BinaryAssetLoader();
  }

  /// Load an image asset
  Future<ImageAsset> loadImage(String path) async {
    return await load<ImageAsset>(path, AssetType.image) as ImageAsset;
  }

  /// Load an audio asset
  Future<AudioAsset> loadAudio(String path) async {
    return await load<AudioAsset>(path, AssetType.audio) as AudioAsset;
  }

  /// Load a text asset
  Future<TextAsset> loadText(String path) async {
    return await load<TextAsset>(path, AssetType.text) as TextAsset;
  }

  /// Load a JSON asset
  Future<JsonAsset> loadJson(String path) async {
    return await load<JsonAsset>(path, AssetType.json) as JsonAsset;
  }

  /// Load a binary asset
  Future<BinaryAsset> loadBinary(String path) async {
    return await load<BinaryAsset>(path, AssetType.binary) as BinaryAsset;
  }

  /// Load an asset of specified type
  Future<Asset> load<T extends Asset>(String path, AssetType type) async {
    // Check if already loaded
    if (_assets.containsKey(path)) {
      return _assets[path]!;
    }

    // Check if loading is in progress
    if (_loadingTasks.containsKey(path)) {
      return await _loadingTasks[path]!;
    }

    // Start loading
    final loadingTask = _loadAsset(path, type);
    _loadingTasks[path] = loadingTask;

    try {
      final asset = await loadingTask;
      _assets[path] = asset;
      _updateMemoryUsage();
      return asset;
    } finally {
      _loadingTasks.remove(path);
    }
  }

  /// Internal asset loading
  Future<Asset> _loadAsset(String path, AssetType type) async {
    final loader = _loaders[type];
    if (loader == null) {
      throw AssetLoadException('No loader registered for asset type: $type');
    }

    final asset = loader.createAsset(path);
    await asset.load();
    return asset;
  }

  /// Load multiple assets
  Future<List<Asset>> loadMultiple(List<String> paths, AssetType type) async {
    final futures = paths.map((path) => load(path, type));
    return await Future.wait(futures);
  }

  /// Unload an asset
  void unload(String path) {
    final asset = _assets.remove(path);
    if (asset != null) {
      asset.unload();
      _updateMemoryUsage();
    }
  }

  /// Unload all assets
  void unloadAll() {
    for (final asset in _assets.values) {
      asset.unload();
    }
    _assets.clear();
    _updateMemoryUsage();
  }

  /// Get a loaded asset
  T? get<T extends Asset>(String path) {
    return _assets[path] as T?;
  }

  /// Get an image asset
  ImageAsset? getImage(String path) => get<ImageAsset>(path);

  /// Get an audio asset
  AudioAsset? getAudio(String path) => get<AudioAsset>(path);

  /// Get a text asset
  TextAsset? getText(String path) => get<TextAsset>(path);

  /// Get a JSON asset
  JsonAsset? getJson(String path) => get<JsonAsset>(path);

  /// Get a binary asset
  BinaryAsset? getBinary(String path) => get<BinaryAsset>(path);

  /// Update total memory usage
  void _updateMemoryUsage() {
    _totalMemoryUsage = 0;
    for (final asset in _assets.values) {
      _totalMemoryUsage += asset.getMemoryUsage();
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'totalAssets': _assets.length,
      'assetCount': _assets.length,
      'memoryUsage': _totalMemoryUsage,
      'memoryUsageMB': (_totalMemoryUsage / (1024 * 1024)).toStringAsFixed(2),
      'assetsByType': _getAssetCountByType(),
    };
  }

  /// Get asset count by type
  Map<AssetType, int> _getAssetCountByType() {
    final counts = <AssetType, int>{};
    for (final asset in _assets.values) {
      counts[asset.type] = (counts[asset.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Clean up all assets
  void dispose() {
    unloadAll();
    _loaders.clear();
  }
}

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

/// Asset bundle for grouped loading
class AssetBundle {
  final String name;
  final List<String> assetPaths;
  final List<AssetType> assetTypes;

  AssetBundle({
    required this.name,
    required this.assetPaths,
    required this.assetTypes,
  }) : assert(
         assetPaths.length == assetTypes.length,
         'Asset paths and types must have same length',
       );

  /// Load all assets in this bundle
  Future<void> load(AssetManager manager) async {
    final futures = <Future>[];
    for (int i = 0; i < assetPaths.length; i++) {
      futures.add(manager.load(assetPaths[i], assetTypes[i]));
    }
    await Future.wait(futures);
  }

  /// Unload all assets in this bundle
  void unload(AssetManager manager) {
    for (final path in assetPaths) {
      manager.unload(path);
    }
  }
}
