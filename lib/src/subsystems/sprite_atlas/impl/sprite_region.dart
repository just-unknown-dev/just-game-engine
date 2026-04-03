part of '../sprite_atlas_subsystem.dart';

/// A named region within a [SpriteAtlas] — describes one sprite or animation
/// frame packed onto an atlas page.
///
/// ## Trimmed sprites
/// When an exporter (e.g. TexturePacker) removes transparent edges to save
/// atlas space, [trimmed] is `true`.  In that case:
/// - [frame] is the **compact** rectangle of actual pixel data in the texture.
/// - [sourceSize] is the **original** art-canvas size (what the sprite should
///   render at).
/// - [spriteSourceOffset] is the top-left position of [frame] within that
///   original canvas, so the trimmed data can be placed back in the right spot.
///
/// Renderers should always display the sprite at [sourceSize]; using [frame]
/// alone for the destination rect would produce a visibly cropped sprite.
///
/// ## Rotated sprites
/// When [rotated] is `true` the exporter stored the frame rotated 90° CW.
/// [AtlasSpriteAnimation] accounts for this automatically via [Sprite.sourceRect].
///
/// ## Pivots / anchors
/// [pivot] is a normalised anchor point (`0.0`–`1.0` per axis).  Defaults to
/// `Offset(0.5, 0.5)` — the centre of the sprite.  [anchorX] / [anchorY]
/// convert this to source-space coordinates for use with [Canvas.drawAtlas]
/// / [RSTransform].
class SpriteRegion {
  /// Logical name used to look up this region (e.g. `"player_run_1"`).
  final String name;

  /// Index into [SpriteAtlas.pages] identifying which texture page this
  /// region lives on.
  final int pageIndex;

  /// Pixel rectangle of the **packed** sprite data inside the atlas texture.
  ///
  /// For trimmed sprites this is smaller than [sourceSize]; for untrimmed
  /// sprites it equals the full art-canvas rect.
  final Rect frame;

  /// `true` when the exporter rotated this frame 90° clock-wise to fit better.
  ///
  /// Renderers must undo this rotation to display the sprite correctly.
  final bool rotated;

  /// `true` when the exporter stripped transparent pixels from the edges.
  final bool trimmed;

  /// Top-left position of [frame] inside the original art canvas.
  ///
  /// `Offset.zero` for untrimmed sprites.  For trimmed sprites this tells you
  /// where to start drawing [frame] so the content lines up with the original
  /// design.
  final Offset spriteSourceOffset;

  /// Full art-canvas size **before** any trimming.
  ///
  /// Use this as the render / display size so the sprite always occupies the
  /// intended amount of screen space regardless of trimming.
  final Size sourceSize;

  /// Normalised pivot / anchor point (0 – 1 per axis).
  ///
  /// Defaults to `Offset(0.5, 0.5)` — the centre of the sprite.
  final Offset pivot;

  const SpriteRegion({
    required this.name,
    required this.pageIndex,
    required this.frame,
    this.rotated = false,
    this.trimmed = false,
    this.spriteSourceOffset = Offset.zero,
    required this.sourceSize,
    this.pivot = const Offset(0.5, 0.5),
  });

  /// Convenience alias for [sourceSize] — the correct display dimensions.
  Size get renderSize => sourceSize;

  /// X anchor in source-rect local coordinates (frame space), accounting for
  /// the trim offset and the configured [pivot].
  ///
  /// Use this as `anchorX` when building an [RSTransform] for [Canvas.drawAtlas].
  double get anchorX => spriteSourceOffset.dx + sourceSize.width * pivot.dx;

  /// Y anchor in source-rect local coordinates.
  double get anchorY => spriteSourceOffset.dy + sourceSize.height * pivot.dy;

  @override
  String toString() =>
      'SpriteRegion("$name", frame: $frame, trimmed: $trimmed, rotated: $rotated)';
}
