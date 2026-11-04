part of 'atlas.dart';

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
/// untrimmed [SpriteRegion.sourceSize], placed on its position by its
/// [SpriteRegion.pivot] like any sprite. Trimmed and rotated frames batch
/// with their neighbours too: a batch places and turns them as [render]
/// does.
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

  /// The region shown. Setting it sets [sourceRect] (the frame's place in
  /// the texture), [renderSize] (its untrimmed size) and [pivot] (its
  /// pivot).
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
    pivot = value.pivot;
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

  /// Where the frame is drawn in the sprite's own space: a trimmed one at
  /// its place inside the untrimmed box, where the exporter cut it from —
  /// the box placed by [pivot] — at its own size; upright, for a rotated
  /// one.
  @override
  Rect? get localRect {
    final region = _region;
    if (!_repacked || region == null) return super.localRect;
    final box = region.sourceSize;
    return Rect.fromLTWH(
      -box.width * pivot.dx + region.spriteSourceOffset.dx,
      -box.height * pivot.dy + region.spriteSourceOffset.dy,
      region.frame.width,
      region.frame.height,
    );
  }

  // A repacked frame is drawn at its own pixel size, its pivot found in the
  // frame — turned with it when it is stored turned.
  @override
  double? get batchUnit => _repacked ? 1.0 : super.batchUnit;

  @override
  double get batchAnchorX {
    final region = _region;
    if (!_repacked || region == null) return super.batchAnchorX;
    if (!region.rotated) return _uprightAnchorX(region);
    // Stored a quarter turn clockwise: the upright point (x, y) of a frame
    // h high is at (h - y, x) in the texture.
    return region.frame.height - _uprightAnchorY(region);
  }

  @override
  double get batchAnchorY {
    final region = _region;
    if (!_repacked || region == null) return super.batchAnchorY;
    return region.rotated ? _uprightAnchorX(region) : _uprightAnchorY(region);
  }

  @override
  bool get batchTurned => _repacked && (_region?.rotated ?? false);

  /// The pivot in the upright frame's own pixels: the box's pivot point,
  /// less where the frame starts in the box.
  double _uprightAnchorX(SpriteRegion region) =>
      region.sourceSize.width * pivot.dx - region.spriteSourceOffset.dx;

  double _uprightAnchorY(SpriteRegion region) =>
      region.sourceSize.height * pivot.dy - region.spriteSourceOffset.dy;

  @override
  void render(Canvas canvas, Size size) {
    final region = _region;
    final image = this.image;
    final source = sourceRect;
    final dest = localRect;
    if (!_repacked ||
        region == null ||
        image == null ||
        source == null ||
        dest == null) {
      super.render(canvas, size);
      return;
    }

    applyTransform(canvas);
    // Flipping mirrors the whole box about the pivot, so the frame's place
    // inside it mirrors too.
    if (flipX || flipY) canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);

    // Faded once, by the paint; the filter carries only the tint's colour —
    // as [Sprite.render] and a batch draw it.
    final paint = spritePaint;
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
          paint,
        );
    } else {
      canvas.drawImageRect(image, source, dest, paint);
    }
    restoreTransform(canvas);
  }
}
