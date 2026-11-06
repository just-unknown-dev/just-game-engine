/// Sprite Batch
///
/// Collects sprites that share a single [ui.Image] atlas and renders them
/// all in **one** draw call — [Canvas.drawRawAtlas], or
/// [Canvas.drawVertices] when one of them is mirrored — dramatically
/// reducing per-frame draw-call overhead compared to individual
/// [Canvas.drawImageRect] calls.
///
/// Usage:
/// ```dart
/// final batch = SpriteBatch(spriteSheet);
/// batch.add(sourceRect: src1, position: pos1, rotation: r1, scale: s1);
/// batch.add(sourceRect: src2, position: pos2, flipX: true);
/// batch.flush(canvas);  // single GPU draw call
/// ```
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../interfaces/rendering_interfaces.dart';

/// A batched sprite renderer that issues a single draw call per flush.
///
/// Sprites are written straight into typed buffers that grow as needed and
/// are kept between frames, so queuing a sprite allocates nothing and a
/// flush hands the engine views of those buffers rather than copies.
///
/// A sprite can be mirrored ([addRaw]'s `flipX` and `flipY`), which a
/// [Canvas.drawRawAtlas] transform cannot express: a flush holding a
/// mirrored sprite draws every sprite queued as textured triangles
/// ([Canvas.drawVertices]) instead — one call still, in the order queued.
class SpriteBatch implements SpriteBatchRenderer {
  /// The shared atlas / sprite-sheet image.
  final ui.Image atlas;

  // Four floats per sprite for the transforms and the source rects, one
  // ARGB int for the colour — the layout Canvas.drawRawAtlas takes — and,
  // for the triangles a mirrored sprite needs, its anchor and its mirror.
  Float32List _transforms = Float32List(4 * _initialCapacity);
  Float32List _rects = Float32List(4 * _initialCapacity);
  Int32List _colors = Int32List(_initialCapacity);
  Float32List _anchors = Float32List(2 * _initialCapacity);
  Uint8List _flips = Uint8List(_initialCapacity);
  int _count = 0;

  // Whether every colour so far is opaque white. Then the colours change
  // nothing and are not sent at all.
  bool _allWhite = true;

  // Whether a sprite queued is mirrored: then the flush draws triangles.
  bool _anyFlip = false;

  // The triangles' buffers, kept between flushes.
  Float32List _positions = Float32List(0);
  Float32List _texCoords = Float32List(0);
  Int32List _vertexColors = Int32List(0);
  Uint16List _indices = Uint16List(0);

  static const int _initialCapacity = 64;
  static const int _white = 0xFFFFFFFF;
  static const int _flipXBit = 1, _flipYBit = 2;

  // Four corners a sprite: 16-bit indices reach this many in one call.
  static const int _maxQuadsPerDraw = 16383;

  // The atlas shader's matrix: texture coordinates are in its pixels. One a
  // batch, not one a process: a typed list cannot be const.
  final Float64List _identity = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;

  /// Reusable [Paint] for the draw call.
  final Paint _paint = Paint();

  /// Reusable [Paint] for the triangles, given the atlas as a shader.
  final Paint _vertexPaint = Paint();

  /// Number of sprites queued since the last [flush].
  int get length => _count;

  /// Whether a sprite queued since the last [flush] is mirrored, so the
  /// flush draws triangles rather than an atlas.
  bool get hasMirrored => _anyFlip;

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
  /// * [position] — world-space position of the anchor.
  /// * [rotation] — rotation in radians.
  /// * [scale] — uniform scale factor.
  /// * [anchorX], [anchorY] — anchor point in source-rect local space
  ///   (defaults to centre).
  /// * [flipX], [flipY] — mirror the sprite about its anchor.
  /// * [color] — per-sprite tint / opacity modulation.
  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    bool flipX = false,
    bool flipY = false,
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
      flipX: flipX,
      flipY: flipY,
      argb: color.toARGB32(),
    );
  }

  /// [add] without the objects: the source rect as [left], [top], [right],
  /// [bottom], the position as [x], [y], and the colour as a 32-bit [argb]
  /// value (0xAARRGGBB).
  ///
  /// The source pixel at ([anchorX], [anchorY]) from the rect's top-left
  /// (its centre when null) lands on ([x], [y]); the sprite is mirrored
  /// about it by [flipX] and [flipY], then scaled and turned about it — as
  /// a sprite drawn by itself is.
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
    bool flipX = false,
    bool flipY = false,
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
    _anchors[_count * 2] = ax;
    _anchors[_count * 2 + 1] = ay;
    final flips = (flipX ? _flipXBit : 0) | (flipY ? _flipYBit : 0);
    _flips[_count] = flips;
    if (flips != 0) _anyFlip = true;
    _colors[_count] = argb;
    if (argb != _white) _allWhite = false;
    _count++;
  }

  void _grow() {
    final capacity = _colors.length * 2;
    _transforms = Float32List(4 * capacity)..setAll(0, _transforms);
    _rects = Float32List(4 * capacity)..setAll(0, _rects);
    _colors = Int32List(capacity)..setAll(0, _colors);
    _anchors = Float32List(2 * capacity)..setAll(0, _anchors);
    _flips = Uint8List(capacity)..setAll(0, _flips);
  }

  /// Render all queued sprites in a single GPU draw call and clear the batch.
  ///
  /// [blendMode] defaults to [BlendMode.modulate] which multiplies the atlas
  /// colour by each sprite's [Color] (useful for tinting / opacity). When
  /// every sprite is opaque white the colours are left out: multiplying by
  /// white changes nothing.
  ///
  /// When a queued sprite is mirrored, they are all drawn as textured
  /// triangles instead of an atlas, in the same order and with the same
  /// sampling — one call for up to 16,383 sprites.
  @override
  void flush(Canvas canvas, {BlendMode blendMode = BlendMode.modulate}) {
    if (_count == 0) return;

    if (_anyFlip) {
      _drawTriangles(canvas, blendMode);
    } else {
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
    }

    clear();
  }

  /// Draws every queued sprite as two textured triangles, the atlas sampled
  /// through an image shader: a mirrored sprite's corners are placed where
  /// its own draw puts them.
  void _drawTriangles(Canvas canvas, BlendMode blendMode) {
    final quads = math.min(_count, _maxQuadsPerDraw);
    if (_positions.length < quads * 8) {
      _positions = Float32List(quads * 8);
      _texCoords = Float32List(quads * 8);
      _vertexColors = Int32List(quads * 4);
      _indices = Uint16List(quads * 6);
      for (var q = 0; q < quads; q++) {
        final v = q * 4, k = q * 6;
        _indices
          ..[k] = v
          ..[k + 1] = v + 1
          ..[k + 2] = v + 2
          ..[k + 3] = v
          ..[k + 4] = v + 2
          ..[k + 5] = v + 3;
      }
    }
    final shader = ui.ImageShader(
      atlas,
      TileMode.clamp,
      TileMode.clamp,
      _identity,
      filterQuality: _paint.filterQuality,
    );
    final paint = _vertexPaint
      ..shader = shader
      ..filterQuality = _paint.filterQuality;
    for (var start = 0; start < _count; start += _maxQuadsPerDraw) {
      final n = math.min(_count - start, _maxQuadsPerDraw);
      for (var q = 0; q < n; q++) {
        _writeQuad(start + q, q);
      }
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_positions, 0, n * 8),
        textureCoordinates: Float32List.sublistView(_texCoords, 0, n * 8),
        colors: _allWhite
            ? null
            : Int32List.sublistView(_vertexColors, 0, n * 4),
        indices: Uint16List.sublistView(_indices, 0, n * 6),
      );
      canvas.drawVertices(vertices, blendMode, paint);
      vertices.dispose();
    }
    // The picture holds what it drew with; these handles are not needed.
    paint.shader = null;
    shader.dispose();
  }

  /// Writes sprite [i]'s corners as quad [q] of the triangle buffers.
  void _writeQuad(int i, int q) {
    final t = i * 4;
    final scos = _transforms[t], ssin = _transforms[t + 1];
    final left = _rects[t], top = _rects[t + 1];
    final w = _rects[t + 2] - left, h = _rects[t + 3] - top;
    final ax = _anchors[i * 2], ay = _anchors[i * 2 + 1];
    // Where the anchor lands: the atlas transform's translation is the
    // anchor already moved back.
    final px = _transforms[t + 2] + scos * ax - ssin * ay;
    final py = _transforms[t + 3] + ssin * ax + scos * ay;
    final flips = _flips[i];
    final fx = (flips & _flipXBit) != 0 ? -1.0 : 1.0;
    final fy = (flips & _flipYBit) != 0 ? -1.0 : 1.0;
    final p = q * 8;
    for (var corner = 0; corner < 4; corner++) {
      // Top-left, top-right, bottom-right, bottom-left.
      final u = corner == 1 || corner == 2 ? w : 0.0;
      final v = corner >= 2 ? h : 0.0;
      final lx = fx * (u - ax), ly = fy * (v - ay);
      _positions[p + corner * 2] = px + scos * lx - ssin * ly;
      _positions[p + corner * 2 + 1] = py + ssin * lx + scos * ly;
      _texCoords[p + corner * 2] = left + u;
      _texCoords[p + corner * 2 + 1] = top + v;
    }
    if (!_allWhite) {
      final c = _colors[i];
      final k = q * 4;
      _vertexColors
        ..[k] = c
        ..[k + 1] = c
        ..[k + 2] = c
        ..[k + 3] = c;
    }
  }

  /// Discard all queued sprites without drawing.
  void clear() {
    _count = 0;
    _allWhite = true;
    _anyFlip = false;
  }
}
