library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';

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

  /// Stroke colour.
  Color color;

  /// Thickness of the line.
  double strokeWidth;

  /// Whether to draw rounded line caps (`true`) or square/butt caps (`false`).
  bool roundCaps;

  factory LineComponent({
    Offset start = Offset.zero,
    required Offset end,
    Color color = Colors.white,
    double strokeWidth = 1.0,
    bool roundCaps = false,
  }) {
    late LineComponent self;
    self = LineComponent._internal(
      start: start,
      end: end,
      color: color,
      strokeWidth: strokeWidth,
      roundCaps: roundCaps,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () => Rect.fromPoints(
          self.start - Offset(self.strokeWidth, self.strokeWidth),
          self.end + Offset(self.strokeWidth, self.strokeWidth),
        ),
        onRender: (canvas, _) {
          canvas.drawLine(
            self.start,
            self.end,
            Paint()
              ..color = self.color
              ..strokeWidth = self.strokeWidth
              ..strokeCap = self.roundCaps ? StrokeCap.round : StrokeCap.butt,
          );
        },
      ),
    );
    return self;
  }

  LineComponent._internal({
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
    required this.roundCaps,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  /// Length of the line segment.
  double get length => (end - start).distance;

  @override
  String toString() =>
      'Line(start=$start, end=$end, color=$color, stroke=$strokeWidth)';
}
