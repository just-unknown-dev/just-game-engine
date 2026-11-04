part of 'atlas.dart';

/// A single texture page belonging to a [SpriteAtlas].
///
/// Large atlases may span multiple pages when the total packed sprite area
/// exceeds the maximum supported GPU texture size (commonly 4096 × 4096 px).
/// Each page is an independent texture file; a [SpriteRegion]'s [SpriteRegion.pageIndex]
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

  /// Page [index] of an atlas, its texture at [imagePath]; unloaded unless
  /// an already decoded [image] is given.
  SpriteAtlasPage({
    required this.index,
    required this.imagePath,
    required this.size,
    this.image,
  });

  /// Loads (or retrieves from [assets]' cache) the page texture and assigns
  /// [image].
  ///
  /// Called automatically by [SpriteAtlas.fromAsset]; there is no need to
  /// call this manually unless you construct a [SpriteAtlasPage] outside the
  /// standard loading pipeline.
  ///
  /// Throws [StateError] if the image file cannot be found or decoded.
  ///
  /// The page keeps its own handle — a [ui.Image.clone] of the cached image
  /// — so unloading the image asset does not leave the atlas's sprites
  /// drawing a disposed image; [dispose] releases it. It also holds the image
  /// asset in [assets] ([AssetManager.acquire]) while it is loaded, so the
  /// decoded image goes once the last atlas page using it is disposed.
  Future<void> loadImage(AssetManager assets) async {
    if (image != null) return;
    final imgAsset = await assets.acquireImage(imagePath);
    final cached = imgAsset.image;
    if (cached == null) {
      assets.release(imagePath, AssetType.image);
      throw StateError('Failed to decode atlas page texture: $imagePath');
    }
    image = _ownedImage = cached.clone();
    _heldIn = assets;
  }

  /// The handle [loadImage] made, which this page disposes.
  ui.Image? _ownedImage;

  /// Where [loadImage] holds the page's image asset.
  AssetManager? _heldIn;

  /// Releases the image handle [loadImage] took, and — a microtask later —
  /// its hold on the image asset; the page is unloaded after. An image given to the constructor,
  /// or set from outside, belongs to whoever gave it and is left alone.
  /// Sprites made from the page share its image: done when the atlas is
  /// unloaded, after they are gone.
  void dispose() {
    final owned = _ownedImage;
    if (owned == null) return;
    _ownedImage = null;
    if (identical(image, owned)) image = null;
    owned.dispose();
    final assets = _heldIn;
    _heldIn = null;
    // Given back after the asset manager is done with whatever unloaded the
    // atlas: an unloadAll still walking its assets is not changed under it.
    if (assets != null) {
      scheduleMicrotask(() => assets.release(imagePath, AssetType.image));
    }
  }

  /// Whether this page's texture has been loaded into GPU memory.
  bool get isLoaded => image != null;

  @override
  String toString() =>
      'SpriteAtlasPage($index, "$imagePath", ${size.width.toInt()}×${size.height.toInt()}, loaded: $isLoaded)';
}
