/// Pointing an engine's file seams somewhere else together: an editor
/// reading a project's files instead of the app's bundle.
library;

import '../animation/animation_context.dart';
import '../assets/text_reader.dart';
import '../ecs/engine_context.dart';
import '../level_map/level_map_context.dart';
import '../materials_2d/materials_2d_context.dart';
import '../scenes/prefabs_context.dart';
import '../sprites/atlas/sprite_asset_loader.dart';
import '../sprites/sprites_context.dart';
import '../timeline/timeline_context.dart';

/// The file seams of an [EngineContext], together.
///
/// Each feature reads its files through its own seam — sprites
/// (`context.sprites`), animator graphs (`context.animatorGraphs`),
/// timelines (`context.timelines`), tilesets and maps
/// (`context.tiles.readText`), prefabs (`context.prefabs`) and 2-D
/// materials (`context.material2DText`) — every one reading the bundle
/// until something points it elsewhere.
extension ContextLoaders on EngineContext {
  /// Points the file-reading seams given at other loaders, together — an
  /// editor reading the project's files, say. Returns what puts them back:
  /// [LoaderOverride.restore] restores each seam only if it still holds
  /// what this override set, so a later override is not undone.
  LoaderOverride overrideLoaders({
    SpriteAssetLoader? sprites,
    AnimatorGraphLoader? animatorGraphs,
    TimelineLoader? timelines,
    TextReader? tileText,
    PrefabLoader? prefabs,
    TextReader? material2DText,
  }) {
    final override = LoaderOverride._(
      this,
      sprites: (this.sprites, sprites),
      animatorGraphs: (this.animatorGraphs, animatorGraphs),
      timelines: (this.timelines, timelines),
      tileText: (tiles.readText, tileText),
      prefabs: (this.prefabs, prefabs),
      material2DText: (this.material2DText, material2DText),
    );
    if (material2DText != null) this.material2DText = material2DText;
    if (sprites != null) this.sprites = sprites;
    if (animatorGraphs != null) this.animatorGraphs = animatorGraphs;
    if (timelines != null) this.timelines = timelines;
    if (prefabs != null) this.prefabs = prefabs;
    if (tileText != null) tiles.readText = tileText;
    return override;
  }

  /// Every seam back on [EngineContext.bundle], and the tile caches cleared.
  void useBundle() {
    final sprites = SpritesContextState.of(this);
    sprites.loader = sprites.bundleLoader;
    final animation = AnimationContextState.of(this);
    animation.graphs = animation.bundleLoader;
    final timeline = TimelineContextState.of(this);
    timeline.loader = timeline.bundleLoader;
    final prefabs = PrefabsContextState.of(this);
    prefabs.loader = prefabs.bundleLoader;
    final materials = Materials2DContextState.of(this);
    materials.reader = materials.bundleText;
    final levelMaps = LevelMapContextState.of(this);
    levelMaps.tiles
      ..readText = levelMaps.bundleText
      ..clear();
  }
}

/// What [ContextLoaders.overrideLoaders] changed, and how to put it back.
final class LoaderOverride {
  LoaderOverride._(
    this._context, {
    required (SpriteAssetLoader, SpriteAssetLoader?) sprites,
    required (AnimatorGraphLoader, AnimatorGraphLoader?) animatorGraphs,
    required (TimelineLoader, TimelineLoader?) timelines,
    required (TextReader, TextReader?) tileText,
    required (PrefabLoader, PrefabLoader?) prefabs,
    required (TextReader, TextReader?) material2DText,
  }) : _sprites = sprites,
       _animatorGraphs = animatorGraphs,
       _timelines = timelines,
       _tileText = tileText,
       _prefabs = prefabs,
       _material2DText = material2DText;

  final EngineContext _context;
  final (SpriteAssetLoader, SpriteAssetLoader?) _sprites;
  final (AnimatorGraphLoader, AnimatorGraphLoader?) _animatorGraphs;
  final (TimelineLoader, TimelineLoader?) _timelines;
  final (TextReader, TextReader?) _tileText;
  final (PrefabLoader, PrefabLoader?) _prefabs;
  final (TextReader, TextReader?) _material2DText;
  bool _restored = false;

  /// Puts back each seam this override set, if it still holds what it set.
  /// Once only.
  void restore() {
    if (_restored) return;
    _restored = true;
    final c = _context;
    if (_sprites.$2 case final set? when identical(c.sprites, set)) {
      c.sprites = _sprites.$1;
    }
    if (_animatorGraphs.$2 case final set?
        when identical(c.animatorGraphs, set)) {
      c.animatorGraphs = _animatorGraphs.$1;
    }
    if (_timelines.$2 case final set? when identical(c.timelines, set)) {
      c.timelines = _timelines.$1;
    }
    if (_tileText.$2 case final set? when identical(c.tiles.readText, set)) {
      c.tiles.readText = _tileText.$1;
    }
    if (_prefabs.$2 case final set? when identical(c.prefabs, set)) {
      c.prefabs = _prefabs.$1;
    }
    if (_material2DText.$2 case final set?
        when identical(c.material2DText, set)) {
      c.material2DText = _material2DText.$1;
    }
  }
}
