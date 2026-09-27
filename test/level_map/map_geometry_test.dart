// The arithmetic behind all four orientations, checked as properties that
// must hold for every cell rather than as a handful of numbers: a cell's
// centre is in that cell, neighbours are mutual and touch, the coordinate
// systems stamps use map back exactly.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _geometries = <String, MapGeometry>{
  'orthogonal': MapGeometry(tileWidth: 32, tileHeight: 32),
  'orthogonal (wide cells)': MapGeometry(tileWidth: 48, tileHeight: 24),
  'isometric': MapGeometry(
    orientation: MapOrientation.isometric,
    tileWidth: 64,
    tileHeight: 32,
  ),
  for (final axis in TileStaggerAxis.values)
    for (final index in TileStaggerIndex.values) ...{
      'staggered ${axis.name}/${index.name}': MapGeometry(
        orientation: MapOrientation.staggered,
        tileWidth: 64,
        tileHeight: 32,
        staggerAxis: axis,
        staggerIndex: index,
      ),
      'hexagonal ${axis.name}/${index.name}': MapGeometry(
        orientation: MapOrientation.hexagonal,
        tileWidth: 28,
        tileHeight: 24,
        hexSideLength: 12,
        staggerAxis: axis,
        staggerIndex: index,
      ),
    },
};

final _cells = [
  for (var y = -5; y <= 5; y++)
    for (var x = -5; x <= 5; x++) TileCoord(x, y),
];

bool _inside(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

void main() {
  for (final MapEntry(key: name, value: g) in _geometries.entries) {
    group(name, () {
      test("a cell's centre is in that cell", () {
        for (final c in _cells) {
          expect(g.cellAt(g.cellCenter(c.x, c.y)), c, reason: '$c');
        }
      });

      test('points just inside the outline are in the cell', () {
        for (final c in _cells) {
          final centre = g.cellCenter(c.x, c.y);
          for (final corner in g.cellPolygon(c.x, c.y)) {
            // A tenth of the way in from each corner.
            final p = Offset.lerp(corner, centre, 0.1)!;
            expect(g.cellAt(p), c, reason: '$c near $corner');
          }
        }
      });

      test('the centre is inside the outline', () {
        for (final c in _cells) {
          expect(
            _inside(g.cellPolygon(c.x, c.y), g.cellCenter(c.x, c.y)),
            isTrue,
          );
        }
      });

      test('neighbours are mutual, distinct, and next to each other', () {
        final expected = g.orientation == MapOrientation.hexagonal ? 6 : 4;
        final reach = g.tileWidth * 1.01 > g.tileHeight * 1.01
            ? g.tileWidth * 1.01
            : g.tileHeight * 1.01;
        for (final c in _cells) {
          final ns = g.neighbours(c);
          expect(ns.toSet(), hasLength(expected), reason: '$c');
          for (final n in ns) {
            expect(g.neighbours(n), contains(c), reason: '$c ↔ $n');
            final d =
                (g.cellCenter(n.x, n.y) - g.cellCenter(c.x, c.y)).distance;
            expect(d, lessThanOrEqualTo(reach), reason: '$c to $n');
          }
        }
      });

      test('an area covers every cell whose centre it holds', () {
        const area = Rect.fromLTWH(-37, -53, 211, 149);
        final range = g.cellRange(area);
        for (final c in _cells) {
          if (area.contains(g.cellCenter(c.x, c.y))) {
            expect(range.contains(c.x, c.y), isTrue, reason: '$c');
          }
        }
        expect(
          g.cellsIn(area).every((c) => area.contains(g.cellCenter(c.x, c.y))),
          isTrue,
        );
      });

      test('stable coordinates map back exactly', () {
        for (final c in _cells) {
          expect(g.fromStable(g.toStable(c)), c);
        }
      });

      test('in stable coordinates, a step is a step whatever the parity', () {
        // Moving one stable step from any cell reaches a neighbour: that is
        // what lets a stamp keep its shape on staggered rows.
        if (g.orientation == MapOrientation.orthogonal) return;
        for (final c in _cells) {
          final s = g.toStable(c);
          for (final step in const [TileCoord(1, 0), TileCoord(0, 1)]) {
            final next = g.fromStable(s + step);
            expect(g.neighbours(c), contains(next), reason: '$c + $step');
          }
        }
      });

      test('mirroring twice and turning all the way round change nothing', () {
        final steps = g.orientation == MapOrientation.hexagonal ? 6 : 4;
        for (final d in const [
          TileCoord(2, -1),
          TileCoord(-3, 4),
          TileCoord(0, 5),
        ]) {
          expect(g.mirrorH(g.mirrorH(d)), d);
          expect(g.mirrorV(g.mirrorV(d)), d);
          var t = d;
          for (var i = 0; i < steps; i++) {
            t = g.turn(t);
          }
          expect(t, d);
          expect(g.turn(g.turn(d), clockwise: false), d);
        }
      });

      test('mirroring an offset left to right mirrors it on screen', () {
        final origin = g.cellCenter(0, 0);
        for (final d in const [TileCoord(2, -1), TileCoord(1, 3)]) {
          final a = g.fromStable(d);
          final b = g.fromStable(g.mirrorH(d));
          final ca = g.cellCenter(a.x, a.y) - origin;
          final cb = g.cellCenter(b.x, b.y) - origin;
          expect(cb.dx, closeTo(-ca.dx, 0.01), reason: '$d');
          expect(cb.dy, closeTo(ca.dy, 0.01), reason: '$d');
        }
      });
    });
  }

  test('an isometric cell (0, 0) has its top corner at the origin', () {
    final g = _geometries['isometric']!;
    expect(g.cellPolygon(0, 0).first, Offset.zero);
    expect(g.cellCenter(1, 0), const Offset(32, 32));
    expect(g.cellCenter(0, 1), const Offset(-32, 32));
  });

  test('a tall tile rises above its cell, bottom-aligned', () {
    final g = MapGeometry(tileWidth: 32, tileHeight: 32);
    expect(
      g.tileImageRect(2, 1, 32, 64, offsetX: 1, offsetY: -2),
      const Rect.fromLTWH(65, 0 - 2, 32, 64),
    );
  });

  test('draw order is back to front on screen', () {
    final g = _geometries['isometric']!;
    final cells = [
      const TileCoord(1, 1),
      const TileCoord(0, 0),
      const TileCoord(1, 0),
    ]..sort(g.compareDrawOrder);
    expect(cells, [
      const TileCoord(0, 0),
      const TileCoord(1, 0),
      const TileCoord(1, 1),
    ]);
  });
}
