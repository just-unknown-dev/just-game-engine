part of '../asset_management.dart';

/// Image/Texture asset
///
/// Read straight from the asset bundle — the bundle is already on the device,
/// so nothing is copied into the engine's persistent cache. [AssetManager]
/// keeps the decoded image in memory until the asset is unloaded.
class ImageAsset extends Asset {
  ui.Image? _image;
  Uint8List? _imageData;

  /// Get the loaded image
  ui.Image? get image => _image;

  /// The encoded bytes (PNG, JPEG…) while the image is being decoded.
  ///
  /// Null once [load] completes: the decoded [image] is what the engine
  /// draws, and holding the encoded copy as well doubled the memory an image
  /// cost for the whole time it stayed loaded.
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
      final data = await _bundle.load(path);
      _imageData = _bytesOf(data);

      final codec = await ui.instantiateImageCodec(_imageData!);
      try {
        final frame = await codec.getNextFrame();
        _image = frame.image;
      } finally {
        codec.dispose();
      }

      _isLoaded = true;
    } catch (e, stack) {
      Error.throwWithStackTrace(
        AssetLoadException('Failed to load image asset: $path', e),
        stack,
      );
    } finally {
      _imageData = null;
    }
  }

  /// Disposes the decoded image.
  ///
  /// Anything that must outlive the asset — a sprite still on screen — holds
  /// its own [ui.Image.clone], which this leaves alone.
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

/// The bytes [data] views — only those. `data.buffer` can be larger than the
/// view (a bundle may hand back a slice of a bigger buffer), so reading the
/// whole buffer picked up bytes from outside the asset.
Uint8List _bytesOf(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
