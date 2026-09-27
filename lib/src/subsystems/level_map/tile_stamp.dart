/// What a tile brush paints: one tile, a block of tiles, or a random pick.
library;

import 'dart:math' as math;

import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'map_geometry.dart';

/// One cell of a stamp: where it goes relative to the brush, and what.
class StampCell {
  const StampCell(this.offset, this.cell);

  /// In the map's stable coordinates (see [MapGeometry.toStable]),
  /// relative to the cell under the pointer.
  final TileCoord offset;

  /// The cell value; [TileCell.empty] erases.
  final int cell;
}

/// A brush's contents.
///
/// Held in the map's *stable* coordinates, so a block picked up on a
/// staggered or hexagonal map keeps its shape wherever it is put down, and
/// flipping or turning it moves the cells as well as turning each tile.
///
/// A stamp made with [TileStamp.random] paints one of its choices per
/// cell, weighted by each tile's probability — Tiled's random mode.
class TileStamp {
  TileStamp(List<StampCell> cells, {List<int>? choices, List<double>? weights})
    : cells = List.unmodifiable(cells),
      choices = List.unmodifiable(choices ?? const <int>[]),
      weights = List.unmodifiable(weights ?? const <double>[]);

  /// A stamp of one tile.
  factory TileStamp.single(int cell) =>
      TileStamp([StampCell(const TileCoord(0, 0), cell)]);

  /// A one-cell stamp that paints a random one of [choices] each time,
  /// weighted by [weights] (all equal when omitted).
  factory TileStamp.random(List<int> choices, [List<double>? weights]) =>
      TileStamp(
        [StampCell(const TileCoord(0, 0), choices.isEmpty ? 0 : choices.first)],
        choices: choices,
        weights: weights ?? [for (final _ in choices) 1.0],
      );

  /// The cells of [source] at [coords], picked up with [anchor] under the
  /// pointer (by default the middle of the block, as in Tiled). Empty cells
  /// are kept, so a stamp can erase part of what it lands on, unless
  /// [skipEmpty].
  factory TileStamp.capture(
    TileChunkStore source,
    Iterable<TileCoord> coords,
    MapGeometry geometry, {
    TileCoord? anchor,
    bool skipEmpty = false,
  }) {
    final list = coords.toList();
    if (list.isEmpty) return TileStamp(const []);
    final stable = [for (final c in list) geometry.toStable(c)];
    TileCoord origin;
    if (anchor != null) {
      origin = geometry.toStable(anchor);
    } else {
      final xs = stable.map((c) => c.x);
      final ys = stable.map((c) => c.y);
      final minX = xs.reduce(math.min);
      final minY = ys.reduce(math.min);
      final w = xs.reduce(math.max) - minX + 1;
      final h = ys.reduce(math.max) - minY + 1;
      origin = TileCoord(minX + w ~/ 2, minY + h ~/ 2);
    }
    return TileStamp([
      for (var i = 0; i < list.length; i++)
        if (!skipEmpty ||
            !TileCell.isEmpty(source.cellAt(list[i].x, list[i].y)))
          StampCell(
            TileCoord(stable[i].x - origin.x, stable[i].y - origin.y),
            source.cellAt(list[i].x, list[i].y),
          ),
    ]);
  }

  /// The cells, relative to the pointer.
  final List<StampCell> cells;

  /// For a random stamp: the tiles to pick from.
  final List<int> choices;

  /// For a random stamp: how likely each choice is.
  final List<double> weights;

  bool get isRandom => choices.length > 1;
  bool get isEmpty => cells.isEmpty;

  /// Whether it paints a single cell.
  bool get isSingle => cells.length == 1;

  /// Where each cell lands with the pointer over [at], and what it paints
  /// there. [random] resolves a random stamp; without it the first choice.
  Iterable<(TileCoord, int)> placeAt(
    TileCoord at,
    MapGeometry geometry, [
    math.Random? random,
  ]) sync* {
    final base = geometry.toStable(at);
    for (final c in cells) {
      final target = geometry.fromStable(
        TileCoord(base.x + c.offset.x, base.y + c.offset.y),
      );
      yield (target, isRandom ? pick(random) : c.cell);
    }
  }

  /// One of [choices], by [weights].
  int pick([math.Random? random]) {
    if (choices.isEmpty) return cells.isEmpty ? 0 : cells.first.cell;
    if (random == null || choices.length == 1) return choices.first;
    final total = weights.fold<double>(0, (a, b) => a + math.max(0, b));
    if (total <= 0) return choices[random.nextInt(choices.length)];
    var roll = random.nextDouble() * total;
    for (var i = 0; i < choices.length; i++) {
      roll -= math.max(0, i < weights.length ? weights[i] : 1);
      if (roll <= 0) return choices[i];
    }
    return choices.last;
  }

  TileStamp _mapped(
    TileCoord Function(TileCoord) move,
    int Function(int) turn,
  ) => TileStamp(
    [for (final c in cells) StampCell(move(c.offset), turn(c.cell))],
    choices: [for (final c in choices) turn(c)],
    weights: weights,
  );

  /// Mirrored left to right on screen: the block and each tile.
  TileStamp flippedH(MapGeometry geometry) =>
      _mapped(geometry.mirrorH, TileCell.mirroredH);

  /// Mirrored top to bottom on screen: the block and each tile.
  TileStamp flippedV(MapGeometry geometry) =>
      _mapped(geometry.mirrorV, TileCell.mirroredV);

  /// Turned one step — a quarter, or a sixth on a hexagonal map.
  TileStamp turned(MapGeometry geometry, {bool clockwise = true}) => _mapped(
    (d) => geometry.turn(d, clockwise: clockwise),
    (c) => geometry.turnCell(c, clockwise: clockwise),
  );

  /// The block's extent in stable coordinates, far edges exclusive.
  TileRange get extent {
    if (cells.isEmpty) return const TileRange(0, 0, 0, 0);
    var x0 = cells.first.offset.x, x1 = x0;
    var y0 = cells.first.offset.y, y1 = y0;
    for (final c in cells) {
      x0 = math.min(x0, c.offset.x);
      x1 = math.max(x1, c.offset.x);
      y0 = math.min(y0, c.offset.y);
      y1 = math.max(y1, c.offset.y);
    }
    return TileRange(x0, y0, x1 + 1, y1 + 1);
  }
}
