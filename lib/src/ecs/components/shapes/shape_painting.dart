/// Drawing the primitive shapes, shared by the shape components.
library;

import 'package:flutter/material.dart';

import 'shape_paint_cache.dart';
import 'shape_paint_style.dart';

/// Draws rectangles, circles and polygons the way the shape components do:
/// filled (when asked) in [ShapePaintStyle] fill, then outlined in the
/// stroke style.
///
/// These build their paints on every call — fine for one-off drawing. The
/// shape components keep theirs in a [ShapePaintCache] and draw with
/// [rectWith], [circleWith] and [pathWith].
abstract final class ShapePainting {
  /// A rectangle, [cornerRadius] rounding its corners.
  static void rect(
    Canvas canvas,
    Rect rect, {
    double cornerRadius = 0,
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    double strokeWidth = 1,
    bool filled = true,
  }) {
    final rrect = cornerRadius == 0
        ? null
        : RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
    if (filled && ShapePaintCache.shows(fill)) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      _drawRect(canvas, rect, rrect, paint);
    }
    if (ShapePaintCache.shows(stroke)) {
      _drawRect(canvas, rect, rrect, _stroke(stroke, strokeWidth, rect));
    }
  }

  /// A circle of [radius] around [center].
  static void circle(
    Canvas canvas,
    Offset center,
    double radius, {
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    double strokeWidth = 1,
    bool filled = true,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (filled && ShapePaintCache.shows(fill)) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      canvas.drawCircle(center, radius, paint);
    }
    if (ShapePaintCache.shows(stroke)) {
      canvas.drawCircle(center, radius, _stroke(stroke, strokeWidth, rect));
    }
  }

  /// The polygon through [points]; an open one ([closed] false) is a line
  /// and is never filled.
  static void polygon(
    Canvas canvas,
    List<Offset> points, {
    bool closed = true,
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    double strokeWidth = 1,
    bool filled = true,
  }) {
    if (points.isEmpty) return;
    final path = pathThrough(points, closed: closed);
    final rect = boundsOf(points);
    if (filled && closed && ShapePaintCache.shows(fill)) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      canvas.drawPath(path, paint);
    }
    if (ShapePaintCache.shows(stroke)) {
      canvas.drawPath(path, _stroke(stroke, strokeWidth, rect));
    }
  }

  /// [rect] as a shape component draws it, with paints from [paints]:
  /// filled when [filled], then outlined. [rrect] is [rect] with its corners
  /// rounded, or null for square ones. [tint] and [opacity] are folded into
  /// the colours; see [ShapePaintCache.fill].
  static void rectWith(
    Canvas canvas,
    ShapePaintCache paints,
    Rect rect,
    RRect? rrect, {
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    required double strokeWidth,
    required bool filled,
    Color? tint,
    double opacity = 1.0,
  }) {
    if (filled && ShapePaintCache.shows(fill)) {
      _drawRect(canvas, rect, rrect, paints.fill(fill, rect, tint, opacity));
    }
    if (ShapePaintCache.shows(stroke)) {
      _drawRect(
        canvas,
        rect,
        rrect,
        paints.stroke(stroke, rect, strokeWidth, tint, opacity),
      );
    }
  }

  /// A circle as a shape component draws it; see [rectWith].
  static void circleWith(
    Canvas canvas,
    ShapePaintCache paints,
    Offset center,
    double radius,
    Rect rect, {
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    required double strokeWidth,
    required bool filled,
    Color? tint,
    double opacity = 1.0,
  }) {
    if (filled && ShapePaintCache.shows(fill)) {
      canvas.drawCircle(center, radius, paints.fill(fill, rect, tint, opacity));
    }
    if (ShapePaintCache.shows(stroke)) {
      canvas.drawCircle(
        center,
        radius,
        paints.stroke(stroke, rect, strokeWidth, tint, opacity),
      );
    }
  }

  /// A path as a shape component draws it; see [rectWith]. [fillable] is
  /// false for an open path, which is only ever outlined.
  static void pathWith(
    Canvas canvas,
    ShapePaintCache paints,
    Path path,
    Rect rect, {
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
    required double strokeWidth,
    required bool filled,
    bool fillable = true,
    Color? tint,
    double opacity = 1.0,
  }) {
    if (filled && fillable && ShapePaintCache.shows(fill)) {
      canvas.drawPath(path, paints.fill(fill, rect, tint, opacity));
    }
    if (ShapePaintCache.shows(stroke)) {
      canvas.drawPath(
        path,
        paints.stroke(stroke, rect, strokeWidth, tint, opacity),
      );
    }
  }

  /// Whether a shape filled when [filled] and outlined in [stroke] can take a
  /// tint and an opacity in its paints rather than through a layer: when it
  /// draws exactly one thing, in a plain colour.
  ///
  /// Two overlapping draws cannot. A layer fades the outline and the fill
  /// together; fading each alone lets the fill show through the outline
  /// where they overlap.
  static bool canFold({
    required bool filled,
    required ShapePaintStyle fill,
    required ShapePaintStyle stroke,
  }) {
    final fills = filled && ShapePaintCache.shows(fill);
    final strokes = ShapePaintCache.shows(stroke);
    if (fills && strokes) return false;
    if (fills) return ShapePaintCache.canFold(fill);
    if (strokes) return ShapePaintCache.canFold(stroke);
    return true;
  }

  /// The path through [points], closed back to the first when [closed].
  static Path pathThrough(List<Offset> points, {bool closed = true}) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    if (closed) path.close();
    return path;
  }

  /// The smallest rectangle holding [points]; empty for none.
  static Rect boundsOf(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = minX;
    var minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // Square corners draw as a plain rectangle: the same pixels as a rounded
  // rectangle of radius 0, without the rounded one's 12-float buffer.
  static void _drawRect(Canvas canvas, Rect rect, RRect? rrect, Paint paint) {
    if (rrect == null) {
      canvas.drawRect(rect, paint);
    } else {
      canvas.drawRRect(rrect, paint);
    }
  }

  static Paint _stroke(ShapePaintStyle style, double width, Rect rect) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    style.applyTo(paint, rect);
    return paint;
  }
}
