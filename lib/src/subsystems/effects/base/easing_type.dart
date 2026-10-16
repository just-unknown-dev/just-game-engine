part of '../effect_system.dart';

/// Easing curve selector for [DeterministicEffect].
///
/// All curves take `t ∈ [0, 1]` and give 0 at 0 and 1 at 1; in between
/// they stay within `[0, 1]` except the elastic ones, which swing outside.
/// Each value is one of the engine's [Easings]; [transform] evaluates it.
/// An effect saves the value's [name], so the names never change.
enum EasingType {
  /// Constant speed ([Easings.linear]).
  linear(Easings.linear),

  /// Starts at rest and accelerates ([Easings.easeInQuad]).
  easeInQuad(Easings.easeInQuad),

  /// Starts fast and decelerates to rest ([Easings.easeOutQuad]).
  easeOutQuad(Easings.easeOutQuad),

  /// Accelerates, then decelerates ([Easings.easeInOutQuad]).
  easeInOutQuad(Easings.easeInOutQuad),

  /// Accelerates, more sharply than quad ([Easings.easeInCubic]).
  easeInCubic(Easings.easeInCubic),

  /// Decelerates to rest, more sharply than quad ([Easings.easeOutCubic]).
  easeOutCubic(Easings.easeOutCubic),

  /// Accelerates, then decelerates; cubic ([Easings.easeInOutCubic]).
  easeInOutCubic(Easings.easeInOutCubic),

  /// Accelerates gently ([Easings.easeInSine]).
  easeInSine(Easings.easeInSine),

  /// Decelerates gently to rest ([Easings.easeOutSine]).
  easeOutSine(Easings.easeOutSine),

  /// Accelerates, then decelerates, gently ([Easings.easeInOutSine]).
  easeInOutSine(Easings.easeInOutSine),

  /// Almost flat, then a steep rush at the end ([Easings.easeInExpo]).
  easeInExpo(Easings.easeInExpo),

  /// A steep rush, then almost flat into the end ([Easings.easeOutExpo]).
  easeOutExpo(Easings.easeOutExpo),

  /// Oscillates around 0, dipping below it, then snaps to 1
  /// ([Easings.easeInElastic]).
  easeInElastic(Easings.easeInElastic),

  /// Overshoots 1 and oscillates down to settle on it
  /// ([Easings.easeOutElastic]).
  easeOutElastic(Easings.easeOutElastic),

  /// Growing hops off 0, then a rise into 1 ([Easings.easeInBounce]).
  easeInBounce(Easings.easeInBounce),

  /// Falls to 1 and bounces off it to rest ([Easings.easeOutBounce]).
  easeOutBounce(Easings.easeOutBounce);

  const EasingType(this.curve);

  /// The function from [Easings] this value names.
  final EasingFunction curve;

  /// Evaluates this curve at normalised progress [t] ∈ `[0, 1]`.
  double transform(double t) => curve(t);
}
