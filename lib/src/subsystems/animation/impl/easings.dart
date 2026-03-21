part of '../animation_system.dart';

/// Easing functions for smooth animations
typedef Easing = double Function(double t);

/// Common easing functions
class Easings {
  // Linear
  static double linear(double t) => t;

  // Quadratic
  static double easeInQuad(double t) => t * t;
  static double easeOutQuad(double t) => t * (2 - t);
  static double easeInOutQuad(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  // Cubic
  static double easeInCubic(double t) => t * t * t;
  static double easeOutCubic(double t) => (--t) * t * t + 1;
  static double easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
  }

  // Quartic
  static double easeInQuart(double t) => t * t * t * t;
  static double easeOutQuart(double t) => 1 - (--t) * t * t * t;
  static double easeInOutQuart(double t) {
    return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
  }

  // Sine
  static double easeInSine(double t) => 1 - math.cos(t * math.pi / 2);
  static double easeOutSine(double t) => math.sin(t * math.pi / 2);
  static double easeInOutSine(double t) => -(math.cos(math.pi * t) - 1) / 2;

  // Exponential
  static double easeInExpo(double t) {
    return t == 0 ? 0 : math.pow(2, 10 * t - 10).toDouble();
  }

  static double easeOutExpo(double t) {
    return t == 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble();
  }

  static double easeInOutExpo(double t) {
    if (t == 0 || t == 1) return t;
    return t < 0.5
        ? math.pow(2, 20 * t - 10).toDouble() / 2
        : (2 - math.pow(2, -20 * t + 10).toDouble()) / 2;
  }

  // Elastic
  static double easeInElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    return t == 0
        ? 0
        : t == 1
        ? 1
        : -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4);
  }

  static double easeOutElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    return t == 0
        ? 0
        : t == 1
        ? 1
        : math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
  }

  // Bounce
  static double easeOutBounce(double t) {
    const n1 = 7.5625;
    const d1 = 2.75;

    if (t < 1 / d1) {
      return n1 * t * t;
    } else if (t < 2 / d1) {
      return n1 * (t -= 1.5 / d1) * t + 0.75;
    } else if (t < 2.5 / d1) {
      return n1 * (t -= 2.25 / d1) * t + 0.9375;
    } else {
      return n1 * (t -= 2.625 / d1) * t + 0.984375;
    }
  }

  static double easeInBounce(double t) {
    return 1 - easeOutBounce(1 - t);
  }
}

// Export common easings
final Easing linear = Easings.linear;
final Easing easeInQuad = Easings.easeInQuad;
final Easing easeOutQuad = Easings.easeOutQuad;
final Easing easeInOutQuad = Easings.easeInOutQuad;
final Easing easeInCubic = Easings.easeInCubic;
final Easing easeOutCubic = Easings.easeOutCubic;
final Easing easeInOutCubic = Easings.easeInOutCubic;
