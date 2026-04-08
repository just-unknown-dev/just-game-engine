library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';

/// Circle shape component.
///
/// Describes a circle centered on the entity's [TransformComponent] position.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading [radius], [color], [filled] and [strokeWidth]
/// at draw-time so mutations are reflected immediately.
class CircleComponent extends RenderableComponent {
  /// Radius of the circle in world units.
  double radius;

  /// Fill colour. Used when [filled] is `true`.
  Color color;

  /// Whether the circle is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  factory CircleComponent({
    required double radius,
    Color color = Colors.white,
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late CircleComponent self;
    self = CircleComponent._internal(
      radius: radius,
      color: color,
      filled: filled,
      strokeWidth: strokeWidth,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () => Rect.fromCircle(
          center: Offset.zero,
          radius: self.radius + self.strokeWidth,
        ),
        onRender: (canvas, _) {
          if (self.filled) {
            canvas.drawCircle(
              Offset.zero,
              self.radius,
              Paint()..color = self.color,
            );
          }
          canvas.drawCircle(
            Offset.zero,
            self.radius,
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

  CircleComponent._internal({
    required this.radius,
    required this.color,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  @override
  String toString() =>
      'Circle(r=$radius, color=$color, filled=$filled, stroke=$strokeWidth)';
}
