library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import 'shape_paint_cache.dart';
import 'shape_paint_style.dart';

/// Line shape component.
///
/// Describes a straight line segment in local (entity-relative) space.
/// Both [start] and [end] are relative to the entity's
/// [TransformComponent] position.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class LineComponent extends RenderableComponent {
  /// Start point of the line in local space.
  Offset start;

  /// End point of the line in local space.
  Offset end;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Thickness of the line.
  double strokeWidth;

  /// Whether to draw rounded line caps (`true`) or square/butt caps (`false`).
  bool roundCaps;

  /// A white line 1 world unit wide, with butt caps, from [start] (the
  /// entity's position by default) to [end].
  factory LineComponent({
    Offset start = Offset.zero,
    required Offset end,
    ShapePaintStyle strokeStyle = const ShapePaintStyle(color: Colors.white),
    double strokeWidth = 1.0,
    bool roundCaps = false,
  }) {
    late LineComponent self;
    self = LineComponent._internal(
      start: start,
      end: end,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
      roundCaps: roundCaps,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () => Rect.fromPoints(
          self.start - Offset(self.strokeWidth, self.strokeWidth),
          self.end + Offset(self.strokeWidth, self.strokeWidth),
        ),
        onRender: (canvas, _) => self._draw(canvas, null, 1.0),
        onRenderFaded: (canvas, _, tint, opacity) =>
            self._drawFaded(canvas, tint, opacity),
      ),
    );
    return self;
  }

  LineComponent._internal({
    required this.start,
    required this.end,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.roundCaps,
    required super.renderable,
  });

  // The paint and the gradient rectangle, kept between frames.
  final ShapePaintCache _paints = ShapePaintCache();
  Offset _rectStart = Offset.zero;
  Offset _rectEnd = Offset.zero;
  double _rectWidth = double.nan;
  Rect _rect = Rect.zero;

  void _draw(Canvas canvas, Color? tint, double opacity) {
    if (!ShapePaintCache.shows(strokeStyle)) return;
    if (start != _rectStart || end != _rectEnd || strokeWidth != _rectWidth) {
      _rectStart = start;
      _rectEnd = end;
      _rectWidth = strokeWidth;
      _rect = Rect.fromPoints(start, end).inflate(strokeWidth);
    }
    final paint = _paints.stroke(
      strokeStyle,
      _rect,
      strokeWidth,
      tint,
      opacity,
    );
    final cap = roundCaps ? StrokeCap.round : StrokeCap.butt;
    if (paint.strokeCap != cap) paint.strokeCap = cap;
    canvas.drawLine(start, end, paint);
  }

  bool _drawFaded(Canvas canvas, Color? tint, double opacity) {
    if (opacity == 0) return true; // Nothing a layer would show.
    if (!ShapePaintCache.canFold(strokeStyle)) return false;
    _draw(canvas, tint, opacity);
    return true;
  }

  /// Length of the line segment.
  double get length => (end - start).distance;

  @override
  String toString() =>
      'Line(start=$start, end=$end, strokeStyle=$strokeStyle, '
      'stroke=$strokeWidth)';
}
