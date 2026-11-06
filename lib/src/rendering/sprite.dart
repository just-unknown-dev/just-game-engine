/// Sprite System
///
/// Handles image/texture rendering for sprites in the game engine.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'renderable.dart';
import '../assets/asset_manager.dart';
import '../interfaces/rendering_interfaces.dart';
import 'package:just_dart/just_dart.dart';

/// A sprite that can be rendered
///
/// Sprites are images or textures that can be positioned, rotated, and scaled
/// in the game world.
class Sprite extends Renderable implements BatchableSprite {
  /// The image to render
  ui.Image? image;

  /// Source rectangle (for sprite sheets)
  Rect? sourceRect;

  /// Size to render (null = use image size)
  Size? renderSize;

  /// Flip horizontally
  bool flipX;

  /// Flip vertically
  bool flipY;

  /// The point of the sprite's box placed at its [position] — and that it
  /// turns, scales and mirrors about — as fractions of the box's size:
  /// (0.5, 0.5), the default, is its centre; (0.5, 1) the middle of its
  /// bottom edge, a character's feet.
  Offset pivot;

  /// How the texture is sampled when scaled. [FilterQuality.none] keeps
  /// pixel art crisp; the default smooths, which suits painted art.
  FilterQuality get filterQuality => _paint.filterQuality;
  set filterQuality(FilterQuality value) => _paint.filterQuality = value;

  /// Cached paint object — reused every frame, mutated in-place.
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  // The tint and opacity _paint's colour filter was made for; the filter is
  // replaced only when they change, not every frame.
  Color? _filterTint;
  double _filterOpacity = -1;

  // A batch draws the sprite as [render] does, mirrored or not
  // (SpriteBatchPlan): from [batchSourceRect], [batchAnchorX]/[batchAnchorY]
  // on its position, [batchUnit] world units a texture pixel. The render
  // systems batch by image *and* [filterQuality], so pixel art
  // (FilterQuality.none) batches too, sampled as it asked.
  @override
  ui.Image? get batchImage => image;

  @override
  Rect? get batchSourceRect => sourceRect;

  /// The rectangle of [image] drawn: [sourceRect], else the whole image.
  /// Null with no image.
  Rect? get drawnSourceRect {
    final img = image;
    if (img == null) return null;
    return sourceRect ??
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
  }

  /// The sprite's box in its own space — [renderSize], else the size of
  /// [drawnSourceRect], with [pivot] on the origin — before it is mirrored,
  /// scaled, turned and moved: what its bounds are made from. Null with no
  /// image.
  Rect? get localBox {
    final src = drawnSourceRect;
    if (src == null) return null;
    final size = renderSize ?? src.size;
    return Rect.fromLTWH(
      -size.width * pivot.dx,
      -size.height * pivot.dy,
      size.width,
      size.height,
    );
  }

  /// Where [render] draws [drawnSourceRect], in the sprite's own space
  /// (see [localBox]): the box itself, unless a subclass draws only part
  /// of it. Null with no image.
  Rect? get localRect => localBox;

  /// How many world units one pixel of [batchSourceRect] covers before the
  /// sprite's scale, when [render] draws it evenly both ways; null when it
  /// stretches it, so a batch cannot draw it.
  double? get batchUnit {
    final src = drawnSourceRect;
    if (src == null) return null;
    final size = renderSize;
    return size == null ? 1.0 : _uniformFit(size, src.width, src.height);
  }

  /// The point of [batchSourceRect], in its pixels from its top-left, that
  /// a batch puts on [position]: [pivot]'s.
  double get batchAnchorX => (drawnSourceRect?.width ?? 0) * pivot.dx;

  /// See [batchAnchorX].
  double get batchAnchorY => (drawnSourceRect?.height ?? 0) * pivot.dy;

  /// Whether [batchSourceRect] holds the picture turned a quarter turn
  /// clockwise, which a batch turns back: an atlas frame stored rotated.
  bool get batchTurned => false;

  /// How much [size] scales a source [width] × [height] when it keeps its
  /// proportions; null when it stretches one way more than the other.
  static double? _uniformFit(Size size, double width, double height) {
    if (!(width > 0) || !(height > 0)) return null;
    final fx = size.width / width, fy = size.height / height;
    if (!(fx > 0) || (fx - fy).abs() > 1e-9 * math.max(fx, fy)) return null;
    return fx;
  }

  // bounds below is placed at this sprite's own `position` (kept in
  // sync with world space every render pass), by its pivot, unlike
  // CustomRenderable-based shapes' local, origin-centered bounds — see
  // [Renderable.boundsAreWorldSpace].
  @override
  bool get boundsAreWorldSpace => true;

  /// Create a sprite
  Sprite({
    this.image,
    this.sourceRect,
    this.renderSize,
    this.flipX = false,
    this.flipY = false,
    this.pivot = const Offset(0.5, 0.5),
    super.position,
    super.rotation,
    super.scale,
    super.layer,
    super.zOrder,
    super.ySort,
    super.visible,
    super.opacity,
    super.tint,
  });

  @override
  void render(Canvas canvas, Size size) {
    final img = image;
    final srcRect = drawnSourceRect;
    final destRect = localRect;
    if (img == null || srcRect == null || destRect == null) return;

    applyTransform(canvas);

    // Mirrored about the pivot, the origin here.
    if (flipX || flipY) {
      canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    }

    canvas.drawImageRect(img, srcRect, destRect, spritePaint);

    restoreTransform(canvas);
  }

  /// The paint [render] draws with, kept between frames: it fades the
  /// sprite, once, by opacity times the tint's own alpha, and its colour
  /// filter carries only the tint's colour — as a batched sprite and a
  /// shape are drawn. (The filter used to carry the opacity too, so a
  /// tinted sprite faded twice: half opacity drew at a quarter, and changed
  /// when the sprite left a batch.) A filter handed to a paint is converted
  /// for the engine each time, so it is only replaced when the tint or the
  /// opacity changes.
  @protected
  Paint get spritePaint {
    final t = tint;
    if (t != _filterTint || opacity != _filterOpacity) {
      _filterTint = t;
      _filterOpacity = opacity;
      _paint.color = Colors.white.withValues(alpha: tintedAlpha(t, opacity));
      _paint.colorFilter = t == null
          ? null
          : ColorFilter.mode(t.withValues(alpha: 1.0), BlendMode.modulate);
    }
    return _paint;
  }

  /// How opaque a sprite tinted [tint] at [opacity] is drawn: [opacity]
  /// times the tint's own alpha, as shapes fold a tint in. The tint's
  /// colour multiplies the image's; its alpha fades it like opacity does.
  static double tintedAlpha(Color? tint, double opacity) =>
      tint == null ? opacity : tint.a * opacity;

  /// The world-space box the sprite covers before it is turned: its
  /// [localBox], mirrored, scaled and placed at its position. Never inside
  /// out, whatever the sign of its scale.
  @override
  Rect? get bounds {
    final box = localBox;
    if (box == null) return null;
    final fx = flipX ? -scale.x : scale.x;
    final fy = flipY ? -scale.y : scale.y;
    final x0 = box.left * fx, x1 = box.right * fx;
    final y0 = box.top * fy, y1 = box.bottom * fy;
    final px = position.x, py = position.y;
    return Rect.fromLTRB(
      px + math.min(x0, x1),
      py + math.min(y0, y1),
      px + math.max(x0, x1),
      py + math.max(y0, y1),
    );
  }

  /// The image this sprite was given by [fromAsset], which it disposes.
  ui.Image? _ownedImage;

  /// Where [fromAsset] holds the image asset, and its path.
  AssetManager? _heldIn;
  String? _heldPath;

  /// Releases the image handle [fromAsset] gave this sprite, and its hold
  /// on the image asset. An image passed to the constructor belongs to
  /// whoever passed it and is left alone. Called when the sprite's
  /// `RenderableComponent` leaves its entity.
  @override
  void dispose() {
    final owned = _ownedImage;
    if (owned == null) return;
    _ownedImage = null;
    if (identical(image, owned)) image = null;
    owned.dispose();
    final assets = _heldIn, path = _heldPath;
    _heldIn = _heldPath = null;
    if (assets != null && path != null) assets.release(path, AssetType.image);
  }

  /// Create a sprite from an asset
  ///
  /// Routes through [assets] — usually `engine.assets` — so the image is
  /// cached and deduplicated. The sprite holds its own handle to the image,
  /// and a hold on the image asset ([AssetManager.acquire]); [dispose]
  /// releases both.
  static Future<Sprite> fromAsset(
    String assetPath, {
    required AssetManager assets,
    Vector3? position,
    double rotation = 0.0,
    double scale = 1.0,
    int layer = 0,
    int zOrder = 0,
  }) async {
    final asset = await assets.acquireImage(assetPath);
    final cached = asset.image;
    if (cached == null) {
      assets.release(assetPath, AssetType.image);
      throw Exception('Failed to load image asset: $assetPath');
    }
    final image = cached.clone();
    return Sprite(
        image: image,
        position: position,
        rotation: rotation,
        scale: Vector3(scale, scale, 1.0),
        layer: layer,
        zOrder: zOrder,
      )
      .._ownedImage = image
      .._heldIn = assets
      .._heldPath = assetPath;
  }

  /// Load an image from assets via [assets] (cached / deduplicated).
  ///
  /// Returns a new handle — a [ui.Image.clone] — of the cached image: the
  /// asset manager disposes its own handle when the asset is unloaded, and a
  /// sprite still showing it would then draw a disposed image. The caller
  /// owns the handle and should [ui.Image.dispose] it when done with it.
  static Future<ui.Image> loadImageFromAsset(
    String assetPath, {
    required AssetManager assets,
  }) async {
    final imageAsset = await assets.loadImage(assetPath);
    final image = imageAsset.image;
    if (image == null) {
      throw Exception('Failed to load image asset: $assetPath');
    }
    return image.clone();
  }
}

/// Nine-slice sprite for UI elements
class NineSliceSprite extends Renderable {
  // bounds is already placed at [position].
  @override
  bool get boundsAreWorldSpace => true;

  /// The image to render
  final ui.Image image;

  /// Size to render
  Size size;

  /// Border insets (left, top, right, bottom)
  final EdgeInsets borderInsets;

  /// Cached paint — reused every frame.
  final Paint _paint = Paint();

  /// Create a nine-slice sprite
  NineSliceSprite({
    required this.image,
    required this.size,
    required this.borderInsets,
    super.position,
    super.rotation,
    super.scale,
    super.layer,
    super.zOrder,
    super.visible,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size canvasSize) {
    applyTransform(canvas);

    _paint.color = Colors.white.withValues(alpha: opacity);

    // Define source rectangles
    final srcLeft = borderInsets.left;
    final srcTop = borderInsets.top;
    final srcRight = image.width - borderInsets.right;
    final srcBottom = image.height - borderInsets.bottom;

    // Define destination rectangles
    final dstLeft = -size.width / 2 + borderInsets.left;
    final dstTop = -size.height / 2 + borderInsets.top;
    final dstRight = size.width / 2 - borderInsets.right;
    final dstBottom = size.height / 2 - borderInsets.bottom;

    // Draw nine slices
    // Top-left corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(0, 0, srcLeft, srcTop),
      Rect.fromLTRB(-size.width / 2, -size.height / 2, dstLeft, dstTop),
      _paint,
    );

    // Top edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, 0, srcRight, srcTop),
      Rect.fromLTRB(dstLeft, -size.height / 2, dstRight, dstTop),
      _paint,
    );

    // Top-right corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcRight, 0, image.width.toDouble(), srcTop),
      Rect.fromLTRB(dstRight, -size.height / 2, size.width / 2, dstTop),
      _paint,
    );

    // Left edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(0, srcTop, srcLeft, srcBottom),
      Rect.fromLTRB(-size.width / 2, dstTop, dstLeft, dstBottom),
      _paint,
    );

    // Center
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
      Rect.fromLTRB(dstLeft, dstTop, dstRight, dstBottom),
      _paint,
    );

    // Right edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcRight, srcTop, image.width.toDouble(), srcBottom),
      Rect.fromLTRB(dstRight, dstTop, size.width / 2, dstBottom),
      _paint,
    );

    // Bottom-left corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(0, srcBottom, srcLeft, image.height.toDouble()),
      Rect.fromLTRB(-size.width / 2, dstBottom, dstLeft, size.height / 2),
      _paint,
    );

    // Bottom edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, srcBottom, srcRight, image.height.toDouble()),
      Rect.fromLTRB(dstLeft, dstBottom, dstRight, size.height / 2),
      _paint,
    );

    // Bottom-right corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(
        srcRight,
        srcBottom,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      Rect.fromLTRB(dstRight, dstBottom, size.width / 2, size.height / 2),
      _paint,
    );

    restoreTransform(canvas);
  }

  /// Never inside out, whatever the sign of its scale.
  @override
  Rect? get bounds {
    return Rect.fromCenter(
      center: position.toOffset(),
      width: (size.width * scale.x).abs(),
      height: (size.height * scale.y).abs(),
    );
  }
}
