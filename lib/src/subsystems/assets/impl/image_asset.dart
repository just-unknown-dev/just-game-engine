part of '../asset_management.dart';

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
      final cache = Engine.instance.cache;
      if (cache.isInitialized) {
        final cachedData = await cache.getBinary(path);
        if (cachedData != null) {
          _imageData = cachedData;
          final codec = await ui.instantiateImageCodec(_imageData!);
          final frame = await codec.getNextFrame();
          _image = frame.image;
          _isLoaded = true;
          return;
        }
      }

      // Load image data from assets
      final data = await rootBundle.load(path);
      _imageData = data.buffer.asUint8List();

      if (cache.isInitialized) {
        await cache.setBinary(path, _imageData!);
      }

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
