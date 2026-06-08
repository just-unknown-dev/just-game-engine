library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';
import 'shape_paint_style.dart';

/// Capsule shape component.
///
/// Describes a capsule (a rectangle with two semicircular end caps) centered
/// on the entity's [TransformComponent] position.
/// When [width] >= [height] the caps are on the left/right sides;
/// when [height] > [width] the caps are on the top/bottom sides.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class CapsuleComponent extends RenderableComponent {
  /// Width of the bounding box in world units.
  double width;

  /// Height of the bounding box in world units.
  double height;

  /// Fill style, combining color tint with optional gradient.
  ShapePaintStyle fillStyle;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Whether the capsule is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  factory CapsuleComponent({
    required double width,
    required double height,
    ShapePaintStyle fillStyle = const ShapePaintStyle(color: Colors.white),
    ShapePaintStyle strokeStyle = const ShapePaintStyle(
      color: Color(0x73FFFFFF),
    ),
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late CapsuleComponent self;
    self = CapsuleComponent._internal(
      width: width,
      height: height,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
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
            Radius.circular(self.capRadius),
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

  CapsuleComponent._internal({
    required this.width,
    required this.height,
    required this.fillStyle,
    required this.strokeStyle,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  /// Radius of the semicircular end caps — half of the shorter side.
  double get capRadius => width < height ? width / 2.0 : height / 2.0;

  @override
  String toString() =>
      'Capsule(${width}x$height, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth)';
}
