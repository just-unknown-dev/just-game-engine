/// The renderable the rectangle and circle components draw with.
library;

import 'package:flutter/material.dart';

import '../../../subsystems/rendering/impl/renderable.dart';

/// A [CustomRenderable] that can skip the canvas transform.
///
/// Most shapes in a 2-D scene are neither turned nor scaled, and drawn
/// opaque. For those, [onRenderMoved] draws the shape already moved to its
/// position — two canvas calls for a filled, outlined rectangle instead of
/// five (save, translate, fill, outline, restore), each call being a trip
/// into the engine. It returns false for a shape it cannot draw that way (a
/// gradient is laid out in the shape's own space), which then draws as any
/// [CustomRenderable] does.
///
/// The pixels are those of the transformed draw: a translation moves a
/// shape by the same amount either way, differing at most in the last bit
/// of a 32-bit float — well below what a pixel can show.
class ShapeRenderable extends CustomRenderable {
  /// A renderable that draws with [onRenderMoved] while it is unturned,
  /// unscaled, opaque and untinted, and with `onRender` otherwise.
  ShapeRenderable({
    required super.onRender,
    required this.onRenderMoved,
    super.getBoundsCallback,
    super.onRenderFaded,
    super.layer,
  });

  /// Draws the shape moved by ([dx], [dy]), without the canvas transform;
  /// false, drawing nothing, when it cannot.
  final bool Function(Canvas canvas, double dx, double dy) onRenderMoved;

  @override
  void render(Canvas canvas, Size canvasSize) {
    if (rotation == 0.0 &&
        scale.x == 1.0 &&
        scale.y == 1.0 &&
        opacity >= 1.0 &&
        tint == null &&
        onRenderMoved(canvas, position.x, position.y)) {
      return;
    }
    super.render(canvas, canvasSize);
  }
}
