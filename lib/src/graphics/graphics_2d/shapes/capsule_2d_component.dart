library;

import 'package:flutter/material.dart';

import '../../../rendering/renderable_component.dart';
import '../../../rendering/renderable.dart';
import 'shape_paint_cache.dart';
import '../../../foundation/shape_paint_style.dart';
import '../../../foundation/solid_shape_2d.dart';
import 'shape_2d_look.dart';
import 'shape_painting.dart';

/// Capsule shape component.
///
/// Describes a capsule (a rectangle with two semicircular end caps) centered
/// on the entity's [TransformComponent] position.
/// When [width] >= [height] the caps are on the left/right sides;
/// when [height] > [width] the caps are on the top/bottom sides.
/// Extends [RenderableComponent] — add it to an entity directly and it draws
/// itself each frame, reading all fields at draw-time so mutations are
/// reflected immediately.
class Capsule2DComponent extends RenderableComponent
    implements SolidShape2DSource, Shape2DLook {
  /// Width of the bounding box in world units.
  double width;

  /// Height of the bounding box in world units.
  double height;

  /// Fill style, combining color tint with optional gradient.
  ShapePaintStyle fillStyle;

  /// Stroke style, combining color tint with optional gradient.
  ShapePaintStyle strokeStyle;

  /// Whether the capsule is filled. Its outline ([strokeStyle]) is drawn
  /// either way, unless fully transparent.
  bool filled;

  /// Width of the outline, in world units; drawn whether or not [filled].
  double strokeWidth;

  /// A [width] × [height] capsule filled white, with a translucent white
  /// outline 1 world unit wide.
  factory Capsule2DComponent({
    required double width,
    required double height,
    ShapePaintStyle fillStyle = const ShapePaintStyle(color: Colors.white),
    ShapePaintStyle strokeStyle = const ShapePaintStyle(
      color: Color(0x73FFFFFF),
    ),
    bool filled = true,
    double strokeWidth = 1.0,
  }) {
    late Capsule2DComponent self;
    self = Capsule2DComponent._internal(
      width: width,
      height: height,
      fillStyle: fillStyle,
      strokeStyle: strokeStyle,
      filled: filled,
      strokeWidth: strokeWidth,
      renderable: CustomRenderable(
        boundsOf: () => Rect.fromCenter(
          center: Offset.zero,
          width: self.width + self.strokeWidth * 2,
          height: self.height + self.strokeWidth * 2,
        ),
        onRender: (canvas, _) => self._draw(canvas, null, 1.0),
        onRenderFaded: (canvas, _, tint, opacity) =>
            self._drawFaded(canvas, tint, opacity),
      ),
    );
    return self;
  }

  Capsule2DComponent._internal({
    required this.width,
    required this.height,
    required this.fillStyle,
    required this.strokeStyle,
    required this.filled,
    required this.strokeWidth,
    required super.renderable,
  });

  (double, double, ShapePaintStyle, ShapePaintStyle, bool, double, Renderable)?
  _look;

  @override
  Object get look {
    final l = _look;
    if (l != null &&
        l.$1 == width &&
        l.$2 == height &&
        identical(l.$3, fillStyle) &&
        identical(l.$4, strokeStyle) &&
        l.$5 == filled &&
        l.$6 == strokeWidth &&
        identical(l.$7, renderable)) {
      return l;
    }
    return _look = (
      width,
      height,
      fillStyle,
      strokeStyle,
      filled,
      strokeWidth,
      renderable,
    );
  }

  // Paints and geometry kept between frames; see ShapePaintCache.
  final ShapePaintCache _paints = ShapePaintCache();
  double _rrectWidth = double.nan;
  double _rrectHeight = double.nan;
  RRect _rrect = RRect.zero;

  void _draw(Canvas canvas, Color? tint, double opacity) {
    if (width != _rrectWidth || height != _rrectHeight) {
      _rrectWidth = width;
      _rrectHeight = height;
      _rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        Radius.circular(capRadius),
      );
    }
    ShapePainting.rectWith(
      canvas,
      _paints,
      _rrect.outerRect,
      _rrect,
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

  /// Radius of the semicircular end caps — half of the shorter side.
  SolidCapsule2D? _solid;

  /// The capsule filling its [width] × [height]: what a collider matching
  /// the shape takes.
  @override
  SolidShape2D get solidShape2D =>
      _solid = SolidCapsule2D.reuse(_solid, width, height);

  double get capRadius => width < height ? width / 2.0 : height / 2.0;

  @override
  String toString() =>
      'Capsule(${width}x$height, fillStyle=$fillStyle, '
      'strokeStyle=$strokeStyle, filled=$filled, '
      'stroke=$strokeWidth)';
}
