/// Sprite Batch
///
/// Collects sprites that share a single [ui.Image] atlas and renders them
/// all in **one** [Canvas.drawAtlas] call, dramatically reducing per-frame
/// draw-call overhead compared to individual [Canvas.drawImageRect] calls.
///
/// Usage:
/// ```dart
/// final batch = SpriteBatch(spriteSheet);
/// batch.add(sourceRect: src1, position: pos1, rotation: r1, scale: s1);
/// batch.add(sourceRect: src2, position: pos2);
/// batch.flush(canvas);  // single GPU draw call
/// ```
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../interfaces/rendering_interfaces.dart';

/// A batched sprite renderer that issues a single [Canvas.drawAtlas] call.
class SpriteBatch implements SpriteBatchRenderer {
  /// The shared atlas / sprite-sheet image.
  final ui.Image atlas;

  // Parallel arrays fed directly to Canvas.drawAtlas.
  final List<RSTransform> _transforms = [];
  final List<Rect> _sources = [];
  final List<Color> _colors = [];

  /// Reusable [Paint] for the draw call.
  final Paint _paint = Paint();

  /// Number of sprites queued since the last [flush].
  int get length => _transforms.length;

  /// Create a batch bound to [atlas].
  SpriteBatch(this.atlas);

  /// Queue a single sprite for batched rendering.
  ///
  /// * [sourceRect] — rectangle on the atlas.
  /// * [position] — world-space centre of the sprite.
  /// * [rotation] — rotation in radians.
  /// * [scale] — uniform scale factor.
  /// * [anchorX], [anchorY] — anchor point in source-rect local space
  ///   (defaults to centre).
  /// * [color] — per-sprite tint / opacity modulation.
  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  }) {
    final ax = anchorX ?? sourceRect.width / 2;
    final ay = anchorY ?? sourceRect.height / 2;

    _transforms.add(
      RSTransform.fromComponents(
        rotation: rotation,
        scale: scale,
        anchorX: ax,
        anchorY: ay,
        translateX: position.dx,
        translateY: position.dy,
      ),
    );
    _sources.add(sourceRect);
    _colors.add(color);
  }

  /// Render all queued sprites in a single GPU draw call and clear the batch.
  ///
  /// [blendMode] defaults to [BlendMode.modulate] which multiplies the atlas
  /// colour by each sprite's [Color] (useful for tinting / opacity).
  @override
  void flush(Canvas canvas, {BlendMode blendMode = BlendMode.modulate}) {
    if (_transforms.isEmpty) return;

    canvas.drawAtlas(
      atlas,
      _transforms,
      _sources,
      _colors,
      blendMode,
      null, // cullRect — null means no culling
      _paint,
    );

    _transforms.clear();
    _sources.clear();
    _colors.clear();
  }

  /// Discard all queued sprites without drawing.
  void clear() {
    _transforms.clear();
    _sources.clear();
    _colors.clear();
  }
}
