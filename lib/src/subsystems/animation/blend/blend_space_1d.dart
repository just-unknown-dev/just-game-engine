/// 1D Blend Space
///
/// Linear interpolation between the two thresholds that bracket a query
/// parameter (Unity's "Simple 1D" blend type) — e.g. blending idle/walk/run
/// clips along a single "speed" parameter.
library;

/// Blends a set of ascending [thresholds] against a single scalar parameter.
///
/// [thresholds] must be sorted ascending and is index-aligned with whatever
/// clip list the caller associates with each threshold — [evaluate] returns
/// weights in that same order.
class BlendSpace1D {
  BlendSpace1D(List<double> thresholds)
    : assert(
        _isSorted(thresholds),
        'BlendSpace1D thresholds must be sorted ascending',
      ),
      thresholds = List.unmodifiable(thresholds);

  /// Ascending sample thresholds.
  final List<double> thresholds;

  /// Returns weights parallel to [thresholds], summing to 1.0 (or `[]` if
  /// [thresholds] is empty).
  ///
  /// [parameter] outside the threshold range clamps to the nearest end
  /// (weight 1.0 on the first/last threshold). Between two thresholds the
  /// weight is a plain linear interpolation.
  List<double> evaluate(double parameter) {
    final n = thresholds.length;
    if (n == 0) return const [];
    if (n == 1) return [1.0];

    if (parameter <= thresholds[0]) {
      return [1.0, for (var i = 1; i < n; i++) 0.0];
    }
    if (parameter >= thresholds[n - 1]) {
      return [for (var i = 0; i < n - 1; i++) 0.0, 1.0];
    }

    for (var i = 0; i < n - 1; i++) {
      final lo = thresholds[i];
      final hi = thresholds[i + 1];
      if (parameter > hi) continue;

      final weights = List<double>.filled(n, 0.0);
      final span = hi - lo;
      final t = span > 0 ? (parameter - lo) / span : 0.0;
      weights[i] = 1.0 - t;
      weights[i + 1] = t;
      return weights;
    }

    // Unreachable given the clamps above, but keeps the function total.
    return [for (var i = 0; i < n - 1; i++) 0.0, 1.0];
  }

  static bool _isSorted(List<double> values) {
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[i - 1]) return false;
    }
    return true;
  }
}
