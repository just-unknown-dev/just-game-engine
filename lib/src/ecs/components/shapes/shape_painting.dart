/// Drawing the primitive shapes, shared by the shape components.
library;

import 'package:flutter/material.dart';

import 'shape_paint_style.dart';

/// Draws rectangles, circles and polygons the way the shape components do:
/// filled (when asked) in [ShapePaintStyle] fill, then outlined in the
/// stroke style.
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
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
    if (filled) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      canvas.drawRRect(rrect, paint);
    }
    canvas.drawRRect(rrect, _stroke(stroke, strokeWidth, rect));
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
    if (filled) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      canvas.drawCircle(center, radius, paint);
    }
    canvas.drawCircle(center, radius, _stroke(stroke, strokeWidth, rect));
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
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (closed) path.close();
    final rect = boundsOf(points);
    if (filled && closed) {
      final paint = Paint();
      fill.applyTo(paint, rect);
      canvas.drawPath(path, paint);
    }
    canvas.drawPath(path, _stroke(stroke, strokeWidth, rect));
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

  static Paint _stroke(ShapePaintStyle style, double width, Rect rect) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    style.applyTo(paint, rect);
    return paint;
  }
}
