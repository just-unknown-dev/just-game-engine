library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';

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

  /// Fill colour. Used when [filled] is `true`.
  Color color;

  /// Whether the rectangle is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  /// Corner radius for rounded rectangles. `0` produces sharp corners.
  double cornerRadius;

  factory RectangleComponent({
    required double width,
    required double height,
    Color color = Colors.white,
    bool filled = true,
    double strokeWidth = 1.0,
    double cornerRadius = 0.0,
  }) {
    late RectangleComponent self;
    self = RectangleComponent._internal(
      width: width,
      height: height,
      color: color,
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
          if (self.filled) {
            canvas.drawRRect(rrect, Paint()..color = self.color);
          }
          canvas.drawRRect(
            rrect,
            Paint()
              ..color = self.filled
                  ? Colors.white.withValues(alpha: 0.45)
                  : self.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = self.strokeWidth,
          );
        },
      ),
    );
    return self;
  }

  RectangleComponent._internal({
    required this.width,
    required this.height,
    required this.color,
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
      'Rectangle(${width}x$height, color=$color, filled=$filled, '
      'stroke=$strokeWidth, radius=$cornerRadius)';
}
