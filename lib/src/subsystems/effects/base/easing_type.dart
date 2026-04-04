part of '../effect_system.dart';

/// Easing curve selector for [DeterministicEffect].
///
/// All curves map `t ∈ [0, 1] → [0, 1]`. Use [EffectEasings.resolve] to
/// obtain the concrete `double Function(double)` for a given type.
enum EasingType {
  linear,
  easeInQuad,
  easeOutQuad,
  easeInOutQuad,
  easeInCubic,
  easeOutCubic,
  easeInOutCubic,
  easeInSine,
  easeOutSine,
  easeInOutSine,
  easeInExpo,
  easeOutExpo,
  easeInElastic,
  easeOutElastic,
  easeInBounce,
  easeOutBounce,
}

/// Self-contained easing math for the effects system.
///
/// These implementations mirror the `Easings` class in the animation
/// subsystem but are duplicated here so effects have no dependency on
/// the animation subsystem.
abstract final class EffectEasings {
  /// Evaluate [type] at normalised progress [t] ∈ [0, 1].
  static double resolve(EasingType type, double t) {
    return switch (type) {
      EasingType.linear => t,
      EasingType.easeInQuad => t * t,
      EasingType.easeOutQuad => t * (2 - t),
      EasingType.easeInOutQuad => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t,
      EasingType.easeInCubic => t * t * t,
      EasingType.easeOutCubic => (t - 1) * (t - 1) * (t - 1) + 1,
      EasingType.easeInOutCubic =>
        t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1,
      EasingType.easeInSine => 1 - math.cos(t * math.pi / 2),
      EasingType.easeOutSine => math.sin(t * math.pi / 2),
      EasingType.easeInOutSine => -(math.cos(math.pi * t) - 1) / 2,
      EasingType.easeInExpo => t == 0 ? 0 : math.pow(2, 10 * t - 10).toDouble(),
      EasingType.easeOutExpo =>
        t == 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble(),
      EasingType.easeInElastic => _easeInElastic(t),
      EasingType.easeOutElastic => _easeOutElastic(t),
      EasingType.easeInBounce => 1 - _easeOutBounce(1 - t),
      EasingType.easeOutBounce => _easeOutBounce(t),
    };
  }

  static double _easeInElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    if (t == 0 || t == 1) return t;
    return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4);
  }

  static double _easeOutElastic(double t) {
    const c4 = (2 * math.pi) / 3;
    if (t == 0 || t == 1) return t;
    return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
  }

  static double _easeOutBounce(double t) {
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
}
