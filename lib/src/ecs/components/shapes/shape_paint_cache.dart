/// The paints a shape component draws with, kept between frames.
library;

import 'package:flutter/material.dart';

import 'shape_paint_style.dart';

/// One shape's fill and stroke paints, brought up to date only when what
/// they are made from changes.
///
/// [ShapePainting]'s static functions build two [Paint]s — each with its
/// own buffer — per shape per frame, and a gradient shader on top. A shape
/// component keeps one of these instead: its paints are re-made only when the
/// style, the gradient's rectangle, the stroke width, or the tint and opacity
/// folded into the colour change.
///
/// Styles are compared by identity: [ShapePaintStyle] and [ShapeGradient]
/// are immutable, so assign a new style to change one.
class ShapePaintCache {
  /// The fill paint, as last prepared by [fill].
  final Paint fillPaint = Paint();

  /// The stroke paint, as last prepared by [stroke].
  final Paint strokePaint = Paint()..style = PaintingStyle.stroke;

  final _Applied _fill = _Applied();
  final _Applied _stroke = _Applied();

  /// Whether [style] draws anything: a gradient, or a colour that is not
  /// fully transparent. Drawing a transparent colour changes no pixel.
  static bool shows(ShapePaintStyle style) =>
      style.gradient != null || style.color.a > 0;

  /// Whether [tint] and [opacity] can be folded into [style]'s paint: only
  /// a plain colour can take them — a gradient already uses the paint's
  /// colour filter.
  static bool canFold(ShapePaintStyle style) => style.gradient == null;

  /// [fillPaint], painting [style] over [rect], with [tint] and [opacity]
  /// multiplied into its colour (a plain [style] only; see [canFold]).
  Paint fill(
    ShapePaintStyle style,
    Rect rect, [
    Color? tint,
    double opacity = 1.0,
  ]) {
    _fill.update(fillPaint, style, rect, tint, opacity);
    return fillPaint;
  }

  /// [strokePaint], [width] wide, painting [style] over [rect], with [tint]
  /// and [opacity] multiplied into its colour (a plain [style] only).
  Paint stroke(
    ShapePaintStyle style,
    Rect rect,
    double width, [
    Color? tint,
    double opacity = 1.0,
  ]) {
    if (strokePaint.strokeWidth != width) strokePaint.strokeWidth = width;
    _stroke.update(strokePaint, style, rect, tint, opacity);
    return strokePaint;
  }

  /// [color] as seen through a modulate layer of [tint] at [opacity] —
  /// what an offscreen layer would have made of it.
  static Color fold(Color color, Color? tint, double opacity) {
    if (tint == null) {
      return opacity == 1.0
          ? color
          : color.withValues(alpha: color.a * opacity);
    }
    return color.withValues(
      alpha: color.a * tint.a * opacity,
      red: color.r * tint.r,
      green: color.g * tint.g,
      blue: color.b * tint.b,
    );
  }
}

/// What one paint was last made from.
class _Applied {
  ShapePaintStyle? style;
  Rect rect = Rect.zero;
  Color? tint;
  double opacity = 1.0;

  void update(
    Paint paint,
    ShapePaintStyle next,
    Rect nextRect,
    Color? nextTint,
    double nextOpacity,
  ) {
    final gradient = next.gradient;
    if (identical(next, style) &&
        nextTint == tint &&
        nextOpacity == opacity &&
        (gradient == null || nextRect == rect)) {
      return;
    }
    style = next;
    rect = nextRect;
    tint = nextTint;
    opacity = nextOpacity;
    if (gradient == null) {
      // Resetting only what is set: the shader and filter setters allocate
      // the paint's object list even to store a null.
      if (paint.shader != null) paint.shader = null;
      if (paint.colorFilter != null) paint.colorFilter = null;
      paint.color = ShapePaintCache.fold(next.color, nextTint, nextOpacity);
    } else {
      assert(nextTint == null && nextOpacity == 1.0, 'cannot fold a gradient');
      paint
        ..color = next.color
        ..shader = gradient.createShader(nextRect)
        ..colorFilter = ColorFilter.mode(next.color, next.blendMode);
    }
  }
}
