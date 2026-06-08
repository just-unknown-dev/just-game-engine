library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';
import 'shape_paint_style.dart';

/// Rectangle shape component.
///
/// Describes an axis-aligned rectangle centered on the entity's
/// [TransformComponent] position. Set [cornerRadius] > 0 for rounded corners.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class RectangleComponent extends RenderableComponent {
  /// Width of the rectangle in world units.
  double width;

  /// Height of the rectangle in world units.
  double height;

  /// Fill style, combining color tint with optional gradient.
  ShapePaintStyle fillStyle;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Whether the rectangle is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  /// Corner radius for rounded rectangles. `0` produces sharp corners.
  double cornerRadius;

  factory RectangleComponent({
    required double width,
    required double height,
    ShapePaintStyle fillStyle = const ShapePaintStyle(color: Colors.white),
    ShapePaintStyle strokeStyle = const ShapePaintStyle(
      color: Color(0x73FFFFFF),
    ),
    bool filled = true,
    double strokeWidth = 1.0,
    double cornerRadius = 0.0,
  }) {
    late RectangleComponent self;
    self = RectangleComponent._internal(
      width: width,
      height: height,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () => Rect.fromCenter(
          center: Offset.zero,
          width: self.width + self.strokeWidth * 2,
          height: self.height + self.strokeWidth * 2,
        ),
        onRender: (canvas, _) {
          final rrect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: self.width,
              height: self.height,
            ),
            Radius.circular(self.cornerRadius),
          );
          final shapeRect = rrect.outerRect;
          if (self.filled) {
            final fillPaint = Paint();
            self.fillStyle.applyTo(fillPaint, shapeRect);
            canvas.drawRRect(rrect, fillPaint);
          }

          final strokePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = self.strokeWidth;
          self.strokeStyle.applyTo(strokePaint, shapeRect);
          canvas.drawRRect(rrect, strokePaint);
        },
      ),
    );
    return self;
  }

  RectangleComponent._internal({
    required this.width,
    required this.height,
    required this.fillStyle,
    required this.strokeStyle,
    required this.filled,
    required this.strokeWidth,
    required this.cornerRadius,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  /// Convenience getter for the size as a [Size] object.
  Size get size => Size(width, height);

  @override
  String toString() =>
      'Rectangle(${width}x$height, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth, radius=$cornerRadius)';
}
