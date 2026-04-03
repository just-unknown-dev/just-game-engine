part of '../sprite_atlas_subsystem.dart';

/// An [Animation] that drives a [Sprite] through the frames of an
/// [AtlasAnimationClip].
///
/// ## Key differences from [SpriteAnimation]
///
/// | Feature | [SpriteAnimation] | [AtlasSpriteAnimation] |
/// |---|---|---|
/// | Frame timing | Uniform (all frames same duration) | Per-frame (each [AtlasFrame] has its own [AtlasFrame.duration]) |
/// | Frame lookup | O(1) via `normalizedTime` | O(log n) binary search over cumulative table |
/// | Multi-page | Not supported | Automatic — swaps [Sprite.image] when frame crosses page boundary |
/// | Trim support | Manual | Automatic — sets [Sprite.renderSize] to [SpriteRegion.sourceSize] |
/// | Source | Grid arithmetic | Named [SpriteRegion] registry |
///
/// ## Usage
///
/// The preferred way to create an [AtlasSpriteAnimation] is via
/// [SpriteAtlas.createAnimation]:
///
/// ```dart
/// final atlas  = await SpriteAtlas.fromAsset('assets/data/hero.json');
/// final sprite = atlas.createSprite('hero_run_0', position: Offset(200, 300));
/// final anim   = atlas.createAnimation('run', sprite, speed: 1.5);
/// engine.animation.add(anim);
/// ```
///
/// ## Priority-based animation switching
///
/// Because each animation is an independent [Animation] instance you can
/// implement priority-based state machines by removing the current animation
/// and adding a new one:
///
/// ```dart
/// engine.animation.remove(idleAnim);
/// engine.animation.add(atlas.createAnimation('run', heroSprite));
/// ```
///
/// ## Multi-page atlases
///
/// When a frame lives on a different [SpriteAtlasPage] than the previous
/// frame, [Sprite.image] is swapped to the correct page texture on the same
/// tick as [Sprite.sourceRect] — there is no one-frame lag or extra render
/// pass required.
class AtlasSpriteAnimation extends Animation {
  /// The atlas that owns [clip] and the [SpriteRegion] registry.
  final SpriteAtlas atlas;

  /// The sprite whose [Sprite.sourceRect], [Sprite.renderSize], and
  /// (for multi-page atlases) [Sprite.image] are updated as frames advance.
  final Sprite sprite;

  /// The animation clip driving this instance.
  final AtlasAnimationClip clip;

  // Pre-computed cumulative timing table for O(log n) frame lookup.
  // _cumulativeDurations[i] is the total elapsed time at the END of frame i.
  late final List<double> _cumulativeDurations;

  // Index of the frame applied on the last updateAnimation call.
  // Initialised to -1 so the first update always applies frame 0 even when
  // currentTime == 0.
  int _lastFrameIndex = -1;

  /// Create an [AtlasSpriteAnimation].
  ///
  /// [duration] is automatically derived from [clip.totalDuration]; do not
  /// supply it manually.  [loop] defaults to [AtlasAnimationClip.loop].
  AtlasSpriteAnimation({
    required this.atlas,
    required this.sprite,
    required this.clip,
    super.loop = true,
    double speed = 1.0,
    super.onComplete,
  }) : super(duration: clip.totalDuration) {
    this.speed = speed;
    _buildCumulativeTable();
    if (clip.frames.isNotEmpty) _applyFrame(0);
  }

  // ── Private setup ─────────────────────────────────────────────────────────

  void _buildCumulativeTable() {
    _cumulativeDurations = List<double>.filled(clip.frames.length, 0.0);
    double acc = 0.0;
    for (int i = 0; i < clip.frames.length; i++) {
      acc += clip.frames[i].duration;
      _cumulativeDurations[i] = acc;
    }
  }

  // ── Animation overrides ───────────────────────────────────────────────────

  @override
  void updateAnimation(double deltaTime) {
    final idx = _frameIndexAtTime(currentTime);
    if (idx != _lastFrameIndex) {
      _applyFrame(idx);
      _lastFrameIndex = idx;
    }
  }

  @override
  void reset() {
    super.reset();
    _lastFrameIndex = -1;
    if (clip.frames.isNotEmpty) _applyFrame(0);
  }

  // ── Frame lookup ──────────────────────────────────────────────────────────

  /// Binary-search for the frame whose cumulative time window contains [t].
  ///
  /// Complexity: O(log n) where n is the number of frames in the clip.
  /// Returns the last valid index when [t] equals or exceeds total duration.
  int _frameIndexAtTime(double t) {
    if (_cumulativeDurations.isEmpty) return 0;

    // Clamp to the last frame at the boundary (handles the final frame).
    final clamped = t.clamp(0.0, _cumulativeDurations.last);
    int lo = 0, hi = _cumulativeDurations.length - 1;

    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulativeDurations[mid] <= clamped) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, clip.frames.length - 1);
  }

  // ── Frame application ─────────────────────────────────────────────────────

  /// Push frame [index] onto the target [sprite].
  ///
  /// - Updates [Sprite.image] if the new frame lives on a different atlas page
  ///   (multi-page support).
  /// - Sets [Sprite.sourceRect] to [SpriteRegion.frame] (the packed pixel
  ///   data rectangle).
  /// - Sets [Sprite.renderSize] to [SpriteRegion.sourceSize] so trimmed
  ///   sprites always display at their intended dimensions.
  void _applyFrame(int index) {
    final atlasFrame = clip.frames[index];
    final region = atlas.getRegion(atlasFrame.regionName);
    if (region == null) return;

    // Multi-page: swap texture if this frame lives on a different page.
    final page = atlas.pages[region.pageIndex];
    if (sprite.image != page.image) {
      sprite.image = page.image;
    }

    // Trimming: use sourceSize (full art canvas) as the display size so the
    // sprite renders at the correct visual scale regardless of how aggressively
    // the packer trimmed transparent edges.
    sprite.sourceRect = region.frame;
    sprite.renderSize = region.sourceSize;
  }
}
