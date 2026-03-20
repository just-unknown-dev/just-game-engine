/// Sprite System
///
/// Handles image/texture rendering for sprites in the game engine.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'renderable.dart';

/// A sprite that can be rendered
///
/// Sprites are images or textures that can be positioned, rotated, and scaled
/// in the game world.
class Sprite extends Renderable {
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

    // Set up paint
    final paint = Paint()
      ..color =
          tint?.withValues(alpha: opacity) ??
          Colors.white.withValues(alpha: opacity)
      ..filterQuality = FilterQuality.medium;

    // Apply tint if specified
    if (tint != null) {
      paint.colorFilter = ColorFilter.mode(
        tint!.withValues(alpha: opacity),
        BlendMode.modulate,
      );
    } else if (opacity < 1.0) {
      paint.color = Colors.white.withValues(alpha: opacity);
    }

    // Draw the image
    canvas.drawImageRect(image!, srcRect, destRect, paint);

    if (flipX || flipY) {
      canvas.restore();
    }

    restoreTransform(canvas);
  }

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
      center: position,
      width: size.width * scale,
      height: size.height * scale,
    );
  }

  /// Create a sprite from an asset
  static Future<Sprite> fromAsset(
    String assetPath, {
    Offset position = Offset.zero,
    double rotation = 0.0,
    double scale = 1.0,
    int layer = 0,
    int zOrder = 0,
  }) async {
    final image = await loadImageFromAsset(assetPath);
    return Sprite(
      image: image,
      position: position,
      rotation: rotation,
      scale: scale,
      layer: layer,
      zOrder: zOrder,
    );
  }

  /// Load an image from assets
  static Future<ui.Image> loadImageFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
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
    Offset position = Offset.zero,
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
      scale: scale,
      layer: layer,
    );
  }

  /// Get number of sprites
  int get spriteCount => _spriteRects.length;

  /// Load a sprite sheet from assets
  static Future<SpriteSheet> fromAsset(
    String assetPath, {
    required int spriteWidth,
    required int spriteHeight,
    int spacing = 0,
    int margin = 0,
  }) async {
    final image = await Sprite.loadImageFromAsset(assetPath);
    return SpriteSheet(
      image: image,
      spriteWidth: spriteWidth,
      spriteHeight: spriteHeight,
      spacing: spacing,
      margin: margin,
    );
  }
}

/// Nine-slice sprite for UI elements
class NineSliceSprite extends Renderable {
  /// The image to render
  final ui.Image image;

  /// Size to render
  Size size;

  /// Border insets (left, top, right, bottom)
  final EdgeInsets borderInsets;

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

    final paint = Paint()..color = Colors.white.withValues(alpha: opacity);

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
      paint,
    );

    // Top edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, 0, srcRight, srcTop),
      Rect.fromLTRB(dstLeft, -size.height / 2, dstRight, dstTop),
      paint,
    );

    // Top-right corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcRight, 0, image.width.toDouble(), srcTop),
      Rect.fromLTRB(dstRight, -size.height / 2, size.width / 2, dstTop),
      paint,
    );

    // Left edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(0, srcTop, srcLeft, srcBottom),
      Rect.fromLTRB(-size.width / 2, dstTop, dstLeft, dstBottom),
      paint,
    );

    // Center
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
      Rect.fromLTRB(dstLeft, dstTop, dstRight, dstBottom),
      paint,
    );

    // Right edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcRight, srcTop, image.width.toDouble(), srcBottom),
      Rect.fromLTRB(dstRight, dstTop, size.width / 2, dstBottom),
      paint,
    );

    // Bottom-left corner
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(0, srcBottom, srcLeft, image.height.toDouble()),
      Rect.fromLTRB(-size.width / 2, dstBottom, dstLeft, size.height / 2),
      paint,
    );

    // Bottom edge
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(srcLeft, srcBottom, srcRight, image.height.toDouble()),
      Rect.fromLTRB(dstLeft, dstBottom, dstRight, size.height / 2),
      paint,
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
      paint,
    );

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    return Rect.fromCenter(
      center: position,
      width: size.width * scale,
      height: size.height * scale,
    );
  }
}
