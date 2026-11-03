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
/// every renderer, the web included. Where layers can be filtered, a pass
/// that can be one ([filter]) is: see [ScreenPassPlan].
abstract interface class ScreenPass {
  /// Whether it draws this frame; asked once a frame, before anything is.
  bool get active;

  /// Draws [frame] — the frame so far, drawn into an image [pixelRatio]
  /// times the view's [size] — over the view onto [canvas], in logical
  /// pixels.
  void paint(ui.Canvas canvas, ui.Image frame, ui.Size size, double pixelRatio);

  /// This pass as a filter over a layer the frame is drawn into — instead of
  /// [paint] over an image of it — for a view of [size] drawn at
  /// [pixelRatio]; null when it cannot be one. Asked after [active], only
  /// where the renderer filters layers with shaders.
  ui.ImageFilter? filter(ui.Size size, double pixelRatio);
}

/// How a frame is drawn through its [ScreenPass]es.
///
/// Where the renderer filters layers with shaders (Impeller), the last
/// passes that can be filters ([ScreenPass.filter]) are: [layers] around
/// the drawing, nothing made of what they filter. Only the passes before
/// them ([imagePasses]) draw from an image of the frame, each into an image
/// for the next and the last over the view. (Every pass through images, a
/// pass drew from an image of the one before, itself drawn from fresh
/// images — on Impeller, Windows, that held GPU memory until the card was
/// full: 7 GB and 15 fps for a lit cave under a screen material.)
final class ScreenPassPlan {
  ScreenPassPlan._(this.imagePasses, this.layers);

  /// The plan for [passes] (each active this frame), in order, over a view
  /// of [size] drawn at [pixelRatio]. [filterLayers] says whether layers
  /// can be filtered; by default, whether this renderer can
  /// (`ui.ImageFilter.isShaderFilterSupported`).
  factory ScreenPassPlan.of(
    List<ScreenPass> passes,
    ui.Size size,
    double pixelRatio, {
    bool? filterLayers,
  }) {
    final layers = <ui.ImageFilter>[];
    var images = passes.length;
    if (filterLayers ?? ui.ImageFilter.isShaderFilterSupported) {
      while (images > 0) {
        final filter = passes[images - 1].filter(size, pixelRatio);
        if (filter == null) break;
        layers.add(filter);
        images--;
      }
    }
    return ScreenPassPlan._(
      List.unmodifiable(passes.take(images)),
      List.unmodifiable(layers.reversed),
    );
  }

  /// The passes drawn from an image of the frame, in order.
  final List<ScreenPass> imagePasses;

  /// The filters of the passes drawn as layers, in order: the first is
  /// innermost.
  final List<ui.ImageFilter> layers;

  /// Whether the frame is drawn into an image: whether any pass draws from
  /// one.
  bool get needsImage => imagePasses.isNotEmpty;

  /// Opens [layers] on [canvas] over the view of [size]: what is drawn
  /// until [end] is filtered by them.
  void begin(ui.Canvas canvas, ui.Size size) {
    final bounds = ui.Offset.zero & size;
    for (final filter in layers.reversed) {
      canvas.saveLayer(bounds, ui.Paint()..imageFilter = filter);
    }
  }

  /// Draws [frame] — the frame drawn into an image [pixelRatio] times the
  /// view's [size] — through [imagePasses] onto [canvas]: each into an
  /// image for the next (handed to [keep], to be let go once the frame is
  /// drawn), the last over the view.
  void paintImages(
    ui.Canvas canvas,
    ui.Image frame,
    ui.Size size,
    double pixelRatio, {
    required void Function(ui.Image image) keep,
  }) {
    final width = frame.width, height = frame.height;
    var image = frame;
    for (var i = 0; i < imagePasses.length; i++) {
      if (i == imagePasses.length - 1) {
        imagePasses[i].paint(canvas, image, size, pixelRatio);
        break;
      }
      final next = ui.PictureRecorder();
      imagePasses[i].paint(
        ui.Canvas(next)..scale(pixelRatio),
        image,
        size,
        pixelRatio,
      );
      final drawn = next.endRecording();
      image = drawn.toImageSync(width, height);
      drawn.dispose();
      keep(image);
    }
  }

  /// Closes the layers [begin] opened: they are filtered.
  void end(ui.Canvas canvas) {
    for (var i = 0; i < layers.length; i++) {
      canvas.restore();
    }
  }
}
