library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';

/// Polygon shape component.
///
/// Describes a convex or concave polygon defined by a list of vertices
/// relative to the entity's [TransformComponent] position.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class PolygonComponent extends RenderableComponent {
  /// Vertices of the polygon in local (entity-relative) space.
  ///
  /// The polygon is drawn by connecting consecutive vertices and closing
  /// the path back to the first vertex.
  List<Offset> vertices;

  /// Fill colour. Used when [filled] is `true`.
  Color color;

  /// Whether the polygon is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  factory PolygonComponent({
    required List<Offset> vertices,
    Color color = Colors.white,
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late PolygonComponent self;
    self = PolygonComponent._internal(
      vertices: vertices,
      color: color,
      filled: filled,
      strokeWidth: strokeWidth,
      renderable: CustomRenderable(
        layer: 8,
        getBoundsCallback: () {
          if (self.vertices.isEmpty) return Rect.zero;
          double minX = self.vertices.first.dx, maxX = minX;
          double minY = self.vertices.first.dy, maxY = minY;
          for (final v in self.vertices) {
            if (v.dx < minX) minX = v.dx;
            if (v.dx > maxX) maxX = v.dx;
            if (v.dy < minY) minY = v.dy;
            if (v.dy > maxY) maxY = v.dy;
          }
          return Rect.fromLTRB(
            minX - self.strokeWidth,
            minY - self.strokeWidth,
            maxX + self.strokeWidth,
            maxY + self.strokeWidth,
          );
        },
        onRender: (canvas, _) {
          if (self.vertices.isEmpty) return;
          final path = Path()
            ..moveTo(self.vertices.first.dx, self.vertices.first.dy);
          for (final v in self.vertices.skip(1)) {
            path.lineTo(v.dx, v.dy);
          }
          path.close();
          if (self.filled) {
            canvas.drawPath(path, Paint()..color = self.color);
          }
          canvas.drawPath(
            path,
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

  PolygonComponent._internal({
    required this.vertices,
    required this.color,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  @override
  String toString() =>
      'Polygon(${vertices.length} vertices, color=$color, filled=$filled, '
      'stroke=$strokeWidth)';
}
