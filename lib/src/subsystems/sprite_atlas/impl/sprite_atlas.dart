part of '../sprite_atlas_subsystem.dart';

/// A parsed sprite atlas containing one or more [SpriteAtlasPage]s plus a
/// registry of named [SpriteRegion]s and [AtlasAnimationClip]s.
///
/// ## Loading
///
/// ```dart
/// // Result is cached by AssetManager — repeated calls for the same path
/// // return the same atlas without re-parsing or re-uploading textures.
/// final atlas = await SpriteAtlas.fromAsset('assets/data/heroes.json');
/// ```
///
/// ## Creating sprites
///
/// ```dart
/// // Creates a Sprite already wired to the correct region on the atlas page.
/// // renderSize is set to sourceSize so trimmed sprites display correctly.
/// final sprite = atlas.createSprite('hero_idle_0',
///     position: Offset(100, 200),
///     scale: 2.0);
/// engine.rendering.add(sprite);
/// ```
///
/// ## Animated sprites
///
/// ```dart
/// final sprite = atlas.createSprite('hero_run_0', position: Offset(200, 300));
/// final anim   = atlas.createAnimation('run', sprite);
/// engine.animation.add(anim);
/// ```
///
/// ## Runtime clip registration
///
/// Clips embedded in the atlas JSON (Aseprite `frameTags`) are available
/// immediately.  Additional / override clips can be registered in code:
///
/// ```dart
/// atlas.registerClip(AtlasAnimationClip(
///   name: 'attack_combo',
///   frames: [
///     AtlasFrame(regionName: 'hero_attack_0', duration: 0.05),
///     AtlasFrame(regionName: 'hero_attack_1', duration: 0.08),
///     AtlasFrame(regionName: 'hero_attack_2', duration: 0.12),
///   ],
///   loop: false,
/// ));
/// ```
class SpriteAtlas {
  /// Human-readable name taken from atlas metadata (typically the image
  /// file name without extension).
  final String name;

  /// All texture pages, ordered by page index.
  ///
  /// Single-page atlases have exactly one entry; multi-page atlases have one
  /// entry per exported texture file.
  final List<SpriteAtlasPage> pages;

  // Immutable after construction — built once by the parser.
  final Map<String, SpriteRegion> _regions;

  // Mutable — callers can register clips at runtime.
  final Map<String, AtlasAnimationClip> _clips = {};

  SpriteAtlas({
    required this.name,
    required this.pages,
    required Map<String, SpriteRegion> regions,
    Map<String, AtlasAnimationClip>? clips,
  }) : _regions = Map.unmodifiable(regions) {
    if (clips != null) _clips.addAll(clips);
  }

  // ── Region API ────────────────────────────────────────────────────────────

  /// Returns the named region, or `null` if it does not exist in this atlas.
  SpriteRegion? getRegion(String name) => _regions[name];

  /// Returns the named region.
  ///
  /// Throws [ArgumentError] when the region does not exist — use this in
  /// hot paths where the name is always expected to be valid.
  SpriteRegion requireRegion(String regionName) {
    final r = _regions[regionName];
    if (r == null) {
      throw ArgumentError.value(
        regionName,
        'regionName',
        'Region not found in atlas "$name"',
      );
    }
    return r;
  }

  /// Every region name packed in this atlas.
  Iterable<String> get regionNames => _regions.keys;

  /// Total number of sprite regions.
  int get regionCount => _regions.length;

  // ── Animation clip API ────────────────────────────────────────────────────

  /// Returns the named clip, or `null` if it does not exist.
  AtlasAnimationClip? getClip(String name) => _clips[name];

  /// Returns the named clip.
  ///
  /// Throws [ArgumentError] when the clip does not exist.
  AtlasAnimationClip requireClip(String clipName) {
    final c = _clips[clipName];
    if (c == null) {
      throw ArgumentError.value(
        clipName,
        'clipName',
        'Clip not found in atlas "$name"',
      );
    }
    return c;
  }

  /// Every clip name registered in this atlas (both parsed and runtime).
  Iterable<String> get clipNames => _clips.keys;

  /// Register (or replace) an [AtlasAnimationClip] at runtime.
  ///
  /// Use this to define clips that are not embedded in the atlas JSON, or to
  /// override imported clip timing / loop behaviour with game-logic-specific
  /// values.
  void registerClip(AtlasAnimationClip clip) => _clips[clip.name] = clip;

  /// Convenience: register multiple clips in a single call.
  void registerClips(Iterable<AtlasAnimationClip> clips) {
    for (final clip in clips) {
      _clips[clip.name] = clip;
    }
  }

  // ── Sprite / animation factory helpers ───────────────────────────────────

  /// Create a [Sprite] backed by the named region on this atlas.
  ///
  /// - [Sprite.image] is set to the page's GPU texture.
  /// - [Sprite.sourceRect] is set to [SpriteRegion.frame] (the packed rect).
  /// - [Sprite.renderSize] is set to [SpriteRegion.sourceSize] so trimmed
  ///   sprites always display at their intended dimensions.
  ///
  /// Throws [StateError] if the atlas page has not been loaded yet — this
  /// cannot happen when the atlas was obtained via [SpriteAtlas.fromAsset].
  Sprite createSprite(
    String regionName, {
    Offset position = Offset.zero,
    double rotation = 0.0,
    double scale = 1.0,
    int layer = 0,
    int zOrder = 0,
    bool flipX = false,
    bool flipY = false,
  }) {
    final region = requireRegion(regionName);
    final page = pages[region.pageIndex];
    if (!page.isLoaded) {
      throw StateError(
        'Atlas page ${region.pageIndex} ("${page.imagePath}") has not been '
        'loaded.  Ensure the atlas is fully loaded via SpriteAtlas.fromAsset() '
        'before calling createSprite().',
      );
    }
    return Sprite(
      image: page.image,
      sourceRect: region.frame,
      renderSize: region.sourceSize,
      position: position,
      rotation: rotation,
      scale: scale,
      layer: layer,
      zOrder: zOrder,
      flipX: flipX,
      flipY: flipY,
    );
  }

  /// Create an [AtlasSpriteAnimation] that drives [sprite] through the named
  /// animation clip.
  ///
  /// [sprite] is typically created via [createSprite] before this call; the
  /// animation will continuously update its [Sprite.sourceRect] (and
  /// [Sprite.image] for multi-page atlases) as frames advance.
  ///
  /// ```dart
  /// final sprite = atlas.createSprite('hero_run_0', position: pos);
  /// final anim   = atlas.createAnimation('run', sprite, speed: 1.5);
  /// engine.animation.add(anim);
  /// ```
  AtlasSpriteAnimation createAnimation(
    String clipName,
    Sprite sprite, {
    bool? loop,
    double speed = 1.0,
    VoidCallback? onComplete,
  }) {
    final clip = requireClip(clipName);
    return AtlasSpriteAnimation(
      atlas: this,
      sprite: sprite,
      clip: clip,
      loop: loop ?? clip.loop,
      speed: speed,
      onComplete: onComplete,
    );
  }

  // ── Loader API ────────────────────────────────────────────────────────────

  /// Load and parse a sprite atlas from a JSON asset file, returning a fully
  /// ready [SpriteAtlas] with all page textures decoded.
  ///
  /// The format (TexturePacker JSON-Array/Hash/multi-page or Aseprite) is
  /// detected automatically from the JSON structure — no format hint is needed.
  ///
  /// Results are **cached** by the engine [AssetManager]: repeated calls for
  /// the same [jsonPath] return the same [SpriteAtlas] instance without
  /// re-parsing or re-uploading GPU textures.
  ///
  /// The [_AtlasAssetLoader] is self-registered on first call, so there is no
  /// setup required beyond calling this method.
  static Future<SpriteAtlas> fromAsset(String jsonPath) async {
    final assetMgr = Engine.instance.assets;
    if (!assetMgr.hasLoader(AssetType.atlas)) {
      assetMgr.registerLoader(AssetType.atlas, _AtlasAssetLoader());
    }
    final asset =
        await assetMgr.load<AtlasAsset>(jsonPath, AssetType.atlas)
            as AtlasAsset;
    return asset.atlas!;
  }

  /// Internal factory called by [AtlasAsset.load] to build the [SpriteAtlas]
  /// from an already-decoded JSON map without re-entering [AssetManager].
  static Future<SpriteAtlas> _buildFromJson(
    Map<String, dynamic> json,
    String jsonPath,
  ) async {
    final basePath = _directoryOf(jsonPath);
    final parser = AtlasParser.detect(json);
    final atlas = await parser.parse(json, basePath);
    for (final page in atlas.pages) {
      await page.loadImage();
    }
    return atlas;
  }

  static String _directoryOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i + 1);
  }

  @override
  String toString() =>
      'SpriteAtlas("$name", $regionCount regions, '
      '${pages.length} page(s), ${_clips.length} clips)';
}
