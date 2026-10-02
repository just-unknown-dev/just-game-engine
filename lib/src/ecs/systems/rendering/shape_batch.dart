/// Plain rectangles and circles drawn together as one set of triangles.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../components/components.dart';
import '../../../subsystems/rendering/impl/renderable.dart';

/// Collects [RectangleComponent]s and [CircleComponent]s into one
/// [Canvas.drawVertices] call — the shape counterpart of a sprite batch,
/// used by `RenderSystem(batchShapes: true)`.
///
/// Only shapes the triangles can draw exactly as the canvas would, bar the
/// edges, are taken: a plain-colour fill and outline (no gradient), square
/// corners, an outline wider than zero (zero is the canvas's one-pixel
/// hairline), full opacity and no tint. [tryAdd] refuses the rest, and they
/// draw one by one as before.
///
/// What differs is the edges: triangles are not anti-aliased, so a batched
/// shape's edge is hard where the canvas would smooth it, and a circle is a
/// polygon of 16 or 24 sides. Hence opt-in.
class ShapeBatch {
  // Two floats per vertex, one ARGB colour per vertex, three vertices per
  // triangle. Kept between frames and grown as needed.
  Float32List _positions = Float32List(2 * _initialVertices);
  Int32List _colors = Int32List(_initialVertices);
  int _count = 0;

  static const int _initialVertices = 1536;

  // The colours come from the vertices alone (BlendMode.dst); the paint
  // only has to be opaque.
  final Paint _paint = Paint();

  // The placement of the shape being added: x' = tx + a·x + c·y,
  // y' = ty + b·x + d·y — the canvas's translate, rotate, scale.
  double _tx = 0, _ty = 0, _a = 1, _b = 0, _c = 0, _d = 1;

  /// Whether nothing is waiting to be drawn.
  bool get isEmpty => _count == 0;

  /// Vertices waiting to be drawn.
  int get vertexCount => _count;

  /// Adds the shape [component] draws, placed as [renderable] is. False —
  /// and nothing added — when the shape cannot be batched.
  bool tryAdd(RenderableComponent component, Renderable renderable) {
    if (renderable.opacity < 1.0 || renderable.tint != null) return false;
    if (component is RectangleComponent) {
      return _addRect(component, renderable);
    }
    if (component is CircleComponent) return _addCircle(component, renderable);
    return false;
  }

  /// Draws everything added since the last flush, in the order it was
  /// added, and empties the batch.
  void flush(Canvas canvas) {
    if (_count == 0) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_positions, 0, _count * 2),
      colors: Int32List.sublistView(_colors, 0, _count),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
    _count = 0;
  }

  /// Drops everything added since the last flush.
  void clear() => _count = 0;

  // ── Shapes ────────────────────────────────────────────────────────────

  /// Which of fill and outline [filled], [fill] and [stroke] draw, or null
  /// when either cannot be drawn as triangles.
  static (bool, bool)? _parts(
    bool filled,
    ShapePaintStyle fill,
    ShapePaintStyle stroke,
    double strokeWidth,
  ) {
    final fills = filled && ShapePaintCache.shows(fill);
    final strokes = ShapePaintCache.shows(stroke);
    if (fills && fill.gradient != null) return null;
    if (strokes && (stroke.gradient != null || !(strokeWidth > 0))) {
      return null;
    }
    return (fills, strokes);
  }

  bool _addRect(RectangleComponent c, Renderable r) {
    if (!c.drawsOwnShape || c.cornerRadius != 0) return false;
    final parts = _parts(c.filled, c.fillStyle, c.strokeStyle, c.strokeWidth);
    if (parts == null) return false;
    final (fills, strokes) = parts;
    _place(r);
    final hw = c.width.abs() / 2, hh = c.height.abs() / 2;
    if (fills) _quad(-hw, -hh, hw, hh, c.fillStyle.color.toARGB32());
    if (strokes) {
      // A mitred outline is the rectangle grown by half the width, less
      // the one shrunk by it: the top and bottom bands run the full width,
      // the sides fill the gap between them — no pixel covered twice.
      final s = c.strokeWidth / 2;
      final color = c.strokeStyle.color.toARGB32();
      if (hw <= s || hh <= s) {
        _quad(-hw - s, -hh - s, hw + s, hh + s, color);
      } else {
        _quad(-hw - s, -hh - s, hw + s, -hh + s, color);
        _quad(-hw - s, hh - s, hw + s, hh + s, color);
        _quad(-hw - s, -hh + s, -hw + s, hh - s, color);
        _quad(hw - s, -hh + s, hw + s, hh - s, color);
      }
    }
    return true;
  }

  bool _addCircle(CircleComponent c, Renderable r) {
    if (!c.drawsOwnShape || c.radius < 0) return false;
    final parts = _parts(c.filled, c.fillStyle, c.strokeStyle, c.strokeWidth);
    if (parts == null) return false;
    final (fills, strokes) = parts;
    _place(r);
    final scale = math.max(r.scale.x.abs(), r.scale.y.abs());
    final unit = c.radius * scale < 8 ? _circle16 : _circle24;
    final n = unit.length ~/ 2;
    final radius = c.radius;
    if (fills) {
      final color = c.fillStyle.color.toARGB32();
      _reserve(3 * n);
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        _vertex(0, 0, color);
        _vertex(unit[2 * i] * radius, unit[2 * i + 1] * radius, color);
        _vertex(unit[2 * j] * radius, unit[2 * j + 1] * radius, color);
      }
    }
    if (strokes) {
      final color = c.strokeStyle.color.toARGB32();
      final s = c.strokeWidth / 2;
      final outer = radius + s;
      final inner = math.max(radius - s, 0.0);
      _reserve(6 * n);
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final ci = unit[2 * i], si = unit[2 * i + 1];
        final cj = unit[2 * j], sj = unit[2 * j + 1];
        _vertex(ci * inner, si * inner, color);
        _vertex(ci * outer, si * outer, color);
        _vertex(cj * outer, sj * outer, color);
        _vertex(ci * inner, si * inner, color);
        _vertex(cj * outer, sj * outer, color);
        _vertex(cj * inner, sj * inner, color);
      }
    }
    return true;
  }

  // ── Vertices ──────────────────────────────────────────────────────────

  void _place(Renderable r) {
    final sx = r.scale.x, sy = r.scale.y;
    _tx = r.position.x;
    _ty = r.position.y;
    final angle = r.rotation;
    if (angle == 0.0) {
      _a = sx;
      _b = 0;
      _c = 0;
      _d = sy;
    } else {
      final cos = math.cos(angle), sin = math.sin(angle);
      _a = cos * sx;
      _b = sin * sx;
      _c = -sin * sy;
      _d = cos * sy;
    }
  }

  void _quad(double l, double t, double r, double b, int color) {
    _reserve(6);
    _vertex(l, t, color);
    _vertex(r, t, color);
    _vertex(r, b, color);
    _vertex(l, t, color);
    _vertex(r, b, color);
    _vertex(l, b, color);
  }

  void _vertex(double x, double y, int color) {
    final i = _count * 2;
    _positions[i] = _tx + _a * x + _c * y;
    _positions[i + 1] = _ty + _b * x + _d * y;
    _colors[_count++] = color;
  }

  void _reserve(int vertices) {
    final needed = _count + vertices;
    if (needed <= _colors.length) return;
    var capacity = _colors.length * 2;
    while (capacity < needed) {
      capacity *= 2;
    }
    _positions = Float32List(2 * capacity)..setAll(0, _positions);
    _colors = Int32List(capacity)..setAll(0, _colors);
  }

  static final Float64List _circle16 = _unitCircle(16);
  static final Float64List _circle24 = _unitCircle(24);

  static Float64List _unitCircle(int sides) {
    final out = Float64List(2 * sides);
    for (var i = 0; i < sides; i++) {
      final angle = 2 * math.pi * i / sides;
      out[2 * i] = math.cos(angle);
      out[2 * i + 1] = math.sin(angle);
    }
    return out;
  }
}
