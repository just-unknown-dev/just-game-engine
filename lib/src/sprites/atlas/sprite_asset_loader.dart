/// Where the sprite systems and level maps get sprite images and atlases
/// from: the bundle by default, an authoring tool's files when it says so.
library;

import 'dart:ui' as ui;

import '../../assets/asset_manager.dart';
import '../../rendering/sprite.dart';
import 'atlas.dart';

/// Where sprite images and atlases come from.
///
/// The game reads the asset bundle ([BundleSpriteAssetLoader]). An authoring
/// tool points its engine's `context.sprites` at one that reads the
/// project's files, because a sheet saved a second ago is not in the bundle
/// yet.
abstract class SpriteAssetLoader {
  /// The decoded image at [path]. Throws when it cannot be read or decoded.
  Future<ui.Image> loadImage(String path);

  /// Whether each image [loadImage] returns is the caller's own handle (a
  /// [ui.Image.clone]) to dispose when done with it, rather than one the
  /// loader keeps and shares. False unless a loader says so: what is not
  /// the caller's is never disposed by it.
  bool get callerDisposesImages => false;

  /// The atlas described by the JSON at [path], its page images loaded.
  /// Throws when the JSON or a page cannot be read.
  Future<SpriteAtlas> loadAtlas(String path);

  /// Forgets [path], so the next load reads it again. A loader that does not
  /// cache has nothing to do.
  void evict(String path) {}

  /// [loadAtlas], and a hold on the atlas for the caller: what loads through
  /// a cache that counts its users stays loaded until each [acquireAtlas]
  /// is matched by a [releaseAtlas] of the same [path]. What the sprite
  /// systems use for what they show. A loader that counts nothing — that
  /// keeps what it loads, or hands out what the caller owns — loads.
  Future<SpriteAtlas> acquireAtlas(String path) => loadAtlas(path);

  /// Gives back one hold [acquireAtlas] took on [path].
  void releaseAtlas(String path) {}

  /// [loadImage], and a hold on the image for the caller, given back by
  /// [releaseImage]; see [acquireAtlas]. The image returned is the caller's
  /// to dispose when [callerDisposesImages] says so, as from [loadImage].
  Future<ui.Image> acquireImage(String path) => loadImage(path);

  /// Gives back one hold [acquireImage] took on [path].
  void releaseImage(String path) {}
}

/// Loads through an asset manager — the engine's (`context.assets`) — which
/// caches by path. With none given it keeps an [AssetManager] of its own.
class BundleSpriteAssetLoader extends SpriteAssetLoader {
  /// A loader reading through [assets]; a new [AssetManager] of its own,
  /// reading the app's bundle, when null.
  BundleSpriteAssetLoader([AssetManager? assets])
    : assets = assets ?? AssetManager();

  /// What it loads through.
  final AssetManager assets;

  @override
  Future<ui.Image> loadImage(String path) =>
      Sprite.loadImageFromAsset(path, assets: assets);

  /// True: [Sprite.loadImageFromAsset] hands out a clone of the cached image.
  @override
  bool get callerDisposesImages => true;

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      SpriteAtlas.fromAsset(path, assets: assets);

  /// Counted by [assets] ([AssetManager.acquire]): the atlas, and its pages,
  /// are unloaded once every hold on it is given back.
  @override
  Future<SpriteAtlas> acquireAtlas(String path) =>
      SpriteAtlas.acquire(path, assets: assets);

  @override
  void releaseAtlas(String path) => assets.release(path, AssetType.atlas);

  /// Counted by [assets]; the image returned is a clone, the caller's own.
  @override
  Future<ui.Image> acquireImage(String path) async {
    final asset = await assets.acquireImage(path);
    final image = asset.image;
    if (image == null) {
      assets.release(path, AssetType.image);
      throw Exception('Failed to load image asset: $path');
    }
    return image.clone();
  }

  @override
  void releaseImage(String path) => assets.release(path, AssetType.image);

  /// Lets [assets] unload [path] — unless something holds it
  /// ([acquireAtlas], [acquireImage], an atlas page): the images this loader
  /// hands out are clones, which stay usable.
  @override
  void evict(String path) {
    if (assets.refCount(path, AssetType.image) == 0 &&
        assets.refCount(path, AssetType.atlas) == 0) {
      assets.unload(path);
    }
  }
}
