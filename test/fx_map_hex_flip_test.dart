// Mirroring a turned hexagonal tile: checked against how the engine draws a
// cell (TileCell.drawTransform) — the tile mirrored or not, then turned —
// so a flip of the stamp mirrors what is on screen, whatever the turn.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A 2×2 matrix, row by row.
typedef _M = (double, double, double, double);

_M _mul(_M a, _M b) => (
  a.$1 * b.$1 + a.$2 * b.$3,
  a.$1 * b.$2 + a.$2 * b.$4,
  a.$3 * b.$1 + a.$4 * b.$3,
  a.$3 * b.$2 + a.$4 * b.$4,
);

const _mirrorH = (-1.0, 0.0, 0.0, 1.0);
const _mirrorV = (1.0, 0.0, 0.0, -1.0);
const _identity = (1.0, 0.0, 0.0, 1.0);

/// What drawing [cell] does to its tile's image: mirror, then turn.
_M _drawn(int cell, {required bool hexagonal}) {
  final t = TileCell.drawTransform(cell, hexagonal: hexagonal);
  final c = math.cos(t.radians);
  final s = math.sin(t.radians);
  return _mul((c, -s, s, c), t.mirrored ? _mirrorH : _identity);
}

Matcher _sameAs(_M m) => predicate<_M>(
  (x) =>
      (x.$1 - m.$1).abs() < 1e-9 &&
      (x.$2 - m.$2).abs() < 1e-9 &&
      (x.$3 - m.$3).abs() < 1e-9 &&
      (x.$4 - m.$4).abs() < 1e-9,
  'the same transform as $m',
);

/// Every combination of the four flags, on tile 5 of slot 0.
final _cells = [
  for (var f = 0; f < 16; f++)
    TileCell.make(
      0,
      5,
      (f & 1 != 0 ? TileCell.flipH : 0) |
          (f & 2 != 0 ? TileCell.flipV : 0) |
          (f & 4 != 0 ? TileCell.flipD : 0) |
          (f & 8 != 0 ? TileCell.rotate120 : 0),
    ),
];

void main() {
  test('the check itself: mirroring a square tile toggles its flag, and '
      'mirrors what is drawn', () {
    for (final cell in _cells.where((c) => !TileCell.isRotated120(c))) {
      expect(
        _drawn(TileCell.mirroredH(cell), hexagonal: false),
        _sameAs(_mul(_mirrorH, _drawn(cell, hexagonal: false))),
      );
      expect(
        _drawn(TileCell.mirroredV(cell), hexagonal: false),
        _sameAs(_mul(_mirrorV, _drawn(cell, hexagonal: false))),
      );
    }
  });

  test('a hexagonal tile, however turned, mirrors left to right on '
      'screen', () {
    for (final cell in _cells) {
      final flipped = TileCell.mirroredHexH(cell);
      expect(
        _drawn(flipped, hexagonal: true),
        _sameAs(_mul(_mirrorH, _drawn(cell, hexagonal: true))),
        reason: 'flags ${TileCell.flagsOf(cell).toRadixString(16)}',
      );
      expect(TileCell.bare(flipped), TileCell.bare(cell));
      expect(TileCell.mirroredHexH(flipped), _drawnSame(cell));
    }
  });

  test('... and top to bottom', () {
    for (final cell in _cells) {
      expect(
        _drawn(TileCell.mirroredHexV(cell), hexagonal: true),
        _sameAs(_mul(_mirrorV, _drawn(cell, hexagonal: true))),
        reason: 'flags ${TileCell.flagsOf(cell).toRadixString(16)}',
      );
    }
  });

  test('a tile turned 60° mirrors to one turned 300°, not 60°', () {
    final turned = TileCell.rotatedHex(TileCell.make(0, 1));
    final flipped = TileCell.mirroredHexH(turned);
    final t = TileCell.drawTransform(flipped, hexagonal: true);
    expect(t.mirrored, isTrue);
    expect(t.radians, closeTo(300 * math.pi / 180, 1e-9));
  });

  test('a stamp on a hexagonal map flips its turned tiles right', () {
    final hex = MapGeometry(
      orientation: MapOrientation.hexagonal,
      tileWidth: 32,
      tileHeight: 28,
      hexSideLength: 14,
    );
    final turned = TileCell.rotatedHex(TileCell.make(0, 1), 2);
    final stamp = TileStamp.single(turned);
    expect(
      stamp.flippedH(hex).cells.single.cell,
      TileCell.mirroredHexH(turned),
    );
    expect(
      stamp.flippedV(hex).cells.single.cell,
      TileCell.mirroredHexV(turned),
    );
    expect(stamp.flippedH(hex).flippedH(hex).cells.single.cell, turned);
  });

  test('square maps mirror as they always did', () {
    final square = MapGeometry(tileWidth: 16, tileHeight: 16);
    for (final cell in _cells) {
      expect(square.mirrorCellH(cell), TileCell.mirroredH(cell));
      expect(square.mirrorCellV(cell), TileCell.mirroredV(cell));
    }
  });

  test('turning back a step is turning five steps on', () {
    for (final cell in _cells) {
      expect(TileCell.rotatedHex(cell, -1), TileCell.rotatedHex(cell, 5));
    }
  });
}

/// A matcher for a cell drawn exactly as [cell] is on a hexagonal map.
Matcher _drawnSame(int cell) => predicate<int>(
  (c) =>
      TileCell.bare(c) == TileCell.bare(cell) &&
      _sameAs(
        _drawn(cell, hexagonal: true),
      ).matches(_drawn(c, hexagonal: true), {}),
  'drawn as ${TileCell.flagsOf(cell).toRadixString(16)} is',
);
