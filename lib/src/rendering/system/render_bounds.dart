/// Where a renderable draws, in the world: for culling it and for the layer
/// of its shader.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart' show internal;

import '../renderable.dart';

/// The world-space extent of what a [Renderable] draws, however it is
/// turned and scaled.
@internal
abstract final class RenderBounds {
  /// The world-space rectangle a shaded [renderable]'s layer covers.
  ///
  /// World-space bounds (a sprite's) are used as they are when the
  /// renderable is not turned; they are not turned with it, so for a turned
  /// one they are turned about its position, as it draws, and the box
  /// around them is used — as they were, the layer clipped a turned
  /// sprite's corners. Local bounds (a shape's, centred on its origin) are
  /// placed as the renderable is: used as they were, they put the layer —
  /// which clips — around the world origin, and the shape vanished.
  static Rect? shaderBounds(Renderable renderable) {
    final bounds = renderable.bounds;
    if (bounds == null) return null;
    if (renderable.boundsAreWorldSpace) {
      final angle = renderable.rotation;
      if (angle == 0.0) return bounds;
      final px = renderable.position.x, py = renderable.position.y;
      final c = math.cos(angle).abs(), s = math.sin(angle).abs();
      final dx = math.max((bounds.left - px).abs(), (bounds.right - px).abs());
      final dy = math.max((bounds.top - py).abs(), (bounds.bottom - py).abs());
      return Rect.fromCenter(
        center: Offset(px, py),
        width: 2 * (dx * c + dy * s),
        height: 2 * (dx * s + dy * c),
      );
    }
    return placed(renderable, bounds);
  }

  /// Local [bounds] turned, scaled and moved as [renderable] is drawn: the
  /// world-space rectangle holding them.
  static Rect placed(Renderable renderable, Rect bounds) {
    final px = renderable.position.x, py = renderable.position.y;
    final sx = renderable.scale.x, sy = renderable.scale.y;
    final angle = renderable.rotation;
    final cos = angle == 0.0 ? 1.0 : math.cos(angle);
    final sin = angle == 0.0 ? 0.0 : math.sin(angle);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var corner = 0; corner < 4; corner++) {
      final x = (corner & 1) == 0 ? bounds.left * sx : bounds.right * sx;
      final y = (corner & 2) == 0 ? bounds.top * sy : bounds.bottom * sy;
      final wx = px + cos * x - sin * y, wy = py + sin * x + cos * y;
      minX = math.min(minX, wx);
      maxX = math.max(maxX, wx);
      minY = math.min(minY, wy);
      maxY = math.max(maxY, wy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Whether [renderable] may draw inside [clip]: false only when its
  /// bounds, grown to cover any turn and scale, miss it entirely.
  static bool mayShow(Renderable renderable, Rect clip) {
    final bounds = renderable.bounds;
    if (bounds == null) return true;
    final (cx, cy, reach) = _reach(
      renderable,
      bounds,
      local: !renderable.boundsAreWorldSpace,
    );
    return cx + reach >= clip.left &&
        cx - reach <= clip.right &&
        cy + reach >= clip.top &&
        cy - reach <= clip.bottom;
  }

  /// A centre and a radius around it that hold everything [renderable]
  /// draws within [bounds], however it is turned or scaled.
  ///
  /// [local] bounds are around the renderable's origin: they turn and scale
  /// with it about its position. World-space bounds are taken as already
  /// placed, but not necessarily turned or scaled — a sprite's are not
  /// turned — so they are grown about the position by the largest scale.
  static (double, double, double) _reach(
    Renderable renderable,
    Rect bounds, {
    required bool local,
  }) {
    final px = renderable.position.x, py = renderable.position.y;
    final scale = math.max(renderable.scale.x.abs(), renderable.scale.y.abs());
    final ox = local ? 0.0 : px, oy = local ? 0.0 : py;
    final dx = math.max((bounds.left - ox).abs(), (bounds.right - ox).abs());
    final dy = math.max((bounds.top - oy).abs(), (bounds.bottom - oy).abs());
    final corner = math.sqrt(dx * dx + dy * dy);
    return (px, py, local ? corner * scale : corner * math.max(1.0, scale));
  }
}
