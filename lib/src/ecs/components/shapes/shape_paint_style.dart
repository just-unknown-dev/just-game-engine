library;

import 'package:flutter/material.dart';

/// Engine-specific gradient descriptor for shape paints.
enum ShapeGradientKind { linear, radial, sweep }

/// Serializable-style gradient config used by shape components.
class ShapeGradient {
  /// Gradient type.
  final ShapeGradientKind kind;

  /// Gradient colors.
  final List<Color> colors;

  /// Optional stop values, same semantics as Flutter gradients.
  final List<double>? stops;

  /// Linear gradient begin alignment.
  final AlignmentGeometry begin;

  /// Linear gradient end alignment.
  final AlignmentGeometry end;

  /// Radial/sweep center alignment.
  final AlignmentGeometry center;

  /// Radial gradient radius in unit space.
  final double radius;

  /// Sweep gradient start angle in radians.
  final double startAngle;

  /// Sweep gradient end angle in radians.
  final double endAngle;

  /// Tile mode for all gradient kinds.
  final TileMode tileMode;

  const ShapeGradient.linear({
    required this.colors,
    this.stops,
    this.begin = Alignment.centerLeft,
    this.end = Alignment.centerRight,
    this.tileMode = TileMode.clamp,
  }) : kind = ShapeGradientKind.linear,
       center = Alignment.center,
       radius = 0.5,
       startAngle = 0.0,
       endAngle = 0.0;

  const ShapeGradient.radial({
    required this.colors,
    this.stops,
    this.center = Alignment.center,
    this.radius = 0.5,
    this.tileMode = TileMode.clamp,
  }) : kind = ShapeGradientKind.radial,
       begin = Alignment.centerLeft,
       end = Alignment.centerRight,
       startAngle = 0.0,
       endAngle = 0.0;

  const ShapeGradient.sweep({
    required this.colors,
    this.stops,
    this.center = Alignment.center,
    this.startAngle = 0.0,
    this.endAngle = 6.283185307179586,
    this.tileMode = TileMode.clamp,
  }) : kind = ShapeGradientKind.sweep,
       begin = Alignment.centerLeft,
       end = Alignment.centerRight,
       radius = 0.5;

  Shader createShader(Rect rect) {
    switch (kind) {
      case ShapeGradientKind.linear:
        return LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
          stops: stops,
          tileMode: tileMode,
        ).createShader(rect);
      case ShapeGradientKind.radial:
        return RadialGradient(
          center: center,
          radius: radius,
          colors: colors,
          stops: stops,
          tileMode: tileMode,
        ).createShader(rect);
      case ShapeGradientKind.sweep:
        return SweepGradient(
          center: center,
          startAngle: startAngle,
          endAngle: endAngle,
          colors: colors,
          stops: stops,
          tileMode: tileMode,
        ).createShader(rect);
    }
  }
}

/// Unified shape paint style that combines color tint and optional gradient.
class ShapePaintStyle {
  /// Color tint applied always; when [gradient] is set this tints the gradient.
  final Color color;

  /// Optional engine-specific gradient.
  final ShapeGradient? gradient;

  /// Blend mode used when combining [color] with [gradient].
  final BlendMode blendMode;

  const ShapePaintStyle({
    this.color = Colors.white,
    this.gradient,
    this.blendMode = BlendMode.modulate,
  });

  /// Applies this style to an existing [Paint].
  void applyTo(Paint paint, Rect shaderRect) {
    paint
      ..shader = null
      ..colorFilter = null
      ..color = color;

    final g = gradient;
    if (g == null) return;

    paint
      ..shader = g.createShader(shaderRect)
      ..colorFilter = ColorFilter.mode(color, blendMode);
  }
}
