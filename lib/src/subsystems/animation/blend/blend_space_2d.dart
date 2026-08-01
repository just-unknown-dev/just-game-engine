/// 2D Blend Space — Gradient Band Interpolation
///
/// Implements the weighting algorithm behind Unity's Freeform
/// Directional/Cartesian 2D blend trees, originally described by Rune
/// Skovbo Johansen ("Gradient Band Interpolation"). Adapted here for
/// sprite-sheet frame blending rather than skeletal pose blending — see
/// [BlendCompositor] (`blend_compositor.dart`) for how the resulting
/// weights become pixels.
///
/// ## Algorithm
///
/// For every sample point `i`, and every *other* sample point `j`, project
/// the query onto the line from `i` toward `j` and take a linear falloff
/// that is 1.0 at `i` and 0.0 at `j`:
///
/// ```text
/// t_ij    = dot(query - p_i, p_j - p_i) / dot(p_j - p_i, p_j - p_i)
/// band_ij = 1 - t_ij
/// ```
///
/// `i`'s raw weight is the *most restrictive* (minimum) band across all its
/// neighbors, clamped at 0. Summing every point's raw weight and dividing
/// each by that sum yields the final weights.
///
/// Querying exactly at a sample point `p_i` always yields weight 1 for `i`
/// and 0 for every other point — this holds for *any* layout of distinct
/// points, not just symmetric ones (at `query = p_i`, every other point `k`
/// has `t = 1` against neighbor `i` specifically, so `band_ki = 0`, which
/// floors `k`'s weight to 0 regardless of the rest of the layout; see the
/// proof in `ANIMATION_BLEND_TREE.md`).
///
/// What is **not** guaranteed for arbitrary scattered layouts is smooth,
/// intuitive behavior *between* samples — a point can be weighted down
/// more than expected by a poorly-positioned neighbor even where it should
/// visually dominate. This behaves well for symmetric/radial layouts, such
/// as the 8-directional locomotion layout this was built for. See
/// `ANIMATION_BLEND_TREE.md` at the package root for the full write-up and
/// this limitation in context.
library;

import 'package:flutter/painting.dart' show Offset;

const double _epsilon = 1e-9;

/// Blends a set of 2D sample [points] against a query point.
class BlendSpace2D {
  BlendSpace2D(List<Offset> points) : points = List.unmodifiable(points);

  /// Sample positions in parameter space, index-aligned with whatever clip
  /// list the caller associates with each point.
  final List<Offset> points;

  /// Returns weights parallel to [points], summing to 1.0 (or `[]` if
  /// [points] is empty).
  List<double> evaluate(Offset query) {
    final n = points.length;
    if (n == 0) return const [];
    if (n == 1) return [1.0];

    final weights = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      var weight = double.infinity;
      final iq = query - points[i];
      for (var j = 0; j < n; j++) {
        if (j == i) continue;
        final ij = points[j] - points[i];
        final ijLenSq = ij.dx * ij.dx + ij.dy * ij.dy;
        if (ijLenSq < _epsilon) continue; // duplicate/coincident sample guard
        final t = (iq.dx * ij.dx + iq.dy * ij.dy) / ijLenSq;
        final band = 1.0 - t;
        if (band < weight) weight = band;
      }
      weights[i] = weight.isFinite ? (weight < 0.0 ? 0.0 : weight) : 0.0;
    }

    var sum = 0.0;
    for (final w in weights) {
      sum += w;
    }
    if (sum < _epsilon) return _nearestFallback(query);

    for (var i = 0; i < n; i++) {
      weights[i] /= sum;
    }
    return weights;
  }

  /// Every raw weight collapsed to ~0 (e.g. every point coincides with
  /// every other point) — fall back to the single nearest sample rather
  /// than dividing by ~0.
  List<double> _nearestFallback(Offset query) {
    final weights = List<double>.filled(points.length, 0.0);
    var nearest = 0;
    var nearestDistSq = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - query).distanceSquared;
      if (d < nearestDistSq) {
        nearestDistSq = d;
        nearest = i;
      }
    }
    weights[nearest] = 1.0;
    return weights;
  }
}
