library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/rendering_engine.dart';
import 'shape_paint_style.dart';

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

  /// Fill style, combining color tint with optional gradient.
  ShapePaintStyle fillStyle;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Whether the polygon is filled (`true`) or drawn as an outline (`false`).
  bool filled;

  /// Stroke width used when [filled] is `false`.
  double strokeWidth;

  factory PolygonComponent({
    required List<Offset> vertices,
    ShapePaintStyle fillStyle = const ShapePaintStyle(color: Colors.white),
    ShapePaintStyle strokeStyle = const ShapePaintStyle(
      color: Color(0x73FFFFFF),
    ),
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late PolygonComponent self;
    self = PolygonComponent._internal(
      vertices: vertices,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
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

          Rect shapeRect;
          double minX = self.vertices.first.dx, maxX = minX;
          double minY = self.vertices.first.dy, maxY = minY;
          for (final v in self.vertices) {
            if (v.dx < minX) minX = v.dx;
            if (v.dx > maxX) maxX = v.dx;
            if (v.dy < minY) minY = v.dy;
            if (v.dy > maxY) maxY = v.dy;
          }
          shapeRect = Rect.fromLTRB(minX, minY, maxX, maxY);

          if (self.filled) {
            final fillPaint = Paint();
            self.fillStyle.applyTo(fillPaint, shapeRect);
            canvas.drawPath(path, fillPaint);
          }

          final strokePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = self.strokeWidth;
          self.strokeStyle.applyTo(strokePaint, shapeRect);
          canvas.drawPath(path, strokePaint);
        },
      ),
    );
    return self;
  }

  PolygonComponent._internal({
    required this.vertices,
    required this.fillStyle,
    required this.strokeStyle,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  @override
  Type get componentType => RenderableComponent;

  @override
  String toString() =>
      'Polygon(${vertices.length} vertices, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth)';
}
