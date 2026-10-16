library;

import 'package:flutter/material.dart';
import 'package:meta/meta.dart' show internal;

import '../rendering/renderable_component.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import 'shape_paint_cache.dart';
import 'shape_paint_style.dart';
import 'shape_renderable.dart';
import 'shape_painting.dart';

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

  /// Whether the rectangle is filled. Its outline ([strokeStyle]) is drawn
  /// either way, unless fully transparent.
  bool filled;

  /// Width of the outline, in world units; drawn whether or not [filled].
  double strokeWidth;

  /// Corner radius for rounded rectangles. `0` produces sharp corners.
  double cornerRadius;

  /// A [width] × [height] rectangle with sharp corners, filled white, with
  /// a translucent white outline 1 world unit wide.
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
    final shape = ShapeRenderable(
      getBoundsCallback: () => Rect.fromCenter(
        center: Offset.zero,
        width: self.width + self.strokeWidth * 2,
        height: self.height + self.strokeWidth * 2,
      ),
      onRender: (canvas, _) => self._draw(canvas, null, 1.0),
      onRenderFaded: (canvas, _, tint, opacity) =>
          self._drawFaded(canvas, tint, opacity),
      onRenderMoved: (canvas, dx, dy) => self._drawMoved(canvas, dx, dy),
    );
    self = RectangleComponent._internal(
      width: width,
      height: height,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
      renderable: shape,
    ).._shape = shape;
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

  // The renderable this component made, which draws from its fields.
  late final CustomRenderable _shape;

  // Paints and geometry kept between frames; see ShapePaintCache.
  final ShapePaintCache _paints = ShapePaintCache();
  double _rectWidth = double.nan;
  double _rectHeight = double.nan;
  double _rectRadius = double.nan;
  Rect _rect = Rect.zero;
  RRect? _rrect;

  /// Whether [renderable] is still the one this component made, so what it
  /// draws is what the fields say — the question a shape batch asks.
  @internal
  bool get drawsOwnShape => identical(renderable, _shape);

  void _updateGeometry() {
    if (width == _rectWidth &&
        height == _rectHeight &&
        cornerRadius == _rectRadius) {
      return;
    }
    _rectWidth = width;
    _rectHeight = height;
    _rectRadius = cornerRadius;
    _rect = Rect.fromCenter(center: Offset.zero, width: width, height: height);
    _rrect = cornerRadius == 0
        ? null
        : RRect.fromRectAndRadius(_rect, Radius.circular(cornerRadius));
  }

  void _draw(Canvas canvas, Color? tint, double opacity) {
    _updateGeometry();
    ShapePainting.rectWith(
      canvas,
      _paints,
      _rect,
      _rrect,
      fill: fillStyle,
      stroke: strokeStyle,
      strokeWidth: strokeWidth,
      filled: filled,
      tint: tint,
      opacity: opacity,
    );
  }

  bool _drawMoved(Canvas canvas, double dx, double dy) {
    // Square corners and plain colours only: a rounded rectangle would need
    // its own moved copy, and a gradient is laid out around the origin.
    if (cornerRadius != 0 ||
        fillStyle.gradient != null ||
        strokeStyle.gradient != null) {
      return false;
    }
    _updateGeometry();
    final r = _rect;
    ShapePainting.rectWith(
      canvas,
      _paints,
      Rect.fromLTRB(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy),
      null,
      fill: fillStyle,
      stroke: strokeStyle,
      strokeWidth: strokeWidth,
      filled: filled,
    );
    return true;
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

  /// Convenience getter for the size as a [Size] object.
  Size get size => Size(width, height);

  @override
  String toString() =>
      'Rectangle(${width}x$height, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth, radius=$cornerRadius)';
}
