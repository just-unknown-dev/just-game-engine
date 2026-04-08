library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';

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

  /// Fill colour. Used when [filled] is `true`.
  Color color;

  /// Whether the capsule is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  factory CapsuleComponent({
    required double width,
    required double height,
    Color color = Colors.white,
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late CapsuleComponent self;
    self = CapsuleComponent._internal(
      width: width,
      height: height,
      color: color,
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

  CapsuleComponent._internal({
    required this.width,
    required this.height,
    required this.color,
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
      'Capsule(${width}x$height, color=$color, filled=$filled, '
      'stroke=$strokeWidth)';
}
