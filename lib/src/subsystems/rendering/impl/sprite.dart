/// Sprite System
///
/// Handles image/texture rendering for sprites in the game engine.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'renderable.dart';
import '../../assets/asset_management.dart';
import '../../../interfaces/rendering_interfaces.dart';
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

  // The batched draw path (Canvas.drawAtlas via RenderSystem) only carries a
  // uniform rotation/scale/translation per sprite — it has no way to express
  // flipX/flipY. Reporting no batchImage while flipped routes this sprite
  // through the individual render() path instead, which does support the
  // flip via canvas.scale(-1, 1). Unflipped sprites keep the batching
  // optimisation. The render systems batch by image *and* [filterQuality],
  // so pixel art (FilterQuality.none) batches too, sampled as it asked.
  @override
  ui.Image? get batchImage => (flipX || flipY) ? null : image;

  @override
  Rect? get batchSourceRect => sourceRect;

  // getBounds() below centers on this sprite's own `position` (kept in sync
  // with world space every render pass), unlike CustomRenderable-based
  // shapes' local, origin-centered bounds — see [Renderable.boundsAreWorldSpace].
  @override
  bool get boundsAreWorldSpace => true;

  /// Create a sprite
  Sprite({
    this.image,
    this.sourceRect,
    this.renderSize,
    this.flipX = false,
    this.flipY = false,
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
    if (image == null) return;

    applyTransform(canvas);

    // Determine source rect
    final srcRect =
        sourceRect ??
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());

    // Determine destination size
    final destSize = renderSize ?? Size(srcRect.width, srcRect.height);

    // Calculate destination rect (centered)
    final destRect = Rect.fromCenter(
      center: Offset.zero,
      width: destSize.width,
      height: destSize.height,
    );

    // Apply flipping
    if (flipX || flipY) {
      canvas.save();
      canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    }

    // Set up paint (reuse cached instance)
    final t = tint;
    if (t != _filterTint || opacity != _filterOpacity) {
      _filterTint = t;
      _filterOpacity = opacity;
      // The paint fades the sprite, once, by opacity times the tint's own
      // alpha; the filter carries only the tint's colour — as a batched
      // sprite and a shape are drawn. (The filter used to carry the opacity
      // too, so a tinted sprite faded twice: half opacity drew at a quarter,
      // and changed when the sprite left a batch.)
      _paint.color = Colors.white.withValues(alpha: tintedAlpha(t, opacity));
      // A filter handed to a paint is converted for the engine each time,
      // so it is only replaced when the tint changes.
      _paint.colorFilter = t == null
          ? null
          : ColorFilter.mode(t.withValues(alpha: 1.0), BlendMode.modulate);
    }

    // Draw the image
    canvas.drawImageRect(image!, srcRect, destRect, _paint);

    if (flipX || flipY) {
      canvas.restore();
    }

    restoreTransform(canvas);
  }

  /// How opaque a sprite tinted [tint] at [opacity] is drawn: [opacity]
  /// times the tint's own alpha, as shapes fold a tint in. The tint's
  /// colour multiplies the image's; its alpha fades it like opacity does.
  static double tintedAlpha(Color? tint, double opacity) =>
      tint == null ? opacity : tint.a * opacity;

  @override
  Rect? getBounds() {
    if (image == null) return null;

    final size =
        renderSize ??
        Size(
          sourceRect?.width ?? image!.width.toDouble(),
          sourceRect?.height ?? image!.height.toDouble(),
        );

    return Rect.fromCenter(
      center: position.toOffset(),
      width: size.width * scale.x,
      height: size.height * scale.y,
    );
  }

  /// The image this sprite was given by [fromAsset], which it disposes.
  ui.Image? _ownedImage;

  /// Releases the image handle [fromAsset] gave this sprite. An image passed
  /// to the constructor belongs to whoever passed it and is left alone.
  void dispose() {
    final owned = _ownedImage;
    if (owned == null) return;
    _ownedImage = null;
    if (identical(image, owned)) image = null;
    owned.dispose();
  }

  /// Create a sprite from an asset
  ///
  /// Routes through [assets] — usually `engine.assets` — so the image is
  /// cached and deduplicated. The sprite holds its own handle to the image;
  /// [dispose] releases it.
  static Future<Sprite> fromAsset(
    String assetPath, {
    required AssetManager assets,
    Vector3? position,
    double rotation = 0.0,
    double scale = 1.0,
    int layer = 0,
    int zOrder = 0,
  }) async {
    final image = await loadImageFromAsset(assetPath, assets: assets);
    return Sprite(
      image: image,
      position: position,
      rotation: rotation,
      scale: Vector3(scale, scale, 1.0),
      layer: layer,
      zOrder: zOrder,
    ).._ownedImage = image;
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

/// Sprite sheet for managing multiple sprites from one image
class SpriteSheet {
  /// The sheet image
  final ui.Image image;

  /// Width of each sprite
  final int spriteWidth;

  /// Height of each sprite
  final int spriteHeight;

  /// Spacing between sprites
  final int spacing;

  /// Margin around the sheet
  final int margin;

  /// Cached sprite rectangles
  final List<Rect> _spriteRects = [];

  /// Create a sprite sheet
  SpriteSheet({
    required this.image,
    required this.spriteWidth,
    required this.spriteHeight,
    this.spacing = 0,
    this.margin = 0,
  }) {
    _calculateSpriteRects();
  }

  /// Calculate all sprite rectangles
  void _calculateSpriteRects() {
    _spriteRects.clear();

    final cols =
        (image.width - margin * 2 + spacing) ~/ (spriteWidth + spacing);
    final rows =
        (image.height - margin * 2 + spacing) ~/ (spriteHeight + spacing);

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = margin + col * (spriteWidth + spacing);
        final y = margin + row * (spriteHeight + spacing);

        _spriteRects.add(
          Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            spriteWidth.toDouble(),
            spriteHeight.toDouble(),
          ),
        );
      }
    }
  }

  /// Get a sprite at a specific index
  Sprite getSprite(
    int index, {
    Vector3? position,
    double rotation = 0.0,
    double scale = 1.0,
    int layer = 0,
  }) {
    if (index < 0 || index >= _spriteRects.length) {
      throw ArgumentError('Sprite index $index out of range');
    }

    return Sprite(
      image: image,
      sourceRect: _spriteRects[index],
      position: position,
      rotation: rotation,
      scale: Vector3(scale, scale, 1.0),
      layer: layer,
    );
  }

  /// Get number of sprites
  int get spriteCount => _spriteRects.length;

  /// Whether [image] came from [fromAsset], and so is this sheet's to
  /// dispose.
  bool _ownsImage = false;

  /// Releases the image handle [fromAsset] gave this sheet. Sprites taken
  /// from the sheet share that image: dispose the sheet once they are gone.
  /// A sheet built on an image passed in leaves it alone.
  void dispose() {
    if (!_ownsImage) return;
    _ownsImage = false;
    image.dispose();
  }

  /// Load a sprite sheet from assets
  ///
  /// The sheet holds its own handle to the image; [dispose] releases it.
  static Future<SpriteSheet> fromAsset(
    String assetPath, {
    required AssetManager assets,
    required int spriteWidth,
    required int spriteHeight,
    int spacing = 0,
    int margin = 0,
  }) async {
    final image = await Sprite.loadImageFromAsset(assetPath, assets: assets);
    return SpriteSheet(
      image: image,
      spriteWidth: spriteWidth,
      spriteHeight: spriteHeight,
      spacing: spacing,
      margin: margin,
    ).._ownsImage = true;
  }
}

/// Nine-slice sprite for UI elements
class NineSliceSprite extends Renderable {
  // getBounds() is already placed at [position].
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

  @override
  Rect? getBounds() {
    return Rect.fromCenter(
      center: position.toOffset(),
      width: size.width * scale.x,
      height: size.height * scale.y,
    );
  }
}
