/// Splitting any polygon into convex pieces a physics engine accepts.
library;

import 'dart:ui';

/// Convex decomposition for collision shapes.
///
/// Both physics backends take convex polygons only, and Box2D at most eight
/// vertices each. A tile's collision may be any polygon a designer drew —
/// an L-shaped ledge, a notch — so it is cut up: ear-clipped into
/// triangles, the triangles merged back (Hertel–Mehlhorn) while they stay
/// convex and small enough, and anything convex but too large fanned into
/// pieces.
abstract final class PolygonDecompose {
  /// Box2D's limit.
  static const int maxVertices = 8;

  /// Twice the signed area: positive when [p] runs clockwise on a y-down
  /// screen.
  static double signedArea2(List<Offset> p) {
    var sum = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum;
  }

  static double _cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  /// [p] without repeated or collinear points, wound with positive signed
  /// area.
  static List<Offset> clean(List<Offset> p, {double epsilon = 1e-6}) {
    var pts = <Offset>[];
    for (final q in p) {
      if (pts.isEmpty || (pts.last - q).distanceSquared > epsilon) pts.add(q);
    }
    if (pts.length > 1 && (pts.first - pts.last).distanceSquared <= epsilon) {
      pts.removeLast();
    }
    var changed = true;
    while (changed && pts.length >= 3) {
      changed = false;
      for (var i = 0; i < pts.length; i++) {
        final a = pts[(i - 1 + pts.length) % pts.length];
        final b = pts[i];
        final c = pts[(i + 1) % pts.length];
        if (_cross(a, b, c).abs() <= epsilon) {
          pts.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    if (pts.length >= 3 && signedArea2(pts) < 0) pts = pts.reversed.toList();
    return pts;
  }

  /// Whether [p] (cleaned) is convex.
  static bool isConvex(List<Offset> p) {
    if (p.length < 3) return false;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      final c = p[(i + 2) % p.length];
      if (_cross(a, b, c) < -1e-9) return false;
    }
    return true;
  }

  /// [polygon] as convex pieces of at most [maxVertices] points. Empty when
  /// it has no area.
  static List<List<Offset>> convexPieces(
    List<Offset> polygon, {
    int maxVertices = PolygonDecompose.maxVertices,
  }) {
    final p = clean(polygon);
    if (p.length < 3) return const [];
    if (isConvex(p)) return _fan(p, maxVertices);
    final triangles = _earClip(p);
    return [
      for (final piece in _merge(triangles, maxVertices))
        ..._fan(piece, maxVertices),
    ];
  }

  /// A convex polygon cut into fans of at most [max] points.
  static List<List<Offset>> _fan(List<Offset> p, int max) {
    if (p.length <= max) return [p];
    final out = <List<Offset>>[];
    var start = 1;
    while (start < p.length - 1) {
      final end = (start + max - 2).clamp(start + 1, p.length - 1);
      out.add([p[0], for (var i = start; i <= end; i++) p[i]]);
      start = end;
    }
    return out;
  }

  static bool _inTriangle(Offset p, Offset a, Offset b, Offset c) {
    final d1 = _cross(a, b, p);
    final d2 = _cross(b, c, p);
    final d3 = _cross(c, a, p);
    return d1 >= 0 && d2 >= 0 && d3 >= 0;
  }

  /// Triangles of a simple polygon with positive winding.
  static List<List<Offset>> _earClip(List<Offset> polygon) {
    final pts = [...polygon];
    final out = <List<Offset>>[];
    var guard = 0;
    while (pts.length > 3 && guard++ < 10000) {
      var clipped = false;
      for (var i = 0; i < pts.length; i++) {
        final a = pts[(i - 1 + pts.length) % pts.length];
        final b = pts[i];
        final c = pts[(i + 1) % pts.length];
        if (_cross(a, b, c) <= 1e-9) continue; // reflex or flat
        var empty = true;
        for (final q in pts) {
          if (q == a || q == b || q == c) continue;
          if (_inTriangle(q, a, b, c)) {
            empty = false;
            break;
          }
        }
        if (!empty) continue;
        out.add([a, b, c]);
        pts.removeAt(i);
        clipped = true;
        break;
      }
      // A self-touching outline can leave no clean ear; fall back to a
      // fan of what is left rather than looping.
      if (!clipped) break;
    }
    if (pts.length == 3) {
      out.add(pts);
    } else if (pts.length > 3) {
      for (var i = 1; i < pts.length - 1; i++) {
        out.add([pts[0], pts[i], pts[i + 1]]);
      }
    }
    return out;
  }

  /// Joins pieces that share an edge while the result stays convex and
  /// within [max] points.
  static List<List<Offset>> _merge(List<List<Offset>> pieces, int max) {
    final list = [...pieces];
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final joined = _join(list[i], list[j]);
          if (joined == null) continue;
          final cleaned = clean(joined);
          if (cleaned.length > max || !isConvex(cleaned)) continue;
          list[i] = cleaned;
          list.removeAt(j);
          merged = true;
          break outer;
        }
      }
    }
    return list;
  }

  /// [a] and [b] joined across an edge they share (b runs it backwards),
  /// or null.
  static List<Offset>? _join(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < a.length; i++) {
      final a0 = a[i];
      final a1 = a[(i + 1) % a.length];
      for (var j = 0; j < b.length; j++) {
        final b0 = b[j];
        final b1 = b[(j + 1) % b.length];
        if (a0 == b1 && a1 == b0) {
          // Walk a up to a0, then b from after b1 round to before b0, then
          // on from a1.
          final out = <Offset>[];
          for (var k = 0; k <= i; k++) {
            out.add(a[k]);
          }
          for (var k = 2; k < b.length; k++) {
            out.add(b[(j + k) % b.length]);
          }
          for (var k = i + 1; k < a.length; k++) {
            out.add(a[k]);
          }
          return out;
        }
      }
    }
    return null;
  }
}
