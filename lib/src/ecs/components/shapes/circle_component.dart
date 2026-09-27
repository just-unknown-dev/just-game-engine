library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';
import 'shape_paint_style.dart';
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

  /// Whether the circle is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

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
    self = CircleComponent._internal(
      radius: radius,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () => Rect.fromCircle(
          center: Offset.zero,
          radius: self.radius + self.strokeWidth,
        ),
        onRender: (canvas, _) => ShapePainting.circle(
          canvas,
          Offset.zero,
          self.radius,
          fill: self.fillStyle,
          stroke: self.strokeStyle,
          strokeWidth: self.strokeWidth,
          filled: self.filled,
        ),
      ),
    );
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

  @override
  String toString() =>
      'Circle(r=$radius, fillStyle=$fillStyle, strokeStyle=$strokeStyle, '
      'filled=$filled, stroke=$strokeWidth)';
}
