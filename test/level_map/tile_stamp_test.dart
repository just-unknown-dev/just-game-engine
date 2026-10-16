// A stamp keeps its shape wherever it is put down, and flips and turns move
// its cells as well as turning each tile — on every orientation.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _geometries = <String, MapGeometry>{
  'orthogonal': MapGeometry(tileWidth: 32, tileHeight: 32),
  'isometric': MapGeometry(
    orientation: MapOrientation.isometric,
    tileWidth: 64,
    tileHeight: 32,
  ),
  'staggered': MapGeometry(
    orientation: MapOrientation.staggered,
    tileWidth: 64,
    tileHeight: 32,
  ),
  'hexagonal': MapGeometry(
    orientation: MapOrientation.hexagonal,
    tileWidth: 28,
    tileHeight: 24,
    hexSideLength: 12,
  ),
};

/// Where each cell's centre is relative to the first one: the shape of a
/// group of cells on screen.
List<(double, double)> _shape(MapGeometry g, List<TileCoord> cells) {
  final origin = g.cellCenter(cells.first.x, cells.first.y);
  return [
    for (final c in cells)
      (
        (g.cellCenter(c.x, c.y).dx - origin.dx).roundToDouble(),
        (g.cellCenter(c.x, c.y).dy - origin.dy).roundToDouble(),
      ),
  ];
}

void main() {
  for (final MapEntry(key: name, value: g) in _geometries.entries) {
    group(name, () {
      final source = TileChunkStore();
      final picked = [
        const TileCoord(3, 4),
        const TileCoord(4, 4),
        const TileCoord(3, 5),
        const TileCoord(4, 6),
      ];
      for (var i = 0; i < picked.length; i++) {
        source.setCell(picked[i].x, picked[i].y, TileCell.make(0, i + 1));
      }
      final stamp = TileStamp.capture(source, picked, g, anchor: picked.first);

      test('put back where it came from, it paints exactly those cells', () {
        final placed = stamp.placeAt(picked.first, g).toList();
        expect([for (final p in placed) p.$1], picked);
        expect(
          [for (final p in placed) TileCell.localIdOf(p.$2)],
          [1, 2, 3, 4],
        );
      });

      test('put down anywhere, odd rows and columns included, it keeps its '
          'shape on screen', () {
        final shape = _shape(g, picked);
        for (final at in const [
          TileCoord(0, 0),
          TileCoord(7, 3),
          TileCoord(-2, -5),
        ]) {
          final placed = [for (final p in stamp.placeAt(at, g)) p.$1];
          expect(_shape(g, placed), shape, reason: 'at $at');
        }
      });

      test('flipped twice, or turned all the way round, it is itself', () {
        final steps = g.orientation == MapOrientation.hexagonal ? 6 : 4;
        var turned = stamp;
        for (var i = 0; i < steps; i++) {
          turned = turned.turned(g);
        }
        for (final other in [
          stamp.flippedH(g).flippedH(g),
          stamp.flippedV(g).flippedV(g),
          turned,
        ]) {
          expect(
            [for (final c in other.cells) (c.offset, c.cell)],
            [for (final c in stamp.cells) (c.offset, c.cell)],
          );
        }
      });

      test('flipped left to right, each tile is mirrored too', () {
        final flipped = stamp.flippedH(g);
        expect(flipped.cells.every((c) => TileCell.isFlippedH(c.cell)), isTrue);
      });
    });
  }

  test('a random stamp picks by weight', () {
    final a = TileCell.make(0, 1);
    final b = TileCell.make(0, 2);
    final stamp = TileStamp.random([a, b], [3, 1]);
    final random = math.Random(7);
    final picks = [for (var i = 0; i < 4000; i++) stamp.pick(random)];
    final share = picks.where((p) => p == a).length / picks.length;
    expect(share, closeTo(0.75, 0.03));
    expect(stamp.isRandom, isTrue);
  });

  test('empty cells can be kept, so a stamp can erase, or left out', () {
    final g = _geometries['orthogonal']!;
    final source = TileChunkStore()..setCell(0, 0, TileCell.make(0, 1));
    final cells = [const TileCoord(0, 0), const TileCoord(1, 0)];
    expect(TileStamp.capture(source, cells, g).cells, hasLength(2));
    expect(
      TileStamp.capture(source, cells, g, skipEmpty: true).cells,
      hasLength(1),
    );
  });
}
