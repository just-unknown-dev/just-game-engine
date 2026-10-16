/// Sprite Batch
///
/// Collects sprites that share a single [ui.Image] atlas and renders them
/// all in **one** [Canvas.drawRawAtlas] call, dramatically reducing per-frame
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

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../interfaces/rendering_interfaces.dart';

/// A batched sprite renderer that issues a single [Canvas.drawRawAtlas] call.
///
/// Sprites are written straight into typed buffers that grow as needed and
/// are kept between frames, so queuing a sprite allocates nothing and a
/// flush hands the engine views of those buffers rather than copies.
class SpriteBatch implements SpriteBatchRenderer {
  /// The shared atlas / sprite-sheet image.
  final ui.Image atlas;

  // Four floats per sprite for the transforms and the source rects, one
  // ARGB int for the colour — the layout Canvas.drawRawAtlas takes.
  Float32List _transforms = Float32List(4 * _initialCapacity);
  Float32List _rects = Float32List(4 * _initialCapacity);
  Int32List _colors = Int32List(_initialCapacity);
  int _count = 0;

  // Whether every colour so far is opaque white. Then the colours change
  // nothing and are not sent at all.
  bool _allWhite = true;

  static const int _initialCapacity = 64;
  static const int _white = 0xFFFFFFFF;

  /// Reusable [Paint] for the draw call.
  final Paint _paint = Paint();

  /// Number of sprites queued since the last [flush].
  int get length => _count;

  /// How the atlas is sampled when a sprite is scaled or turned.
  ///
  /// [FilterQuality.none] keeps pixel art crisp. The render systems batch
  /// sprites by image *and* filter quality and set this to match.
  FilterQuality get filterQuality => _paint.filterQuality;
  set filterQuality(FilterQuality value) => _paint.filterQuality = value;

  /// Create a batch bound to [atlas], sampled with [filterQuality].
  SpriteBatch(this.atlas, {FilterQuality filterQuality = FilterQuality.none}) {
    _paint.filterQuality = filterQuality;
  }

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
    addRaw(
      left: sourceRect.left,
      top: sourceRect.top,
      right: sourceRect.right,
      bottom: sourceRect.bottom,
      x: position.dx,
      y: position.dy,
      rotation: rotation,
      scale: scale,
      anchorX: anchorX,
      anchorY: anchorY,
      argb: color.toARGB32(),
    );
  }

  /// [add] without the objects: the source rect as [left], [top], [right],
  /// [bottom], the position as [x], [y], and the colour as a 32-bit [argb]
  /// value (0xAARRGGBB).
  ///
  /// What the render systems call, so queuing a sprite allocates nothing.
  void addRaw({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double x,
    required double y,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    int argb = _white,
  }) {
    if (_count == _colors.length) _grow();
    final ax = anchorX ?? (right - left) / 2;
    final ay = anchorY ?? (bottom - top) / 2;

    // The RSTransform.fromComponents arithmetic, with a turn-free shortcut.
    final double scos, ssin;
    if (rotation == 0.0) {
      scos = scale;
      ssin = 0.0;
    } else {
      scos = math.cos(rotation) * scale;
      ssin = math.sin(rotation) * scale;
    }
    final i = _count * 4;
    _transforms[i] = scos;
    _transforms[i + 1] = ssin;
    _transforms[i + 2] = x - scos * ax + ssin * ay;
    _transforms[i + 3] = y - ssin * ax - scos * ay;
    _rects[i] = left;
    _rects[i + 1] = top;
    _rects[i + 2] = right;
    _rects[i + 3] = bottom;
    _colors[_count] = argb;
    if (argb != _white) _allWhite = false;
    _count++;
  }

  void _grow() {
    final capacity = _colors.length * 2;
    _transforms = Float32List(4 * capacity)..setAll(0, _transforms);
    _rects = Float32List(4 * capacity)..setAll(0, _rects);
    _colors = Int32List(capacity)..setAll(0, _colors);
  }

  /// Render all queued sprites in a single GPU draw call and clear the batch.
  ///
  /// [blendMode] defaults to [BlendMode.modulate] which multiplies the atlas
  /// colour by each sprite's [Color] (useful for tinting / opacity). When
  /// every sprite is opaque white the colours are left out: multiplying by
  /// white changes nothing.
  @override
  void flush(Canvas canvas, {BlendMode blendMode = BlendMode.modulate}) {
    if (_count == 0) return;

    final n = _count * 4;
    canvas.drawRawAtlas(
      atlas,
      Float32List.sublistView(_transforms, 0, n),
      Float32List.sublistView(_rects, 0, n),
      _allWhite ? null : Int32List.sublistView(_colors, 0, _count),
      _allWhite ? null : blendMode,
      null, // cullRect — null means no culling
      _paint,
    );

    clear();
  }

  /// Discard all queued sprites without drawing.
  void clear() {
    _count = 0;
    _allWhite = true;
  }
}
