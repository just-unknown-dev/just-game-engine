/// A render item 2-D lighting draws as well.
library;

import 'dart:ui';

import '../../../ecs/ecs.dart';
import '../../../rendering/render_items_component.dart';

/// A [RenderItem] that 2-D lighting (`Lighting2DPass`) draws too: its
/// normals, and what of it casts shadows — in the same order and place as
/// the render system draws it. A Level Map's layer (`MapLayerRenderItem`)
/// is one; any other item is left out of the light's buffers.
abstract interface class Lighting2DItem implements RenderItem {
  /// What a flat normal — facing the viewer, not emissive — is drawn as in
  /// the normals buffer: red and green the normal's x and y, blue how
  /// emissive.
  static const int flatNormal = 0xFF808000;

  /// What a shadow caster is drawn as in 2-D lighting's mask: opaque, its
  /// [depth] (how far light reaches into it, 0-64) in red.
  static int casterColor(double depth) =>
      0xFF000000 | ((depth * 4).round().clamp(0, 255) << 16);

  /// Draws the item's normals for [owner] onto [canvas], in world space:
  /// through its normal map when it has one (or glows), and true; else in
  /// [flatNormal] when [flat] — something shaded was drawn under it, which
  /// it must hide — or not at all, false.
  bool paintNormals(
    Canvas canvas,
    RenderContext context,
    Entity owner, {
    required bool flat,
  });

  /// Draws what of the item casts shadows for [owner] onto [canvas], in
  /// world space, in [casterColor] of its shadow depth, and true; false,
  /// drawing nothing, when it casts none.
  bool paintSilhouette(Canvas canvas, RenderContext context, Entity owner);
}
