library;

import 'package:flutter/material.dart';
import 'package:meta/meta.dart' show internal;

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import 'shape_paint_cache.dart';
import 'shape_paint_style.dart';
import 'shape_renderable.dart';
import 'shape_painting.dart';

/// Circle shape component.
///
/// Describes a circle centered on the entity's [TransformComponent] position.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading [radius], [fillStyle], [strokeStyle], [filled]
/// and [strokeWidth] at draw-time so mutations are reflected immediately.
class CircleComponent extends RenderableComponent {
  /// Radius of the circle in world units.
  double radius;

  /// Fill style, combining color tint with optional gradient.
  ShapePaintStyle fillStyle;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Whether the circle is filled. Its outline ([strokeStyle]) is drawn
  /// either way, unless fully transparent.
  bool filled;

  /// Width of the outline, in world units; drawn whether or not [filled].
  double strokeWidth;

  /// A circle of [radius] filled white, with a translucent white outline 1
  /// world unit wide.
  factory CircleComponent({
    required double radius,
    ShapePaintStyle fillStyle = const ShapePaintStyle(color: Colors.white),
    ShapePaintStyle strokeStyle = const ShapePaintStyle(
      color: Color(0x73FFFFFF),
    ),
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late CircleComponent self;
    final shape = ShapeRenderable(
      getBoundsCallback: () => Rect.fromCircle(
        center: Offset.zero,
        radius: self.radius + self.strokeWidth,
      ),
      onRender: (canvas, _) => self._draw(canvas, null, 1.0),
      onRenderFaded: (canvas, _, tint, opacity) =>
          self._drawFaded(canvas, tint, opacity),
      onRenderMoved: (canvas, dx, dy) => self._drawMoved(canvas, dx, dy),
    );
    self = CircleComponent._internal(
      radius: radius,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
      renderable: shape,
    ).._shape = shape;
    return self;
  }

  CircleComponent._internal({
    required this.radius,
    required this.fillStyle,
    required this.strokeStyle,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  // The renderable this component made, which draws from its fields.
  late final CustomRenderable _shape;

  // Paints and the gradient rectangle, kept between frames.
  final ShapePaintCache _paints = ShapePaintCache();
  double _rectRadius = double.nan;
  Rect _rect = Rect.zero;

  /// Whether [renderable] is still the one this component made, so what it
  /// draws is what the fields say — the question a shape batch asks.
  @internal
  bool get drawsOwnShape => identical(renderable, _shape);

  void _draw(Canvas canvas, Color? tint, double opacity) {
    if (radius != _rectRadius) {
      _rectRadius = radius;
      _rect = Rect.fromCircle(center: Offset.zero, radius: radius);
    }
    ShapePainting.circleWith(
      canvas,
      _paints,
      Offset.zero,
      radius,
      _rect,
      fill: fillStyle,
      stroke: strokeStyle,
      strokeWidth: strokeWidth,
      filled: filled,
      tint: tint,
      opacity: opacity,
    );
  }

  bool _drawMoved(Canvas canvas, double dx, double dy) {
    // A gradient is laid out around the origin: drawn transformed.
    if (fillStyle.gradient != null || strokeStyle.gradient != null) {
      return false;
    }
    ShapePainting.circleWith(
      canvas,
      _paints,
      Offset(dx, dy),
      radius,
      Rect.zero, // Only a gradient reads it.
      fill: fillStyle,
      stroke: strokeStyle,
      strokeWidth: strokeWidth,
      filled: filled,
    );
    return true;
  }

  bool _drawFaded(Canvas canvas, Color? tint, double opacity) {
    if (opacity == 0) return true; // Nothing a layer would show.
    if (!ShapePainting.canFold(
      filled: filled,
      fill: fillStyle,
      stroke: strokeStyle,
    )) {
      return false;
    }
    _draw(canvas, tint, opacity);
    return true;
  }

  @override
  String toString() =>
      'Circle(r=$radius, fillStyle=$fillStyle, strokeStyle=$strokeStyle, '
      'filled=$filled, stroke=$strokeWidth)';
}
