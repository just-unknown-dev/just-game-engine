/// One cell of a tile layer, packed into 32 bits.
library;

/// A cell's position on a map layer, in tiles.
///
/// What "x" and "y" mean depends on the map's orientation: columns and rows
/// on an orthogonal map, the two diamond axes on an isometric one, and
/// Tiled's staggered column/row on a staggered or hexagonal one. See
/// `MapGeometry`.
class TileCoord {
  const TileCoord(this.x, this.y);

  final int x;
  final int y;

  TileCoord operator +(TileCoord other) => TileCoord(x + other.x, y + other.y);

  @override
  bool operator ==(Object other) =>
      other is TileCoord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// The value of one cell: which tile of which tileset, and how it is turned.
///
/// ```
/// bit 31  30  29  28 | 27 ........ 20 | 19 .............. 0
///     H   V   D   R  | tileset slot+1 | tile id in the tileset
/// ```
///
/// The four flags are exactly Tiled's (mirrored horizontally, vertically,
/// across the diagonal, and turned 120° on a hexagonal map), so a cell's
/// flags carry across to a TMX file unchanged. The tile is named by the
/// map's tileset *slot* and the tile's id within that tileset rather than by
/// Tiled's global id: global ids number the tilesets one after another, so a
/// tileset that gains a row of tiles would renumber every tileset after it.
/// Global ids are worked out only when a map is exported.
///
/// Zero is an empty cell — which is why the slot is stored plus one.
///
/// Cells are unsigned 32-bit values. Keep them in a `Uint32List`, test the
/// flags with masks, and never compare a cell's sign: on the web every int
/// is a double and a set top bit must not read as negative.
abstract final class TileCell {
  /// No tile.
  static const int empty = 0;

  /// Mirrored left to right.
  static const int flipH = 0x80000000;

  /// Mirrored top to bottom.
  static const int flipV = 0x40000000;

  /// Mirrored across the top-left to bottom-right diagonal.
  static const int flipD = 0x20000000;

  /// Hexagonal maps: turned 120° clockwise.
  static const int rotate120 = 0x10000000;

  /// Every flag bit.
  static const int flagMask = 0xF0000000;

  /// Everything but the flags: which tile.
  static const int tileMask = 0x0FFFFFFF;

  static const int _slotShift = 20;
  static const int _slotBits = 0xFF;
  static const int _localMask = 0xFFFFF;

  /// How many tilesets a map can use.
  static const int maxTilesets = 255;

  /// The largest tile id a tileset can have.
  static const int maxLocalId = _localMask;

  /// Tile [localId] of the tileset in [slot], turned by [flags].
  static int make(int slot, int localId, [int flags = 0]) {
    assert(slot >= 0 && slot < maxTilesets, 'tileset slot $slot');
    assert(localId >= 0 && localId <= maxLocalId, 'tile id $localId');
    return ((((slot + 1) & _slotBits) << _slotShift) |
            (localId & _localMask) |
            (flags & flagMask))
        .toUnsigned(32);
  }

  /// Whether [cell] holds no tile.
  static bool isEmpty(int cell) => (cell & tileMask) == 0;

  /// The tileset slot [cell] draws from; -1 when empty.
  static int slotOf(int cell) => ((cell >>> _slotShift) & _slotBits) - 1;

  /// The tile's id within its tileset.
  static int localIdOf(int cell) => cell & _localMask;

  /// The flag bits of [cell].
  static int flagsOf(int cell) => cell & flagMask;

  /// [cell] with its flags replaced by [flags].
  static int withFlags(int cell, int flags) =>
      ((cell & tileMask) | (flags & flagMask)).toUnsigned(32);

  /// [cell] without any flags: the same tile, unturned.
  static int bare(int cell) => cell & tileMask;

  static bool isFlippedH(int cell) => (cell & flipH) != 0;
  static bool isFlippedV(int cell) => (cell & flipV) != 0;
  static bool isFlippedD(int cell) => (cell & flipD) != 0;
  static bool isRotated120(int cell) => (cell & rotate120) != 0;

  // Rotating a square tile by a quarter turn, as a mapping of its three
  // mirror flags. Index = H<<2 | V<<1 | D. Tiled draws a tile by mirroring
  // across the diagonal first, then horizontally, then vertically, and these
  // are the results of following that with a quarter turn — Tiled's own
  // tables.
  static const List<int> _quarterRight = [5, 4, 1, 0, 7, 6, 3, 2];
  static const List<int> _quarterLeft = [3, 2, 7, 6, 1, 0, 5, 4];

  static int _mask(int cell) =>
      (isFlippedH(cell) ? 4 : 0) |
      (isFlippedV(cell) ? 2 : 0) |
      (isFlippedD(cell) ? 1 : 0);

  static int _fromMask(int cell, int mask) => withFlags(
    cell,
    (mask & 4 != 0 ? flipH : 0) |
        (mask & 2 != 0 ? flipV : 0) |
        (mask & 1 != 0 ? flipD : 0) |
        (cell & rotate120),
  );

  /// [cell] turned a quarter clockwise (square and diamond tiles).
  static int rotatedRight(int cell) =>
      isEmpty(cell) ? cell : _fromMask(cell, _quarterRight[_mask(cell)]);

  /// [cell] turned a quarter anticlockwise (square and diamond tiles).
  static int rotatedLeft(int cell) =>
      isEmpty(cell) ? cell : _fromMask(cell, _quarterLeft[_mask(cell)]);

  /// [cell] mirrored left to right, however it is already turned: Tiled
  /// applies the horizontal mirror after the diagonal one, so toggling it
  /// mirrors what is on screen.
  static int mirroredH(int cell) =>
      isEmpty(cell) ? cell : (cell ^ flipH).toUnsigned(32);

  /// [cell] mirrored top to bottom, however it is already turned.
  static int mirroredV(int cell) =>
      isEmpty(cell) ? cell : (cell ^ flipV).toUnsigned(32);

  // Each of a square tile's eight turns as "mirror left to right or not,
  // then this many quarter turns clockwise". Index = H<<2 | V<<1 | D.
  static const List<(int, bool)> _squareDraw = [
    (0, false), // none
    (3, true), // D
    (2, true), // V
    (3, false), // V D
    (0, true), // H
    (1, false), // H D
    (2, false), // H V
    (1, true), // H V D
  ];

  /// How to draw [cell]'s tile: mirror it left to right when [mirrored],
  /// then turn it clockwise by [radians] about its centre. [sideways] says
  /// the turned tile is as wide as it was tall (square tiles on their side).
  ///
  /// Tiled's three mirror flags make eight ways a square tile can face;
  /// each is exactly one mirror (or none) and a number of quarter turns. A
  /// hexagonal tile mirrors, then turns by its 60° and 120° flags.
  static ({bool mirrored, double radians, bool sideways}) drawTransform(
    int cell, {
    bool hexagonal = false,
  }) {
    final h = isFlippedH(cell);
    final v = isFlippedV(cell);
    final d = isFlippedD(cell);
    if (hexagonal) {
      // Mirrored vertically is mirrored horizontally and turned half round.
      final degrees =
          (d ? 60 : 0) + (isRotated120(cell) ? 120 : 0) + (v ? 180 : 0);
      return (mirrored: h != v, radians: degrees * _pi / 180, sideways: false);
    }
    final (turns, mirrored) =
        _squareDraw[(h ? 4 : 0) | (v ? 2 : 0) | (d ? 1 : 0)];
    return (
      mirrored: mirrored,
      radians: turns * _pi / 2,
      sideways: turns.isOdd,
    );
  }

  static const double _pi = 3.141592653589793;

  /// [cell] on a hexagonal map, turned 60° clockwise ([steps] times).
  ///
  /// A hexagonal tile's turn is the diagonal flag (60°) plus the 120° flag;
  /// 180° is mirrored both ways. The turn is kept in that form: 0°, 60° or
  /// 120° plus, when past 180°, both mirrors.
  static int rotatedHex(int cell, [int steps = 1]) {
    if (isEmpty(cell)) return cell;
    var turn = (isFlippedD(cell) ? 1 : 0) + (isRotated120(cell) ? 2 : 0);
    var flags = flagsOf(cell) & (flipH | flipV);
    turn += steps % 6;
    while (turn >= 3) {
      turn -= 3;
      flags ^= flipH | flipV;
    }
    if (turn < 0) turn += 3;
    return withFlags(
      cell,
      flags | (turn & 1 != 0 ? flipD : 0) | (turn & 2 != 0 ? rotate120 : 0),
    );
  }
}
