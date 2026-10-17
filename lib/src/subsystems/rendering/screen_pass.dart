/// Something drawn over the whole frame from an image of it.
library;

import 'dart:ui' as ui;

/// Drawn over the whole frame from an image of it — a screen material's
/// vignette, colour grade or pixelation, say — by `RenderingEngine`: when
/// [active], the frame is drawn into an image (everything up to the overlay
/// hooks of order `RenderingEngine.screenPassOrder`, an editor's own
/// drawing left out), which [paint] then draws over the view.
///
/// Unlike a post-process pass it needs no layer filter, so it works on
/// every renderer, the web included.
abstract interface class ScreenPass {
  /// Whether it draws this frame; asked once a frame, before anything is.
  bool get active;

  /// Draws [frame] — the frame so far, drawn into an image [pixelRatio]
  /// times the view's [size] — over the view onto [canvas], in logical
  /// pixels.
  void paint(ui.Canvas canvas, ui.Image frame, ui.Size size, double pixelRatio);
}
