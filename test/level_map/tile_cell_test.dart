// A cell packs a tileset slot, a tile id and Tiled's four transform flags
// into 32 unsigned bits.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('slot, tile and flags come back out as they went in', () {
    final cell = TileCell.make(3, 1234, TileCell.flipH | TileCell.flipD);
    expect(TileCell.slotOf(cell), 3);
    expect(TileCell.localIdOf(cell), 1234);
    expect(TileCell.isFlippedH(cell), isTrue);
    expect(TileCell.isFlippedV(cell), isFalse);
    expect(TileCell.isFlippedD(cell), isTrue);
    expect(TileCell.isEmpty(cell), isFalse);
    expect(cell, greaterThan(0), reason: 'unsigned, even with bit 31 set');
  });

  test('slot 0, tile 0 is a tile, not an empty cell', () {
    final cell = TileCell.make(0, 0);
    expect(TileCell.isEmpty(cell), isFalse);
    expect(TileCell.slotOf(cell), 0);
    expect(TileCell.isEmpty(TileCell.empty), isTrue);
    expect(TileCell.slotOf(TileCell.empty), -1);
  });

  test('flags can be replaced and stripped without touching the tile', () {
    final cell = TileCell.make(1, 7, TileCell.flipV);
    final turned = TileCell.withFlags(
      cell,
      TileCell.flipH | TileCell.rotate120,
    );
    expect(TileCell.bare(turned), TileCell.bare(cell));
    expect(TileCell.isFlippedV(turned), isFalse);
    expect(TileCell.isRotated120(turned), isTrue);
  });

  group('turning a square tile', () {
    final all = [
      for (var mask = 0; mask < 8; mask++)
        TileCell.make(
          0,
          5,
          (mask & 4 != 0 ? TileCell.flipH : 0) |
              (mask & 2 != 0 ? TileCell.flipV : 0) |
              (mask & 1 != 0 ? TileCell.flipD : 0),
        ),
    ];

    test('four quarter turns come back round', () {
      for (final cell in all) {
        var c = cell;
        for (var i = 0; i < 4; i++) {
          c = TileCell.rotatedRight(c);
        }
        expect(c, cell);
      }
    });

    test('right then left undoes it, and so does left then right', () {
      for (final cell in all) {
        expect(TileCell.rotatedLeft(TileCell.rotatedRight(cell)), cell);
        expect(TileCell.rotatedRight(TileCell.rotatedLeft(cell)), cell);
      }
    });

    test('a quarter turn of an unturned tile is diagonal plus horizontal, as '
        'in Tiled', () {
      final turned = TileCell.rotatedRight(TileCell.make(0, 1));
      expect(TileCell.isFlippedD(turned), isTrue);
      expect(TileCell.isFlippedH(turned), isTrue);
      expect(TileCell.isFlippedV(turned), isFalse);
    });

    test('two quarter turns are both mirrors', () {
      final half = TileCell.rotatedRight(
        TileCell.rotatedRight(TileCell.make(0, 1)),
      );
      expect(TileCell.flagsOf(half), TileCell.flipH | TileCell.flipV);
    });

    test('mirroring twice is nothing', () {
      for (final cell in all) {
        expect(TileCell.mirroredH(TileCell.mirroredH(cell)), cell);
        expect(TileCell.mirroredV(TileCell.mirroredV(cell)), cell);
      }
    });

    test('an empty cell stays empty', () {
      expect(TileCell.rotatedRight(TileCell.empty), TileCell.empty);
      expect(TileCell.mirroredH(TileCell.empty), TileCell.empty);
    });
  });

  test('six sixths of a turn bring a hexagonal tile back round', () {
    final cell = TileCell.make(0, 2, TileCell.flipH);
    var c = cell;
    final seen = <int>{};
    for (var i = 0; i < 6; i++) {
      c = TileCell.rotatedHex(c);
      seen.add(TileCell.flagsOf(c));
    }
    expect(c, cell);
    expect(seen, hasLength(6), reason: 'every step is a different turn');
    expect(TileCell.rotatedHex(TileCell.rotatedHex(cell), -1), cell);
    expect(TileCell.rotatedHex(cell, -1), TileCell.rotatedHex(cell, 5));
  });
}
