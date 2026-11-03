import 'dart:math' as math;
import 'dart:ui' show Color;

/// sRGB colours as the linear RGB the 3-D renderer lights and blends in.
abstract final class LinearColor {
  /// sRGB [c] as linear RGB.
  static (double, double, double) of(Color c) =>
      (_toLinear(c.r), _toLinear(c.g), _toLinear(c.b));

  static double _toLinear(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}
