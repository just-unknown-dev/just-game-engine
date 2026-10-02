library;

import 'package:flutter/material.dart';

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import 'shape_paint_cache.dart';
import 'shape_paint_style.dart';
import 'shape_painting.dart';

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

  /// Whether the polygon is filled. Its outline ([strokeStyle]) is drawn
  /// either way, unless fully transparent.
  bool filled;

  /// Width of the outline, in world units; drawn whether or not [filled].
  double strokeWidth;

  /// A polygon through [vertices] — that list, not a copy — filled white,
  /// with a translucent white outline 1 world unit wide.
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
        onRender: (canvas, _) => self._draw(canvas, null, 1.0),
        onRenderFaded: (canvas, _, tint, opacity) =>
            self._drawFaded(canvas, tint, opacity),
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

  // Paints, the path and its bounds, kept between frames. The path is
  // rebuilt when a vertex changes — [vertices] is compared with the copy it
  // was built from, so editing the list in place is seen too.
  final ShapePaintCache _paints = ShapePaintCache();
  final List<Offset> _pathPoints = [];
  Path _path = Path();
  Rect _pathBounds = Rect.zero;

  void _updatePath() {
    final points = vertices;
    var same = points.length == _pathPoints.length;
    for (var i = 0; same && i < points.length; i++) {
      same = points[i] == _pathPoints[i];
    }
    if (same) return;
    _pathPoints
      ..clear()
      ..addAll(points);
    _path = ShapePainting.pathThrough(points);
    _pathBounds = ShapePainting.boundsOf(points);
  }

  void _draw(Canvas canvas, Color? tint, double opacity) {
    if (vertices.isEmpty) return;
    _updatePath();
    ShapePainting.pathWith(
      canvas,
      _paints,
      _path,
      _pathBounds,
      fill: fillStyle,
      stroke: strokeStyle,
      strokeWidth: strokeWidth,
      filled: filled,
      tint: tint,
      opacity: opacity,
    );
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
      'Polygon(${vertices.length} vertices, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth)';
}
