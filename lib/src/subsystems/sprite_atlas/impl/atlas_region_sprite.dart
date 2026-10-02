part of '../sprite_atlas_subsystem.dart';

/// A [Sprite] showing one [SpriteRegion] of an atlas the way its exporter
/// packed it.
///
/// A trimmed frame — its transparent edges cut away by TexturePacker or
/// Aseprite — is drawn at its own size, at [SpriteRegion.spriteSourceOffset]
/// inside the untrimmed box, so an animation whose frames are trimmed
/// differently neither stretches nor jitters. A frame the packer stored
/// turned 90° clockwise ([SpriteRegion.rotated]) is turned back upright.
///
/// The sprite's size — for bounds, culling and picking — is always the
/// untrimmed [SpriteRegion.sourceSize], centred on its position like any
/// sprite. A frame that is neither trimmed nor rotated draws exactly as a
/// plain [Sprite] does, batched with its neighbours; a trimmed or rotated
/// one draws by itself, since a batch cannot move or turn a frame.
class AtlasRegionSprite extends Sprite {
  /// A sprite showing [region] of [image] (the atlas page the region is
  /// on); with no region it draws as a plain [Sprite]. The rest are
  /// [Sprite]'s own parameters.
  AtlasRegionSprite({
    SpriteRegion? region,
    super.image,
    super.flipX,
    super.flipY,
    super.position,
    super.rotation,
    super.scale,
    super.layer,
    super.zOrder,
    super.ySort,
    super.visible,
    super.opacity,
    super.tint,
  }) {
    this.region = region;
  }

  SpriteRegion? _region;
  bool _repacked = false;

  // [Sprite]'s own paint is its own; this one draws a repacked frame.
  final Paint _framePaint = Paint();

  /// The region shown. Setting it sets [sourceRect] (the frame's place in
  /// the texture) and [renderSize] (its untrimmed size).
  SpriteRegion? get region => _region;
  set region(SpriteRegion? value) {
    if (identical(value, _region)) return;
    _region = value;
    if (value == null) {
      _repacked = false;
      return;
    }
    sourceRect = textureRectOf(value);
    renderSize = value.sourceSize;
    _repacked = value.rotated || isTrimmedAway(value);
  }

  /// Where [region]'s pixels are in its page's texture. A rotated frame's
  /// `frame` gives its upright size, so in the texture its width and height
  /// are the other way round.
  static Rect textureRectOf(SpriteRegion region) {
    final f = region.frame;
    return region.rotated ? Rect.fromLTWH(f.left, f.top, f.height, f.width) : f;
  }

  /// Whether trimming moved or shrank [region]'s pixels inside its box —
  /// whether drawing the frame at the box's size would stretch it.
  static bool isTrimmedAway(SpriteRegion region) =>
      region.trimmed &&
      (region.spriteSourceOffset != Offset.zero ||
          region.frame.width != region.sourceSize.width ||
          region.frame.height != region.sourceSize.height);

  // A batch draws the texture rect centred at its native size: right for a
  // whole frame, wrong for one that was trimmed or turned.
  @override
  ui.Image? get batchImage => _repacked ? null : super.batchImage;

  @override
  void render(Canvas canvas, Size size) {
    final region = _region;
    final image = this.image;
    final source = sourceRect;
    if (!_repacked || region == null || image == null || source == null) {
      super.render(canvas, size);
      return;
    }

    applyTransform(canvas);
    // Flipping turns the whole box about its centre, so the frame's place
    // inside it mirrors too.
    if (flipX || flipY) canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);

    _framePaint
      ..filterQuality = filterQuality
      ..color = (tint ?? Colors.white).withValues(alpha: opacity)
      ..colorFilter = tint == null
          ? null
          : ColorFilter.mode(
              tint!.withValues(alpha: opacity),
              BlendMode.modulate,
            );

    // The untrimmed box is centred on the sprite; the frame sits in it where
    // the exporter cut it from.
    final box = region.sourceSize;
    final dest = Rect.fromLTWH(
      -box.width / 2 + region.spriteSourceOffset.dx,
      -box.height / 2 + region.spriteSourceOffset.dy,
      region.frame.width,
      region.frame.height,
    );
    if (region.rotated) {
      // Stored turned 90° clockwise: draw it turned back.
      canvas
        ..translate(dest.center.dx, dest.center.dy)
        ..rotate(-math.pi / 2)
        ..drawImageRect(
          image,
          source,
          Rect.fromCenter(
            center: Offset.zero,
            width: dest.height,
            height: dest.width,
          ),
          _framePaint,
        );
    } else {
      canvas.drawImageRect(image, source, dest, _framePaint);
    }
    restoreTransform(canvas);
  }
}
