/// Where the sprite systems and level maps get sprite images and atlases
/// from: the bundle by default, an authoring tool's files when it says so.
library;

import 'dart:ui' as ui;

import '../assets/asset_management.dart';
import '../rendering/impl/sprite.dart';
import 'sprite_atlas_subsystem.dart';

/// Where sprite images and atlases come from.
///
/// The game reads the asset bundle ([BundleSpriteAssetLoader]). An authoring
/// tool points its engine's `context.sprites` at one that reads the
/// project's files, because a sheet saved a second ago is not in the bundle
/// yet.
abstract class SpriteAssetLoader {
  /// The decoded image at [path]. Throws when it cannot be read or decoded.
  Future<ui.Image> loadImage(String path);

  /// The atlas described by the JSON at [path], its page images loaded.
  /// Throws when the JSON or a page cannot be read.
  Future<SpriteAtlas> loadAtlas(String path);

  /// Forgets [path], so the next load reads it again. A loader that does not
  /// cache has nothing to do.
  void evict(String path) {}
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

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      SpriteAtlas.fromAsset(path, assets: assets);
}
