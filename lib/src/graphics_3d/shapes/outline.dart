import 'dart:math' as math;

/// Plane outlines: the maths behind a polygon shape. A point is (x, y) in
/// the outline's own plane; for `Polygon3D` that is (x, z) on the ground.
abstract final class Outline {
  static const double _eps = 1e-9;

  /// Twice the signed area of [points]: above 0 when they run
  /// counter-clockwise (x right, y up).
  static double signedArea2(List<(double, double)> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final (x0, y0) = points[i];
      final (x1, y1) = points[(i + 1) % points.length];
      sum += x0 * y1 - x1 * y0;
    }
    return sum;
  }

  /// [points] without repeats (a point equal to the one before it, the last
  /// equal to the first) and without corners that make no turn.
  static List<(double, double)> clean(List<(double, double)> points) {
    final out = <(double, double)>[];
    for (final p in points) {
      if (out.isNotEmpty && _same(out.last, p)) continue;
      out.add(p);
    }
    while (out.length > 1 && _same(out.first, out.last)) {
      out.removeLast();
    }
    var changed = true;
    while (changed && out.length >= 3) {
      changed = false;
      for (var i = 0; i < out.length; i++) {
        final a = out[(i - 1 + out.length) % out.length];
        final b = out[i];
        final c = out[(i + 1) % out.length];
        final turn = _cross(a, b, c);
        final scale = _length(a, b) * _length(b, c);
        if (turn.abs() <= 1e-9 * math.max(scale, 1e-12)) {
          out.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    return out;
  }

  /// Whether [points] (cleaned) turn the same way at every corner.
  static bool isConvex(List<(double, double)> points) {
    if (points.length < 3) return false;
    var sign = 0;
    for (var i = 0; i < points.length; i++) {
      final turn = _cross(
        points[i],
        points[(i + 1) % points.length],
        points[(i + 2) % points.length],
      );
      if (turn.abs() <= _eps) continue;
      final s = turn > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return sign != 0;
  }

  /// Triangles covering the simple polygon [points] by ear clipping: three
  /// indices into [points] each, every triangle counter-clockwise. A
  /// polygon that crosses itself gets what could be cut before it stuck.
  static List<int> triangulate(List<(double, double)> points) {
    final n = points.length;
    if (n < 3) return const [];
    final ccw = signedArea2(points) > 0;
    final ring = [for (var i = 0; i < n; i++) ccw ? i : n - 1 - i];
    final out = <int>[];
    while (ring.length > 3) {
      var cut = false;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[(i - 1 + ring.length) % ring.length];
        final b = ring[i];
        final c = ring[(i + 1) % ring.length];
        if (_cross(points[a], points[b], points[c]) <= _eps) continue;
        var empty = true;
        for (final p in ring) {
          if (p == a || p == b || p == c) continue;
          final q = points[p];
          if (_same(q, points[a]) ||
              _same(q, points[b]) ||
              _same(q, points[c])) {
            continue;
          }
          if (_inside(q, points[a], points[b], points[c])) {
            empty = false;
            break;
          }
        }
        if (!empty) continue;
        out.addAll([a, b, c]);
        ring.removeAt(i);
        cut = true;
        break;
      }
      if (!cut) {
        // Stuck: the outline crosses itself. Drop a corner that makes no
        // turn if there is one, else give up.
        final flat = ring.indexWhere((b) {
          final i = ring.indexOf(b);
          return _cross(
                points[ring[(i - 1 + ring.length) % ring.length]],
                points[b],
                points[ring[(i + 1) % ring.length]],
              ).abs() <=
              _eps;
        });
        if (flat < 0) return out;
        ring.removeAt(flat);
      }
    }
    if (_cross(points[ring[0]], points[ring[1]], points[ring[2]]) > _eps) {
      out.addAll(ring);
    }
    return out;
  }

  /// [triangles] (from [triangulate]) merged into convex polygons
  /// (Hertel–Mehlhorn): no more than four times the fewest possible. Each
  /// polygon is a counter-clockwise list of indices into [points].
  static List<List<int>> convexParts(
    List<(double, double)> points,
    List<int> triangles,
  ) {
    final parts = [
      for (var i = 0; i + 2 < triangles.length; i += 3)
        [triangles[i], triangles[i + 1], triangles[i + 2]],
    ];
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var a = 0; a < parts.length; a++) {
        for (var b = a + 1; b < parts.length; b++) {
          final joined = _join(parts[a], parts[b]);
          if (joined == null) continue;
          if (!isConvex([for (final i in joined) points[i]])) continue;
          parts[a] = joined;
          parts.removeAt(b);
          merged = true;
          break outer;
        }
      }
    }
    return parts;
  }

  /// [a] and [b] as one polygon when they share an edge (running opposite
  /// ways), else null.
  static List<int>? _join(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      final u = a[i];
      final v = a[(i + 1) % a.length];
      for (var j = 0; j < b.length; j++) {
        if (b[j] != v || b[(j + 1) % b.length] != u) continue;
        // a from v round to u, then b from after u round to before v.
        final out = <int>[];
        for (var k = 0; k < a.length; k++) {
          out.add(a[(i + 1 + k) % a.length]);
        }
        for (var k = 2; k < b.length; k++) {
          out.add(b[(j + k) % b.length]);
        }
        return out;
      }
    }
    return null;
  }

  static bool _same((double, double) a, (double, double) b) =>
      (a.$1 - b.$1).abs() <= 1e-9 && (a.$2 - b.$2).abs() <= 1e-9;

  static double _length((double, double) a, (double, double) b) =>
      math.sqrt((b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2));

  /// (b − a) × (c − a): above 0 when a, b, c turn counter-clockwise.
  static double _cross(
    (double, double) a,
    (double, double) b,
    (double, double) c,
  ) => (b.$1 - a.$1) * (c.$2 - a.$2) - (b.$2 - a.$2) * (c.$1 - a.$1);

  static bool _inside(
    (double, double) p,
    (double, double) a,
    (double, double) b,
    (double, double) c,
  ) =>
      _cross(a, b, p) >= -_eps &&
      _cross(b, c, p) >= -_eps &&
      _cross(c, a, p) >= -_eps;
}
