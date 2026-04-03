part of '../sprite_atlas_subsystem.dart';

/// A single texture page belonging to a [SpriteAtlas].
///
/// Large atlases may span multiple pages when the total packed sprite area
/// exceeds the maximum supported GPU texture size (commonly 4096 × 4096 px).
/// Each page is an independent texture file; a [SpriteRegion]'s [pageIndex]
/// says which page it lives on.
///
/// Page images are loaded and cached through the engine [AssetManager] so
/// they integrate transparently with the reference-counted asset lifecycle
/// and the memory-budget tracking in [AssetManager.totalMemoryUsage].
class SpriteAtlasPage {
  /// Zero-based index of this page within [SpriteAtlas.pages].
  final int index;

  /// Asset path to the page's texture image
  /// (e.g. `"assets/sprites/heroes_0.png"`).
  final String imagePath;

  /// Decoded GPU image.  `null` until [loadImage] has been called.
  ui.Image? image;

  /// Pixel dimensions of this page, as reported in the atlas metadata.
  final Size size;

  SpriteAtlasPage({
    required this.index,
    required this.imagePath,
    required this.size,
    this.image,
  });

  /// Loads (or retrieves from the engine [AssetManager] cache) the page
  /// texture and assigns [image].
  ///
  /// Called automatically by [SpriteAtlas.fromAsset]; there is no need to
  /// call this manually unless you construct a [SpriteAtlasPage] outside the
  /// standard loading pipeline.
  ///
  /// Throws [StateError] if the image file cannot be found or decoded.
  Future<void> loadImage() async {
    if (image != null) return;
    final imgAsset = await Engine.instance.assets.loadImage(imagePath);
    if (imgAsset.image == null) {
      throw StateError('Failed to decode atlas page texture: $imagePath');
    }
    image = imgAsset.image;
  }

  /// Whether this page's texture has been loaded into GPU memory.
  bool get isLoaded => image != null;

  @override
  String toString() =>
      'SpriteAtlasPage($index, "$imagePath", ${size.width.toInt()}×${size.height.toInt()}, loaded: $isLoaded)';
}
