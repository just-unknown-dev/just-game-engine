/// What sprites keep per engine: where sprite images and atlases come from.
library;

import '../ecs/engine_context.dart';
import 'atlas/sprite_asset_loader.dart';

/// The sprite state of one [EngineContext]; read it through
/// [ContextSprites].
final class SpritesContextState {
  SpritesContextState._(EngineContext context)
    : bundleLoader = BundleSpriteAssetLoader(context.assets) {
    loader = bundleLoader;
  }

  /// [context]'s state, made the first time it is asked for.
  static SpritesContextState of(EngineContext context) =>
      context.slot(_key, () => SpritesContextState._(context));

  static final Object _key = Object();

  /// The loader reading the context's bundle, through its assets: the
  /// default [loader].
  final BundleSpriteAssetLoader bundleLoader;

  /// See [ContextSprites.sprites].
  late SpriteAssetLoader loader;
}

/// Where an engine's sprites come from, on its [EngineContext].
extension ContextSprites on EngineContext {
  /// Loads sprite images and atlases for the sprite systems and the level
  /// maps' tileset images. The bundle, through `assets`, by default; an
  /// authoring tool points it at the project's files (`overrideLoaders`).
  SpriteAssetLoader get sprites => SpritesContextState.of(this).loader;
  set sprites(SpriteAssetLoader value) =>
      SpritesContextState.of(this).loader = value;
}
