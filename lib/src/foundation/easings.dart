/// The engine's easing functions: one table, read by effects
/// (`EasingType`) and by timelines (`KeyEasings`).
library;

import 'dart:math' as math;

/// An easing curve: normalised progress `t ∈ [0, 1]` to eased progress.
///
/// Every curve here is 0 at 0 and 1 at 1; between them some overshoot
/// (elastic) or dip below 0 (elastic in).
typedef EasingFunction = double Function(double t);

/// The engine's easing functions — the single table behind the effects'
/// `EasingType` and the timelines' `KeyEasings`.
///
/// The names those two save (an effect's `easing`, a timeline key's `e`)
/// are the names of these functions.
abstract final class Easings {
  // Linear
  /// No easing: [t] unchanged, so progress moves at a constant speed.
  static double linear(double t) => t;

  // Quadratic
  /// Starts at rest and accelerates: `t²`.
  static double easeInQuad(double t) => t * t;

  /// Starts fast and decelerates to rest: [easeInQuad] mirrored.
  static double easeOutQuad(double t) => t * (2 - t);

  /// Accelerates through the first half and decelerates through the
  /// second (quadratic); halfway at `t = 0.5`.
  static double easeInOutQuad(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  // Cubic
  /// Starts at rest and accelerates, more sharply than [easeInQuad]: `t³`.
  static double easeInCubic(double t) => t * t * t;

  /// Starts fast and decelerates to rest, more sharply than
  /// [easeOutQuad]: [easeInCubic] mirrored.
  static double easeOutCubic(double t) => (t - 1) * (t - 1) * (t - 1) + 1;

  /// Accelerates through the first half and decelerates through the
  /// second (cubic); steeper in the middle than [easeInOutQuad].
  static double easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
  }

  // Quartic
  /// Starts at rest and accelerates, sharper still than [easeInCubic]:
  /// `t⁴`.
  static double easeInQuart(double t) => t * t * t * t;

  /// Starts fast and decelerates to rest, sharper still than
  /// [easeOutCubic]: [easeInQuart] mirrored.
  static double easeOutQuart(double t) => 1 - (--t) * t * t * t;

  /// Accelerates through the first half and decelerates through the
  /// second (quartic): slow at both ends, fast through the middle.
  static double easeInOutQuart(double t) {
    return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
  }

  // Sine
  /// Starts at rest and accelerates gently, along a quarter cosine; the
  /// softest of the ease-ins.
  static double easeInSine(double t) => 1 - math.cos(t * math.pi / 2);

  /// Starts moving and decelerates gently to rest, along a quarter sine;
  /// the softest of the ease-outs.
  static double easeOutSine(double t) => math.sin(t * math.pi / 2);

  /// Accelerates gently through the first half and decelerates through the
  /// second, along half a cosine wave.
  static double easeInOutSine(double t) => -(math.cos(math.pi * t) - 1) / 2;

  // Exponential
  /// Almost flat at first, then accelerates steeply at the end:
  /// `2^(10t − 10)`, and exactly 0 at `t = 0`.
  static double easeInExpo(double t) {
    return t == 0 ? 0 : math.pow(2, 10 * t - 10).toDouble();
  }

  /// Rises steeply at first, then flattens out just short of the end:
  /// `1 − 2^(−10t)`, and exactly 1 at `t = 1`.
  static double easeOutExpo(double t) {
    return t == 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble();
  }

  /// Almost flat at both ends with a steep rush through the middle:
  /// [easeInExpo] for the first half, [easeOutExpo] for the second.
  static double easeInOutExpo(double t) {
    if (t == 0 || t == 1) return t;
    return t < 0.5
        ? math.pow(2, 20 * t - 10).toDouble() / 2
        : (2 - math.pow(2, -20 * t + 10).toDouble()) / 2;
  }

  // Elastic
  /// Winds up like a plucked spring: oscillates around 0 with growing
  /// swings — dipping below 0 — then snaps to 1 at the end.
  static double easeInElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    if (t == 0 || t == 1) return t;
    return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4);
  }

  /// Springs past 1 almost at once, then oscillates around 1 with shrinking
  /// swings (overshooting above it) until it settles there.
  static double easeOutElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    if (t == 0 || t == 1) return t;
    return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
  }

  // Bounce
  /// A dropped ball: accelerates to 1, then bounces back off it three
  /// times, each bounce smaller, and comes to rest at 1. Never leaves
  /// 0..1.
  static double easeOutBounce(double t) {
    const n1 = 7.5625;
    const d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) {
      t -= 1.5 / d1;
      return n1 * t * t + 0.75;
    }
    if (t < 2.5 / d1) {
      t -= 2.25 / d1;
      return n1 * t * t + 0.9375;
    }
    t -= 2.625 / d1;
    return n1 * t * t + 0.984375;
  }

  /// [easeOutBounce] reversed: three hops off 0, each bigger, then a last
  /// rise that slows into 1. Never leaves 0..1.
  static double easeInBounce(double t) => 1 - easeOutBounce(1 - t);
}
