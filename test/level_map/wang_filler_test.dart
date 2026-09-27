// Terrain painting: tiles chosen so terrains meet cleanly, as Tiled's
// terrain brush chooses them.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A tileset laid out as the 16-tile corner template: tile n has grass
/// (colour 1) at the corners whose bits are set.
TilesetData _cornerTileset() {
  final ts = TilesetData(name: 't', image: 't.png', columns: 4, tileCount: 16);
  final set = WangSetData(name: 'Grass');
  WangTemplate.corner16.applyTo(set, firstTile: 0, tilesetColumns: 4);
  ts.wangSets.add(set);
  return ts;
}

/// The corners (TL, TR, BR, BL) the tile in [cell] shows.
List<int> _corners(WangFiller f, int cell) {
  final id = f.wangIdOf(cell)!;
  return [id[7], id[1], id[3], id[5]];
}

void main() {
  test('the templates have the tiles they say', () {
    expect(WangTemplate.corner16.idOf(0), [0, 2, 0, 2, 0, 2, 0, 2]);
    expect(WangTemplate.corner16.idOf(15), [0, 1, 0, 1, 0, 1, 0, 1]);
    expect(WangTemplate.corner16.idOf(1), [
      0,
      2,
      0,
      2,
      0,
      2,
      0,
      1,
    ], reason: 'top-left');
    final blobs = {
      for (var i = 0; i < 47; i++) WangTemplate.blob47.idOf(i).join(),
    };
    expect(blobs, hasLength(47), reason: 'all different');
  });

  group('a corner set on an orthogonal map', () {
    final g = MapGeometry(tileWidth: 16, tileHeight: 16);
    final ts = _cornerTileset();
    WangFiller filler() => WangFiller(
      set: ts.wangSets.single,
      tileset: ts,
      slot: 0,
      geometry: g,
      random: math.Random(1),
    );

    TileChunkStore dirt() {
      final layer = TileChunkStore();
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 6; x++) {
          layer.setCell(x, y, TileCell.make(0, 0));
        }
      }
      return layer;
    }

    test('painting one corner changes the four cells around it', () {
      final f = filler();
      final result = f.paint(dirt(), [
        const WangTarget.corner(TileCoord(3, 3)),
      ], 1);
      expect(result.changes.keys.toSet(), {
        const TileCoord(2, 2),
        const TileCoord(3, 2),
        const TileCoord(2, 3),
        const TileCoord(3, 3),
      });
      expect(_corners(f, result.changes[const TileCoord(2, 2)]!), [2, 2, 1, 2]);
      expect(_corners(f, result.changes[const TileCoord(3, 3)]!), [1, 2, 2, 2]);
      expect(result.unmatched, isEmpty);
    });

    test('a painted patch joins up, and its middle is all grass', () {
      final f = filler();
      final layer = dirt();
      for (final t in [
        for (var y = 2; y <= 4; y++)
          for (var x = 2; x <= 4; x++) WangTarget.corner(TileCoord(x, y)),
      ]) {
        final r = f.paint(layer, [t], 1);
        r.changes.forEach((c, v) => layer.setCell(c.x, c.y, v));
      }
      expect(
        TileCell.localIdOf(layer.cellAt(2, 2)),
        15,
        reason: 'all corners grass',
      );
      expect(TileCell.localIdOf(layer.cellAt(3, 3)), 15);
      // Every shared corner agrees between its four cells.
      for (var y = 1; y <= 5; y++) {
        for (var x = 1; x <= 5; x++) {
          final around = [
            _corners(f, layer.cellAt(x - 1, y - 1))[2],
            _corners(f, layer.cellAt(x, y - 1))[3],
            _corners(f, layer.cellAt(x - 1, y))[1],
            _corners(f, layer.cellAt(x, y))[0],
          ];
          expect(around.toSet(), hasLength(1), reason: 'corner ($x, $y)');
        }
      }
    });

    test('the brush takes the corner nearest the pointer', () {
      final t = WangFiller.targetAt(g, const Offset(30, 3), WangType.corner);
      expect(t, const WangTarget.corner(TileCoord(2, 0)));
    });

    test('a set that lacks a combination says so, and still paints', () {
      final sparse = _cornerTileset()..wangSets.single.wangIds.remove(4);
      final f = WangFiller(
        set: sparse.wangSets.single,
        tileset: sparse,
        slot: 0,
        geometry: g,
        random: math.Random(1),
      );
      final r = f.paint(dirt(), [const WangTarget.corner(TileCoord(3, 3))], 1);
      expect(
        r.unmatched,
        contains(const TileCoord(2, 2)),
        reason: 'needs tile 4',
      );
      expect(r.changes, contains(const TileCoord(2, 2)));
    });
  });

  test('a turnable set makes do with one corner tile', () {
    final g = MapGeometry(tileWidth: 16, tileHeight: 16);
    final ts = TilesetData(
      name: 't',
      image: 't.png',
      columns: 4,
      tileCount: 4,
      transformations: const TileTransformations(rotate: true),
    );
    // Only "grass at the top-left corner", and plain dirt.
    ts.wangSets.add(
      WangSetData(
        colors: [WangColorData(), WangColorData()],
        wangIds: {
          0: [0, 2, 0, 2, 0, 2, 0, 2],
          1: [0, 2, 0, 2, 0, 2, 0, 1],
        },
      ),
    );
    final f = WangFiller(
      set: ts.wangSets.single,
      tileset: ts,
      slot: 0,
      geometry: g,
    );
    final layer = TileChunkStore()..setCell(0, 0, TileCell.make(0, 0));
    final r = f.paint(layer, [const WangTarget.corner(TileCoord(1, 1))], 1);
    expect(r.unmatched, isEmpty, reason: 'turned copies fill the gaps');
    final bottomRight = r.changes[const TileCoord(1, 1)]!;
    expect(TileCell.localIdOf(bottomRight), 1);
    expect(_corners(f, bottomRight), [1, 2, 2, 2]);
    final topLeft = r.changes[const TileCoord(0, 0)]!;
    expect(_corners(f, topLeft), [2, 2, 1, 2]);
  });

  test('an edge set paints edges', () {
    final g = MapGeometry(tileWidth: 16, tileHeight: 16);
    final ts = TilesetData(
      name: 'r',
      image: 'r.png',
      columns: 4,
      tileCount: 16,
    );
    final set = WangSetData(type: WangType.edge, colors: [WangColorData()]);
    for (var n = 0; n < 16; n++) {
      int c(int bit) => n & bit != 0 ? 1 : 0;
      set.wangIds[n] = [c(1), 0, c(2), 0, c(4), 0, c(8), 0];
    }
    ts.wangSets.add(set);
    final f = WangFiller(set: set, tileset: ts, slot: 0, geometry: g);
    final r = f.paint(TileChunkStore(), [
      const WangTarget.edge(TileCoord(2, 2), horizontal: false),
    ], 1);
    // The edge between (1, 2) and (2, 2): the right of one, the left of the
    // other.
    expect(TileCell.localIdOf(r.changes[const TileCoord(1, 2)]!), 2);
    expect(TileCell.localIdOf(r.changes[const TileCoord(2, 2)]!), 8);
  });

  for (final orientation in [
    MapOrientation.isometric,
    MapOrientation.staggered,
  ]) {
    test('terrain paints on the lattice of a ${orientation.name} map', () {
      final g = MapGeometry(
        orientation: orientation,
        tileWidth: 64,
        tileHeight: 32,
      );
      final ts = _cornerTileset();
      final f = WangFiller(
        set: ts.wangSets.single,
        tileset: ts,
        slot: 0,
        geometry: g,
      );
      final r = f.paint(TileChunkStore(), [
        const WangTarget.corner(TileCoord(0, 0)),
      ], 1);
      expect(r.changes, hasLength(4));
      // The four cells meet at one point on screen.
      final meeting = <Offset>{
        for (final c in r.changes.keys)
          for (final p in g.cellPolygon(c.x, c.y)) p,
      };
      final shared = meeting.where(
        (p) => r.changes.keys.every((c) => g.cellPolygon(c.x, c.y).contains(p)),
      );
      expect(shared, hasLength(1));
    });
  }

  test('hexagonal maps have no terrain brush', () {
    final g = MapGeometry(
      orientation: MapOrientation.hexagonal,
      tileWidth: 28,
      tileHeight: 24,
      hexSideLength: 12,
    );
    final ts = _cornerTileset();
    expect(
      () => WangFiller(
        set: ts.wangSets.single,
        tileset: ts,
        slot: 0,
        geometry: g,
      ),
      throwsUnsupportedError,
    );
  });
}
