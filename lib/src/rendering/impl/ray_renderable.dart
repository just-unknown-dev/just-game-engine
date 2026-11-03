/// Ray Renderable
///
/// A [Renderable] that draws a glowing line segment (beam / bullet trail /
/// laser) in world space and fades it out over its [lifetime].
library;

import 'package:flutter/material.dart';

import 'renderable.dart';

/// Draws a glowing line from [start] to [end] that fades to transparent over
/// [lifetime] seconds.
///
/// Call [update] each frame (before render) to advance the fade timer.
/// Once [isExpired] is `true` the renderable can safely be removed from the
/// rendering pipeline.
///
/// The visual is composed of two layers:
/// - A sharp core line at full [color] and [width].
/// - A wider, blurred glow halo at 35 % of the core's opacity for the
///   neon/laser look.
class RayRenderable extends Renderable {
  /// World-space start point of the beam.
  Offset start;

  /// World-space end point of the beam.
  Offset end;

  /// Core beam colour.
  Color color;

  /// Stroke width of the core line (world units; scaled by [scale]).
  double width;

  /// Width multiplier for the outer glow relative to [width].
  double glowWidthMultiplier;

  /// Blur sigma applied to the glow (0 or less: no glow is drawn at all).
  double glowBlurSigma;

  /// Total fade duration in seconds. `0` (or less) makes a permanent beam:
  /// it never fades and never [isExpired].
  final double lifetime;

  double _timeLeft;

  /// Cached paint for the glow halo — reused every frame.
  final Paint _glowPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  /// Cached paint for the core beam — reused every frame.
  final Paint _corePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  /// A beam from [start] to [end], pale yellow by default, [width] 2.5 with
  /// a glow 4 times as wide blurred at sigma 5, fading out over [lifetime]
  /// (0.25 s by default); drawn on layer 5 at z-order 10 unless told
  /// otherwise.
  RayRenderable({
    required this.start,
    required this.end,
    this.color = const Color(0xFFFFFF44),
    this.width = 2.5,
    this.glowWidthMultiplier = 4.0,
    this.glowBlurSigma = 5.0,
    this.lifetime = 0.25,
    super.layer = 5,
    super.zOrder = 10,
  }) : _timeLeft = lifetime,
       super(position: null);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// `true` once the fade timer has elapsed; never for a permanent beam
  /// ([lifetime] of 0 or less).
  bool get isExpired => lifetime > 0 && _timeLeft <= 0;

  /// Advance the fade timer by [dt] seconds.
  ///
  /// Call this every frame before rendering.
  void update(double dt) {
    if (lifetime <= 0) return; // permanent beam
    if (_timeLeft > 0) {
      _timeLeft -= dt;
      opacity = (_timeLeft / lifetime).clamp(0.0, 1.0);
    }
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    if (!visible || opacity <= 0) return;

    final effectiveAlpha = opacity.clamp(0.0, 1.0);
    final coreAlpha = (effectiveAlpha * 255).round();

    // Glow halo (drawn first so core renders on top)
    if (glowBlurSigma > 0) {
      _glowPaint
        ..color = color.withAlpha((coreAlpha * 0.35).round())
        ..strokeWidth =
            (width * ((scale.x + scale.y) / 2) * glowWidthMultiplier)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlurSigma);
      canvas.drawLine(start, end, _glowPaint);
    }

    // Core beam
    _corePaint
      ..color = color.withAlpha(coreAlpha)
      ..strokeWidth = width * (scale.x + scale.y) / 2;
    canvas.drawLine(start, end, _corePaint);
  }

  // [start] and [end] are world-space points.
  @override
  bool get boundsAreWorldSpace => true;

  @override
  Rect? getBounds() {
    return Rect.fromPoints(
      start,
      end,
    ).inflate((width * glowWidthMultiplier) / 2);
  }
}
