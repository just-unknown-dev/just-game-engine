/// Ready-made terrain layouts: fill in a Wang set's ids in one step.
library;

import '../tileset_data.dart';

/// A standard arrangement of terrain tiles in a tileset image, and the Wang
/// ids that arrangement means.
///
/// Assigning Wang ids by hand is slow — 16 tiles × 4 corners, or 47 × 8
/// slots. A tileset drawn in one of these layouts gets every id from one
/// choice: where the block starts. Each template is a two-terrain set:
/// colour 1 is the terrain the tiles are "of" (grass), colour 2 what it
/// meets (dirt, or empty).
enum WangTemplate {
  /// Sixteen tiles in a 4 × 4 block, a corner set. Tile *n* has colour 1 at
  /// the corners whose bits are set in *n*: 1 top-left, 2 top-right, 4
  /// bottom-right, 8 bottom-left. Tile 0 is all colour 2, tile 15 all
  /// colour 1.
  corner16(WangType.corner, 16, 4),

  /// The 47 distinct "blob" tiles, a mixed set, in a 7-wide block (the last
  /// two places empty): every arrangement of the eight neighbours that
  /// looks different, in ascending order of its neighbour mask — bits
  /// 1 top, 2 top-right, 4 right, 8 bottom-right, 16 bottom, 32 bottom-left,
  /// 64 left, 128 top-left, a corner counted only when both edges beside it
  /// are set.
  blob47(WangType.mixed, 47, 7);

  const WangTemplate(this.type, this.tileCount, this.columns);

  final WangType type;

  /// How many tiles the layout has.
  final int tileCount;

  /// How wide its block is, in tiles.
  final int columns;

  /// The Wang id of the template's [index]th tile.
  List<int> idOf(int index) => switch (this) {
    WangTemplate.corner16 => _corner16(index),
    WangTemplate.blob47 => _blob(_blobMasks[index]),
  };

  static List<int> _corner16(int n) {
    int c(int bit) => n & bit != 0 ? 1 : 2;
    // Slots: top, TR, right, BR, bottom, BL, left, TL.
    return [0, c(2), 0, c(4), 0, c(8), 0, c(1)];
  }

  // The neighbour bits of a blob tile.
  static const int _n = 1,
      _ne = 2,
      _e = 4,
      _se = 8,
      _s = 16,
      _sw = 32,
      _w = 64,
      _nw = 128;

  /// The 47 masks that look different, ascending.
  static final List<int> _blobMasks = () {
    final out = <int>{};
    for (var m = 0; m < 256; m++) {
      var k = m;
      if (k & _n == 0 || k & _e == 0) k &= ~_ne;
      if (k & _e == 0 || k & _s == 0) k &= ~_se;
      if (k & _s == 0 || k & _w == 0) k &= ~_sw;
      if (k & _w == 0 || k & _n == 0) k &= ~_nw;
      out.add(k);
    }
    return out.toList()..sort();
  }();

  static List<int> _blob(int m) {
    int c(int bit) => m & bit != 0 ? 1 : 2;
    return [c(_n), c(_ne), c(_e), c(_se), c(_s), c(_sw), c(_w), c(_nw)];
  }

  /// Fills [set]'s ids from a block of this layout whose first tile is
  /// [firstTile] in a tileset [tilesetColumns] wide, and makes sure it has
  /// the two colours. Tiles that fall outside [tileCountLimit] are skipped.
  /// Returns how many tiles were assigned.
  int applyTo(
    WangSetData set, {
    required int firstTile,
    required int tilesetColumns,
    int? tileCountLimit,
  }) {
    set.type = type;
    while (set.colors.length < 2) {
      set.colors.add(
        WangColorData(
          name: set.colors.isEmpty ? 'Terrain' : 'Other',
          color: set.colors.isEmpty ? 0xFF4CAF50 : 0xFF8D6E63,
        ),
      );
    }
    final width = tilesetColumns < 1 ? 1 : tilesetColumns;
    final startCol = firstTile % width;
    final startRow = firstTile ~/ width;
    var assigned = 0;
    for (var i = 0; i < tileCount; i++) {
      final col = startCol + i % columns;
      final row = startRow + i ~/ columns;
      if (col >= tilesetColumns) continue;
      final id = row * tilesetColumns + col;
      if (tileCountLimit != null && id >= tileCountLimit) continue;
      set.wangIds[id] = idOf(i);
      assigned++;
    }
    if (set.tile < 0) {
      set.tile = firstTile + (this == WangTemplate.corner16 ? 15 : 0);
    }
    return assigned;
  }
}
