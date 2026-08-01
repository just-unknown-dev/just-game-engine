/// Blend Sprite
///
/// Composite [Renderable] populated each frame by `AnimationBlendTreeSystem`
/// with a set of weighted sprite-sheet frame layers, and drawn as a
/// sequence of alpha-composited `drawImageRect` calls — see
/// `ANIMATION_BLEND_TREE.md` at the package root for why the layer alphas
/// must be [BlendCompositor]-derived cumulative alphas, not raw weights.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'renderable.dart';
import '../../../interfaces/rendering_interfaces.dart';

/// One weighted frame to draw as part of a [BlendSprite].
class BlendLayer {
  BlendLayer({required this.image, required this.sourceRect, required this.alpha});

  ui.Image image;
  Rect sourceRect;

  /// Cumulative-renormalized draw alpha — see `BlendCompositor`. Not the
  /// same as the blend weight it was derived from.
  double alpha;
}

/// A [Renderable] that draws several weighted sprite-sheet frames as one
/// visually-blended sprite. Drop-in replacement for [Sprite] wherever a
/// `RenderableComponent.renderable` is assigned; [layers] is normally
/// populated by `AnimationBlendTreeSystem`, not set by hand.
class BlendSprite extends Renderable implements BatchableSprite {
  BlendSprite({
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

  /// The layers to composite this frame, back-to-front. Cleared and
  /// repopulated every tick by `AnimationBlendTreeSystem`.
  final List<BlendLayer> layers = [];

  /// Size to render (null = use the first layer's source size).
  Size? renderSize;

  bool flipX;
  bool flipY;

  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  // A BlendSprite draws multiple, potentially different, source images in
  // one pass — Canvas.drawAtlas batching only carries a single image per
  // sprite, so this always routes through the individual render() path
  // (same opt-out mechanism flipped Sprites already use — see sprite.dart).
  @override
  ui.Image? get batchImage => null;

  @override
  Rect? get batchSourceRect => null;

  @override
  bool get boundsAreWorldSpace => true;

  @override
  void render(Canvas canvas, Size size) {
    if (layers.isEmpty) return;

    applyTransform(canvas);

    if (flipX || flipY) {
      canvas.save();
      canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    }

    final destSize = renderSize ?? layers.first.sourceRect.size;
    final destRect = Rect.fromCenter(
      center: Offset.zero,
      width: destSize.width,
      height: destSize.height,
    );

    // Mirrors Sprite.render's exact tint/opacity paint setup (just per-layer
    // alpha instead of the whole renderable's opacity) so a tinted
    // BlendSprite composites identically to a tinted Sprite.
    for (final layer in layers) {
      final layerAlpha = layer.alpha * opacity;
      if (layerAlpha <= 0) continue;

      _paint.color =
          tint?.withValues(alpha: layerAlpha) ??
          Colors.white.withValues(alpha: layerAlpha);
      if (tint != null) {
        _paint.colorFilter = ColorFilter.mode(
          tint!.withValues(alpha: layerAlpha),
          BlendMode.modulate,
        );
      } else {
        _paint.colorFilter = null;
      }
      canvas.drawImageRect(layer.image, layer.sourceRect, destRect, _paint);
    }

    if (flipX || flipY) {
      canvas.restore();
    }

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    if (layers.isEmpty) return null;
    final size = renderSize ?? layers.first.sourceRect.size;
    return Rect.fromCenter(
      center: position.toOffset(),
      width: size.width * scale.x,
      height: size.height * scale.y,
    );
  }
}
