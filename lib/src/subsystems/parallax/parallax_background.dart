/// Parallax Background System
///
/// Provides multi-layer scrolling backgrounds with configurable scroll rates
/// per layer, supporting both repeating (tiled) and non-repeating images,
/// as well as velocity-based auto-scrolling.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A single layer in a parallax background.
///
/// Each layer holds an image and a scroll factor that controls how fast it
/// moves relative to the camera. A factor of `1.0` scrolls at camera speed
/// (foreground), `0.0` stays fixed (sky/background), and values in between
/// produce the parallax effect.
///
/// Set [repeat] to `true` (the default) to tile the image seamlessly.
///
/// Use [velocityX] / [velocityY] for auto-scrolling (e.g. drifting clouds)
/// independent of camera movement.
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

  /// Whether the layer image tiles to fill the viewport.
  bool repeat;

  /// Optional static offset applied before scrolling.
  Offset offset;

  /// Opacity of the layer (0.0–1.0).
  double opacity;

  /// Optional tint color blended onto the layer.
  Color? tint;

  /// Cached paint — mutated in place each frame to avoid allocation.
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

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
    this.repeat = true,
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
    bool repeat = true,
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
         repeat: repeat,
         offset: offset,
         opacity: opacity,
         tint: tint,
       );

  /// Reset accumulated auto-scroll offset back to zero.
  void resetAutoScroll() {
    _autoScrollX = 0.0;
    _autoScrollY = 0.0;
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
///   ParallaxLayer(image: hillsImage, scrollFactorX: 0.3, scrollFactorY: 0.2),
///   ParallaxLayer(image: treesImage, scrollFactorX: 0.7, scrollFactorY: 0.5),
/// ]);
/// engine.parallax.addBackground(bg);
/// ```
class ParallaxBackground {
  /// Ordered list of layers (index 0 = furthest back).
  final List<ParallaxLayer> layers;

  /// Current camera position used to compute layer offsets.
  ///
  /// Set automatically by [ParallaxSystem] before each render call.
  Offset cameraPosition;

  /// Overall opacity multiplier applied to every layer.
  double opacity;

  /// Whether this background is visible.
  bool visible;

  /// Create a parallax background.
  ParallaxBackground({
    List<ParallaxLayer>? layers,
    this.cameraPosition = Offset.zero,
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

  /// Remove a layer.
  bool removeLayer(ParallaxLayer layer) => layers.remove(layer);

  /// Advance auto-scroll offsets for all layers.
  void update(double deltaTime) {
    for (final layer in layers) {
      layer._autoScrollX += layer.velocityX * deltaTime;
      layer._autoScrollY += layer.velocityY * deltaTime;
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
    paint.color = Colors.white.withValues(alpha: effectiveOpacity);
    if (layer.tint != null) {
      paint.colorFilter = ColorFilter.mode(
        layer.tint!.withValues(alpha: effectiveOpacity),
        BlendMode.modulate,
      );
    } else {
      paint.colorFilter = null;
    }

    // Total scroll = camera-driven + auto-scroll + static offset
    final scrollX =
        cameraPosition.dx * layer.scrollFactorX +
        layer._autoScrollX +
        layer.offset.dx;
    final scrollY =
        cameraPosition.dy * layer.scrollFactorY +
        layer._autoScrollY +
        layer.offset.dy;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );

    if (layer.repeat) {
      _renderRepeating(
        canvas,
        size,
        layer,
        imgW,
        imgH,
        scrollX,
        scrollY,
        srcRect,
        paint,
      );
    } else {
      _renderSingle(
        canvas,
        layer,
        imgW,
        imgH,
        scrollX,
        scrollY,
        srcRect,
        paint,
      );
    }
  }

  void _renderRepeating(
    Canvas canvas,
    Size size,
    ParallaxLayer layer,
    double imgW,
    double imgH,
    double scrollX,
    double scrollY,
    Rect srcRect,
    Paint paint,
  ) {
    // Compute tile-aligned start so tiles wrap seamlessly.
    final offsetX = -(scrollX % imgW);
    final offsetY = -(scrollY % imgH);

    // Ensure coverage even for negative modulo.
    final startX = offsetX > 0 ? offsetX - imgW : offsetX;
    final startY = offsetY > 0 ? offsetY - imgH : offsetY;

    for (double y = startY; y < size.height; y += imgH) {
      for (double x = startX; x < size.width; x += imgW) {
        final destRect = Rect.fromLTWH(x, y, imgW, imgH);
        canvas.drawImageRect(layer.image, srcRect, destRect, paint);
      }
    }
  }

  void _renderSingle(
    Canvas canvas,
    ParallaxLayer layer,
    double imgW,
    double imgH,
    double scrollX,
    double scrollY,
    Rect srcRect,
    Paint paint,
  ) {
    final destRect = Rect.fromLTWH(-scrollX, -scrollY, imgW, imgH);
    canvas.drawImageRect(layer.image, srcRect, destRect, paint);
  }
}

/// Parallax subsystem that manages multiple [ParallaxBackground] instances.
///
/// The [ParallaxSystem] is owned by the [Engine] and automatically wired
/// into the rendering pipeline via [RenderingEngine.onRenderBackground].
///
/// ```dart
/// engine.parallax.addBackground(myParallax);
/// ```
class ParallaxSystem {
  /// All registered parallax backgrounds (rendered in order).
  final List<ParallaxBackground> _backgrounds = [];

  bool _initialized = false;

  /// Whether the system has been initialized.
  bool get isInitialized => _initialized;

  /// Read-only view of current backgrounds.
  List<ParallaxBackground> get backgrounds => List.unmodifiable(_backgrounds);

  /// Number of registered backgrounds.
  int get backgroundCount => _backgrounds.length;

  /// Initialize the parallax system.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
  }

  /// Register a background to be rendered each frame.
  void addBackground(ParallaxBackground background) {
    _backgrounds.add(background);
  }

  /// Remove a previously registered background.
  bool removeBackground(ParallaxBackground background) {
    return _backgrounds.remove(background);
  }

  /// Remove all backgrounds.
  void clear() {
    _backgrounds.clear();
  }

  /// Advance auto-scroll offsets and feed the current [cameraPosition]
  /// into every background.
  ///
  /// Called once per frame by [Engine._update].
  void update(double deltaTime, Offset cameraPosition) {
    for (final bg in _backgrounds) {
      bg.cameraPosition = cameraPosition;
      bg.update(deltaTime);
    }
  }

  /// Render all backgrounds to [canvas].
  ///
  /// This is intended to be called via [RenderingEngine.onRenderBackground]
  /// in screen space (before the camera transform).
  void render(Canvas canvas, Size size) {
    for (final bg in _backgrounds) {
      bg.render(canvas, size);
    }
  }

  /// Dispose the system and clear all backgrounds.
  void dispose() {
    _backgrounds.clear();
    _initialized = false;
  }
}
