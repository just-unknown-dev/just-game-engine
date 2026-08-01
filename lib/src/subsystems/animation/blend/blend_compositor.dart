/// Weighted Sprite Compositing
///
/// Turns a set of blend weights (Σw = 1) into sequential Porter-Duff "over"
/// alphas that reproduce a true per-pixel weighted average once every layer
/// has been drawn — see [BlendCompositor.cumulativeAlphas] for the formula
/// and why reusing a raw weight directly as its layer's alpha is a
/// different, generally wrong formula rather than an equivalent shortcut.
library;

const double _epsilon = 1e-9;

/// Static namespace for turning blend weights into per-layer draw alphas.
abstract final class BlendCompositor {
  /// Returns per-layer alphas parallel to [weights], such that sequentially
  /// drawing each layer with e.g. `canvas.drawImageRect(..., paint..color =
  /// baseColor.withValues(alpha: alphas[k]))` — in any fixed order —
  /// reproduces `Σ weights[i] * pixel[i]` once all layers are drawn.
  ///
  /// Formula: `alpha[k] = weights[k] / (weights[0] + ... + weights[k])`
  /// (the running sum *through* k, inclusive) — so the first layer with any
  /// weight is always drawn fully opaque (`alpha == 1.0`, since its running
  /// sum equals its own weight) and later layers get progressively smaller
  /// alphas as the running sum grows toward 1.
  ///
  /// Proof sketch: after drawing layers `0..k` with these alphas, the
  /// canvas holds the running weighted average of those layers. Drawing
  /// layer `k+1` with `alpha[k+1] = weights[k+1] / runningSum(0..k+1)`
  /// blends it in at exactly its share of the new running sum — the
  /// definition of extending a weighted running mean by one term. This
  /// holds for any layer count and, given `Σweights = 1`, converges to the
  /// exact weighted average.
  ///
  /// This is exactly the familiar two-layer crossfade pattern ("draw A
  /// opaque, draw B on top at alpha = t") generalized to N layers — it is
  /// **not** the same as reusing each raw `weights[k]` directly as that
  /// layer's alpha (which would give the base layer alpha `weights[0]`
  /// instead of `1.0`). That direct-reuse shortcut is a different formula,
  /// generally wrong, and the discrepancy is easy to demonstrate once there
  /// are three or more simultaneously-blended layers — see
  /// `blend_animation_math_test.dart` for a worked regression case.
  static List<double> cumulativeAlphas(List<double> weights) {
    final alphas = List<double>.filled(weights.length, 0.0);
    var running = 0.0;
    for (var k = 0; k < weights.length; k++) {
      running += weights[k];
      alphas[k] = running > _epsilon ? weights[k] / running : 0.0;
    }
    return alphas;
  }
}
