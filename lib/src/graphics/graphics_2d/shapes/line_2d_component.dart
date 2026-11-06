library;

import 'package:flutter/material.dart';

import '../../../rendering/renderable_component.dart';
import '../../../rendering/renderable.dart';
import 'shape_paint_cache.dart';
import '../../../foundation/shape_paint_style.dart';
import '../../../foundation/solid_shape_2d.dart';
import 'shape_2d_look.dart';

/// Line shape component.
///
/// Describes a straight line segment in local (entity-relative) space.
/// Both [start] and [end] are relative to the entity's
/// [TransformComponent] position.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class Line2DComponent extends RenderableComponent
    implements SolidShape2DSource, Shape2DLook {
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
  factory Line2DComponent({
    Offset start = Offset.zero,
    required Offset end,
    ShapePaintStyle strokeStyle = const ShapePaintStyle(color: Colors.white),
    double strokeWidth = 1.0,
    bool roundCaps = false,
  }) {
    late Line2DComponent self;
    self = Line2DComponent._internal(
      start: start,
      end: end,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
      roundCaps: roundCaps,
      renderable: CustomRenderable(
        // Whichever way the line runs: grown from the corners its ends
        // make, wide enough for its width and its caps.
        boundsOf: () =>
            Rect.fromPoints(self.start, self.end).inflate(self.strokeWidth),
        onRender: (canvas, _) => self._draw(canvas, null, 1.0),
        onRenderFaded: (canvas, _, tint, opacity) =>
            self._drawFaded(canvas, tint, opacity),
      ),
    );
    return self;
  }

  Line2DComponent._internal({
    required this.start,
    required this.end,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.roundCaps,
    required super.renderable,
  });

  (Offset, Offset, ShapePaintStyle, double, bool, Renderable)? _look;

  @override
  Object get look {
    final l = _look;
    if (l != null &&
        l.$1 == start &&
        l.$2 == end &&
        identical(l.$3, strokeStyle) &&
        l.$4 == strokeWidth &&
        l.$5 == roundCaps &&
        identical(l.$6, renderable)) {
      return l;
    }
    return _look = (
      start,
      end,
      strokeStyle,
      strokeWidth,
      roundCaps,
      renderable,
    );
  }

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
  SolidLine2D? _solid;

  /// The line, [strokeWidth] thick: what a collider matching the shape
  /// takes.
  @override
  SolidShape2D get solidShape2D =>
      _solid = SolidLine2D.reuse(_solid, start, end, strokeWidth);

  double get length => (end - start).distance;

  @override
  String toString() =>
      'Line(start=$start, end=$end, strokeStyle=$strokeStyle, '
      'stroke=$strokeWidth)';
}
