/// Parallax Background System
///
/// Provides multi-layer scrolling backgrounds with configurable scroll rates
/// per layer, supporting both repeating (tiled) and non-repeating images,
/// as well as velocity-based auto-scrolling.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A single layer in a parallax background.
///
/// Each layer holds an image and a scroll factor that controls how fast it
/// moves relative to the camera. A factor of `1.0` scrolls at camera speed
/// (foreground), `0.0` stays fixed (sky/background), and values in between
/// produce the parallax effect.
///
/// [repeatX] and [repeatY] (both on by default) tile the image seamlessly
/// across and down the view; on an axis that does not repeat the image is
/// drawn once — a strip of hills repeats across only.
///
/// Use [velocityX] / [velocityY] for auto-scrolling (e.g. drifting clouds)
/// independent of camera movement.
///
/// The layer does not own [image]: it is never disposed here.
class ParallaxLayer {
  /// The image for this layer.
  ui.Image image;

  /// Horizontal scroll factor relative to camera (0.0 = fixed, 1.0 = camera speed).
  double scrollFactorX;

  /// Vertical scroll factor relative to camera (0.0 = fixed, 1.0 = camera speed).
  double scrollFactorY;

  /// Horizontal auto-scroll velocity in pixels per second.
  double velocityX;

  /// Vertical auto-scroll velocity in pixels per second.
  double velocityY;

  /// Scale applied to the layer image.
  double scale;

  /// Whether the image tiles across the view, left to right.
  bool repeatX;

  /// Whether the image tiles down the view, top to bottom.
  bool repeatY;

  /// Optional static offset applied before scrolling.
  Offset offset;

  /// Opacity of the layer (0.0–1.0).
  double opacity;

  /// Optional tint color blended onto the layer.
  Color? tint;

  /// Cached paint — mutated in place each frame to avoid allocation.
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  // The tint and opacity the paint's colour and filter were set for; they
  // are set again only when those change — a filter handed to a paint is
  // converted for the engine each time.
  Color? _paintTint;
  double _paintOpacity = -1;

  // The repeating image shader, and what it was made for. It only scales
  // the image — the scroll moves the canvas — so it is remade only when the
  // image, the scale or the repeating axes change, not as the view moves.
  ImageShader? _tiles;
  ui.Image? _tilesImage;
  double _tilesScale = double.nan;
  bool _tilesRepeatX = true, _tilesRepeatY = true;
  final Float64List _tilesMatrix = Float64List(16);

  /// Accumulated auto-scroll offset (advanced by [ParallaxBackground.update]).
  double _autoScrollX = 0.0;
  double _autoScrollY = 0.0;

  /// Create a parallax layer.
  ParallaxLayer({
    required this.image,
    this.scrollFactorX = 0.5,
    this.scrollFactorY = 0.5,
    this.velocityX = 0.0,
    this.velocityY = 0.0,
    this.scale = 1.0,
    this.repeatX = true,
    this.repeatY = true,
    this.offset = Offset.zero,
    this.opacity = 1.0,
    this.tint,
  });

  /// Convenience constructor with a single scroll factor for both axes.
  ParallaxLayer.uniform({
    required ui.Image image,
    double scrollFactor = 0.5,
    double velocityX = 0.0,
    double velocityY = 0.0,
    double scale = 1.0,
    bool repeatX = true,
    bool repeatY = true,
    Offset offset = Offset.zero,
    double opacity = 1.0,
    Color? tint,
  }) : this(
         image: image,
         scrollFactorX: scrollFactor,
         scrollFactorY: scrollFactor,
         velocityX: velocityX,
         velocityY: velocityY,
         scale: scale,
         repeatX: repeatX,
         repeatY: repeatY,
         offset: offset,
         opacity: opacity,
         tint: tint,
       );

  /// Reset accumulated auto-scroll offset back to zero.
  void resetAutoScroll() {
    _autoScrollX = 0.0;
    _autoScrollY = 0.0;
  }

  /// Releases the repeating shader this layer made to draw itself; drawn
  /// again, it makes a new one. [image] is not touched.
  void dispose() {
    // A picture still drawing the shader keeps what it needs.
    _tiles?.dispose();
    _tiles = null;
    _tilesImage = null;
    _paint.shader = null;
  }
}

/// A multi-layer parallax background.
///
/// Add [ParallaxLayer] instances from back to front. During rendering, each
/// layer is offset based on the camera position and its scroll factors to
/// create a depth illusion. Layers can also auto-scroll independently via
/// their velocity properties.
///
/// Usage:
/// ```dart
/// final bg = ParallaxBackground(layers: [
///   ParallaxLayer(image: skyImage,   scrollFactorX: 0.0, scrollFactorY: 0.0),
///   ParallaxLayer(image: cloudsImage, scrollFactorX: 0.1, velocityX: 20),
///   ParallaxLayer(image: hillsImage, scrollFactorX: 0.3, repeatY: false),
///   ParallaxLayer(image: treesImage, scrollFactorX: 0.7, scrollFactorY: 0.5),
/// ]);
/// world.createEntityWithComponents([ParallaxComponent(background: bg)]);
/// ```
///
/// `ParallaxRenderSystem`, one of the engine's default systems, scrolls and
/// draws it.
class ParallaxBackground {
  /// Ordered list of layers (index 0 = furthest back).
  final List<ParallaxLayer> layers;

  /// Current camera position used to compute layer offsets.
  ///
  /// Set by `ParallaxRenderSystem` before each draw.
  Offset cameraPosition;

  /// How many screen pixels a world unit covers: the camera's zoom. The
  /// camera-driven scroll is multiplied by it, so a layer with a scroll
  /// factor of 1.0 moves with the world at any zoom.
  ///
  /// Set by `ParallaxRenderSystem` before each draw.
  double cameraZoom;

  /// Overall opacity multiplier applied to every layer.
  double opacity;

  /// Whether this background is visible.
  bool visible;

  /// Create a parallax background.
  ParallaxBackground({
    List<ParallaxLayer>? layers,
    this.cameraPosition = Offset.zero,
    this.cameraZoom = 1.0,
    this.opacity = 1.0,
    this.visible = true,
  }) : layers = layers ?? [];

  /// Add a layer (rendered last = closest to camera).
  void addLayer(ParallaxLayer layer) {
    layers.add(layer);
  }

  /// Insert a layer at a specific index.
  void insertLayer(int index, ParallaxLayer layer) {
    layers.insert(index, layer);
  }

  /// Remove a layer, releasing what it made to draw itself
  /// ([ParallaxLayer.dispose]).
  bool removeLayer(ParallaxLayer layer) {
    final removed = layers.remove(layer);
    if (removed) layer.dispose();
    return removed;
  }

  /// Advance auto-scroll offsets for all layers.
  void update(double deltaTime) {
    for (final layer in layers) {
      layer._autoScrollX += layer.velocityX * deltaTime;
      layer._autoScrollY += layer.velocityY * deltaTime;
    }
  }

  /// Releases what every layer made to draw itself ([ParallaxLayer.dispose]);
  /// the layers and their images stay, and drawing again makes it anew.
  /// `ParallaxComponent` calls it when it leaves its entity.
  void dispose() {
    for (final layer in layers) {
      layer.dispose();
    }
  }

  /// Render all layers to [canvas] in order (back to front).
  ///
  /// The [size] is the viewport size in screen pixels.
  void render(Canvas canvas, Size size) {
    if (!visible || layers.isEmpty) return;

    for (final layer in layers) {
      _renderLayer(canvas, size, layer);
    }
  }

  void _renderLayer(Canvas canvas, Size size, ParallaxLayer layer) {
    final img = layer.image;
    final imgW = img.width.toDouble() * layer.scale;
    final imgH = img.height.toDouble() * layer.scale;
    if (imgW <= 0 || imgH <= 0) return;

    // Configure paint
    final paint = layer._paint;
    final effectiveOpacity = opacity * layer.opacity;
    final tint = layer.tint;
    if (tint != layer._paintTint || effectiveOpacity != layer._paintOpacity) {
      layer
        .._paintTint = tint
        .._paintOpacity = effectiveOpacity;
      // Faded once, by the paint (with the tint's own alpha); the filter
      // carries only the tint's colour. It used to carry the opacity too,
      // fading a tinted layer twice.
      paint
        ..color = Colors.white.withValues(
          alpha: tint == null ? effectiveOpacity : tint.a * effectiveOpacity,
        )
        ..colorFilter = tint == null
            ? null
            : ColorFilter.mode(tint.withValues(alpha: 1.0), BlendMode.modulate);
    }

    // Total scroll = camera-driven (in screen pixels: the camera's move
    // times its zoom) + auto-scroll + static offset.
    final scrollX =
        cameraPosition.dx * layer.scrollFactorX * cameraZoom +
        layer._autoScrollX +
        layer.offset.dx;
    final scrollY =
        cameraPosition.dy * layer.scrollFactorY * cameraZoom +
        layer._autoScrollY +
        layer.offset.dy;

    if (layer.repeatX || layer.repeatY) {
      _renderRepeating(canvas, size, layer, imgW, imgH, scrollX, scrollY);
    } else {
      _renderSingle(canvas, layer, imgW, imgH, scrollX, scrollY);
    }
  }

  /// Fills the view with the layer's image repeated — across, down or both:
  /// one rectangle painted with a repeating image shader, rather than one
  /// image draw per tile, which also leaves no hairline seams where tiles
  /// met at fractional positions. On an axis that does not repeat, the
  /// rectangle covers the image once, where it scrolled to.
  ///
  /// The shader only scales the image; the scroll moves the canvas, so the
  /// shader is kept while the view moves.
  void _renderRepeating(
    Canvas canvas,
    Size size,
    ParallaxLayer layer,
    double imgW,
    double imgH,
    double scrollX,
    double scrollY,
  ) {
    final repeatX = layer.repeatX, repeatY = layer.repeatY;
    // Where the tiles start: on a repeating axis, tile-aligned at or just
    // before the view's edge, so they wrap seamlessly (also for negative
    // scroll); otherwise where the one image is.
    final startX = repeatX ? _tileStart(scrollX, imgW) : -scrollX;
    final startY = repeatY ? _tileStart(scrollY, imgH) : -scrollY;

    final paint = layer._paint;
    var tiles = layer._tiles;
    if (tiles == null ||
        !identical(layer._tilesImage, layer.image) ||
        layer.scale != layer._tilesScale ||
        repeatX != layer._tilesRepeatX ||
        repeatY != layer._tilesRepeatY) {
      final m = layer._tilesMatrix
        ..fillRange(0, 16, 0.0)
        ..[0] = layer.scale
        ..[5] = layer.scale
        ..[10] = 1.0
        ..[15] = 1.0;
      // Clamped on an axis that does not repeat: its edges are sampled as
      // a single image's are.
      final next = ImageShader(
        layer.image,
        repeatX ? TileMode.repeated : TileMode.clamp,
        repeatY ? TileMode.repeated : TileMode.clamp,
        m,
        filterQuality: paint.filterQuality,
      );
      paint.shader = next;
      // A picture still drawing the old shader keeps what it needs.
      tiles?.dispose();
      tiles = layer._tiles = next;
      layer
        .._tilesImage = layer.image
        .._tilesScale = layer.scale
        .._tilesRepeatX = repeatX
        .._tilesRepeatY = repeatY;
    } else if (!identical(paint.shader, tiles)) {
      paint.shader = tiles;
    }

    // What is covered, in the view: all of it on a repeating axis, the
    // image's extent on the other.
    final left = repeatX ? 0.0 : startX;
    final top = repeatY ? 0.0 : startY;
    final width = repeatX ? size.width : imgW;
    final height = repeatY ? size.height : imgH;
    canvas
      ..save()
      ..translate(startX, startY)
      ..drawRect(
        Rect.fromLTWH(left - startX, top - startY, width, height),
        paint,
      )
      ..restore();
  }

  /// Where tiles of [extent] start for a [scroll]: at or just before 0.
  static double _tileStart(double scroll, double extent) {
    final offset = -(scroll % extent);
    return offset > 0 ? offset - extent : offset;
  }

  void _renderSingle(
    Canvas canvas,
    ParallaxLayer layer,
    double imgW,
    double imgH,
    double scrollX,
    double scrollY,
  ) {
    final img = layer.image;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final destRect = Rect.fromLTWH(-scrollX, -scrollY, imgW, imgH);
    final paint = layer._paint;
    if (paint.shader != null) paint.shader = null;
    canvas.drawImageRect(img, srcRect, destRect, paint);
  }
}
