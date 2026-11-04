/// What the 2-D and 3-D physics systems share about making a body again.
library;

import 'dart:math' as math;

/// When a body is made again for a change of its entity's scale: the shape
/// of a body is fixed when it is made, so `Physics2DSystem` and
/// `Physics3DSystem` make it again for a new scale — but not for float
/// noise.
abstract final class BodyRebuild {
  /// The smallest change of an entity's scale, as a fraction of the scale
  /// its body was made at, that makes the body again. Less is float noise —
  /// an animation or a tween ending at 1.0000001 — and making the body again
  /// for it every step also made its joints again each step.
  static const double scaleTolerance = 1e-4;

  /// Whether [now] is within [scaleTolerance] of [made]: the scale a body
  /// was made at still.
  static bool sameScale(double made, double now) =>
      made == now ||
      (now - made).abs() <= scaleTolerance * math.max(made.abs(), now.abs());
}
