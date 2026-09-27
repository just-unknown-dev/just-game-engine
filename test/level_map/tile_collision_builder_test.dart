// A layer's collision as bodies: whole-cell ground merged into long boxes,
// everything else convex polygons small enough for Box2D.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

TilesetData _tileset() =>
    TilesetData(
        name: 't',
        image: 't.png',
        tileWidth: 16,
        tileHeight: 16,
        columns: 4,
        tileCount: 8,
      )
      // 0: solid, 1: one-way, 2: a slope rising to the right, 3: none,
      // 4: an L-shaped ledge, 5: a kind nobody registered.
      ..tileOrNew(0).collision = TileCollision.full(16, 16)
      ..tileOrNew(1).collision = TileCollision.full(16, 16, kind: 'oneWay')
      ..tileOrNew(2).collision = TileCollision(
        shapes: [
          const TilePolygonShape([
            Offset(0, 16),
            Offset(16, 0),
            Offset(16, 16),
          ]),
        ],
      )
      ..tileOrNew(4).collision = TileCollision(
        shapes: [
          const TilePolygonShape([
            Offset(0, 0),
            Offset(16, 0),
            Offset(16, 8),
            Offset(8, 8),
            Offset(8, 16),
            Offset(0, 16),
          ]),
        ],
      )
      ..tileOrNew(5).collision = TileCollision.full(16, 16, kind: 'lava')
      // 6: a half-height ledge at the bottom; 7: the top-left and top-right
      // quarters, as terrain draws a ceiling.
      ..tileOrNew(6).collision = TileCollision(
        shapes: [const TileRectShape(Rect.fromLTWH(0, 8, 16, 8))],
      )
      ..tileOrNew(7).collision = TileCollision(
        shapes: [
          const TileRectShape(Rect.fromLTWH(0, 0, 8, 8)),
          const TileRectShape(Rect.fromLTWH(8, 0, 8, 8)),
        ],
      );

List<MapBodySpec> _build(
  void Function(TileChunkStore s) paint, {
  MapGeometry? geometry,
  Offset offset = Offset.zero,
}) {
  final cells = TileChunkStore();
  paint(cells);
  final ts = _tileset();
  return TileCollisionBuilder.build(
    cells: cells,
    geometry: geometry ?? MapGeometry(tileWidth: 16, tileHeight: 16),
    tilesetAt: (slot) => slot == 0 ? ts : null,
    offset: offset,
  );
}

void main() {
  test('solid ground merges into one box per block', () {
    final bodies = _build((s) {
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 10; x++) {
          s.setCell(x, y, TileCell.make(0, 0));
        }
      }
    });
    expect(bodies, hasLength(1));
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 0, 160, 48));
    expect(bodies.single.cells, hasLength(30));
  });

  test('an L of ground is two boxes, rows first', () {
    final bodies = _build((s) {
      for (var x = 0; x < 5; x++) {
        s.setCell(x, 0, TileCell.make(0, 0));
      }
      s.setCell(0, 1, TileCell.make(0, 0));
    });
    expect(bodies.map((b) => b.bounds).toSet(), {
      const Rect.fromLTWH(0, 0, 80, 16),
      const Rect.fromLTWH(0, 16, 16, 16),
    });
  });

  test('one-way tiles join along rows only, and stay apart from solid', () {
    final bodies = _build((s) {
      for (var x = 0; x < 4; x++) {
        s.setCell(x, 0, TileCell.make(0, 1));
        s.setCell(x, 1, TileCell.make(0, 1));
        s.setCell(x, 2, TileCell.make(0, 0));
      }
    });
    final oneWay = bodies.where((b) => b.kind == 'oneWay').toList();
    expect(oneWay, hasLength(2));
    expect(bodies.where((b) => b.kind == 'solid'), hasLength(1));
  });

  test('a tile of an unknown kind still collides, and keeps its kind', () {
    final bodies = _build((s) => s.setCell(0, 0, TileCell.make(0, 5)));
    expect(bodies.single.kind, 'lava');
  });

  test('a slope is a triangle where the tile is', () {
    final body = _build((s) => s.setCell(2, 1, TileCell.make(0, 2))).single;
    expect(body.isBox, isFalse);
    expect(body.bounds, const Rect.fromLTWH(32, 16, 16, 16));
    expect(body.polygon, hasLength(3));
  });

  test('a mirrored slope rises the other way', () {
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 2, TileCell.flipH)),
    ).single;
    final points = [for (final p in body.polygon!) p + body.center];
    // The high corner is now on the left.
    expect(points, contains(const Offset(0, 0)));
    expect(points, isNot(contains(const Offset(16, 0))));
  });

  test('a concave shape becomes convex pieces covering the same area', () {
    final bodies = _build((s) => s.setCell(0, 0, TileCell.make(0, 4)));
    expect(bodies.length, greaterThanOrEqualTo(2));
    var area = 0.0;
    for (final b in bodies) {
      expect(
        PolygonDecompose.isConvex(PolygonDecompose.clean(b.polygon!)),
        isTrue,
      );
      expect(b.polygon!.length, lessThanOrEqualTo(8));
      area +=
          PolygonDecompose.signedArea2(
            PolygonDecompose.clean(b.polygon!),
          ).abs() /
          2;
    }
    expect(area, closeTo(16 * 16 - 8 * 8, 0.01));
  });

  test('half-tile ledges along a row are one box, with no seams', () {
    final bodies = _build((s) {
      for (var x = 0; x < 6; x++) {
        s.setCell(x, 2, TileCell.make(0, 6));
      }
    });
    expect(bodies, hasLength(1));
    expect(bodies.single.isBox, isTrue);
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 40, 96, 8));
    expect(bodies.single.cells, hasLength(6));
  });

  test('quarters of a tile join each other and their neighbours', () {
    final bodies = _build((s) {
      s
        ..setCell(0, 0, TileCell.make(0, 7))
        ..setCell(1, 0, TileCell.make(0, 7));
    });
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 0, 32, 8));
  });

  test('a ledge turned on its side is still a box, and stacks', () {
    final bodies = _build((s) {
      for (var y = 0; y < 3; y++) {
        s.setCell(0, y, TileCell.make(0, 6, TileCell.flipD));
      }
    });
    // Mirrored across the diagonal, the bottom half becomes the right half.
    expect(bodies.single.isBox, isTrue);
    expect(bodies.single.bounds, const Rect.fromLTWH(8, 0, 8, 48));
  });

  test('a layer offset moves every body', () {
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 0)),
      offset: const Offset(100, -20),
    ).single;
    expect(body.bounds, const Rect.fromLTWH(100, -20, 16, 16));
  });

  test('an isometric tile collides where its image is drawn', () {
    final g = MapGeometry(
      orientation: MapOrientation.isometric,
      tileWidth: 32,
      tileHeight: 16,
    );
    // Tile 0 is a whole 16×16 box, which on an isometric map is not a
    // whole cell — but still an upright box, where the image is.
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 0)),
      geometry: g,
    ).single;
    expect(body.isBox, isTrue);
    expect(body.bounds, g.tileImageRect(0, 0, 16, 16));
  });

  group('convex pieces', () {
    test('a convex polygon over eight points is fanned', () {
      final twelve = [
        for (var i = 0; i < 12; i++)
          Offset(
            100 * (1 + 0.5 * (i.isEven ? 1 : 0.999)) * _cos(i * 30),
            100 * _sin(i * 30),
          ),
      ];
      final pieces = PolygonDecompose.convexPieces(twelve);
      expect(pieces.length, greaterThan(1));
      expect(pieces.every((p) => p.length <= 8), isTrue);
    });

    test('points in a straight line are dropped', () {
      final square = PolygonDecompose.clean(const [
        Offset(0, 0),
        Offset(5, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ]);
      expect(square, hasLength(4));
    });

    test('a shape with no area gives nothing', () {
      expect(
        PolygonDecompose.convexPieces(const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(2, 2),
        ]),
        isEmpty,
      );
    });
  });

  test('merging cells: rows, then stacks of the same span', () {
    final cells = {
      for (var x = 0; x < 3; x++) ...[TileCoord(x, 0), TileCoord(x, 1)],
      const TileCoord(0, 2),
    };
    final area = TileCollisionBuilder.mergeCells(cells, TileMergeMode.area);
    expect(area, hasLength(2));
    final rows = TileCollisionBuilder.mergeCells(cells, TileMergeMode.rows);
    expect(rows, hasLength(3));
    expect(
      TileCollisionBuilder.mergeCells(cells, TileMergeMode.none),
      hasLength(7),
    );
  });
}

double _cos(double degrees) => _trig(degrees, true);
double _sin(double degrees) => _trig(degrees, false);
double _trig(double degrees, bool cos) {
  final r = degrees * 3.141592653589793 / 180;
  // A few terms of the series is plenty for building a test polygon.
  double c = 1, s = r, term = 1;
  for (var n = 1; n < 12; n++) {
    term *= -r * r / ((2 * n - 1) * (2 * n));
    c += term;
  }
  term = r;
  for (var n = 1; n < 12; n++) {
    term *= -r * r / ((2 * n) * (2 * n + 1));
    s += term;
  }
  return cos ? c : s;
}
