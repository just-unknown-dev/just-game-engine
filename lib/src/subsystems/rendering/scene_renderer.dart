/// A pass that draws the world some other way than the canvas renderables.
library;

import 'dart:ui';

import 'render_view.dart';

/// Draws the world from a [RenderView] — the slot a 3-D rendering backend
/// fills.
///
/// Scene renderers run inside the frame, in screen space, after the
/// background and the camera's pre-effects and before the 2-D renderables
/// and the ECS world are drawn over them (see `RenderingEngine.render` for
/// the whole order). A GPU backend renders its scene into a texture and
/// draws the texture's image here — `canvas.drawImageRect` over the
/// viewport — so post-processing and camera effects still apply to it, and
/// 2-D sprites, UI and gizmos still draw on top.
///
/// Register with `RenderingEngine.addSceneRenderer`. With none registered,
/// a frame costs nothing extra.
abstract class SceneRenderer {
  const SceneRenderer();

  /// Draw order among scene renderers; lower first.
  int get order => 0;

  /// Skipped while false.
  bool get enabled => true;

  /// Draw into [canvas], whose coordinates are viewport pixels, what
  /// [view] sees.
  void render(Canvas canvas, RenderView view);
}
