/// Where a level map's cells are: the arithmetic behind all four orientations.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'tile_cell.dart';
import 'level_map_data.dart';

/// A rectangle of cells: [x0] to [x1] and [y0] to [y1], the far edges
/// exclusive.
class TileRange {
  const TileRange(this.x0, this.y0, this.x1, this.y1);

  final int x0;
  final int y0;
  final int x1;
  final int y1;

  bool get isEmpty => x1 <= x0 || y1 <= y0;
  int get width => math.max(0, x1 - x0);
  int get height => math.max(0, y1 - y0);

  bool contains(int x, int y) => x >= x0 && x < x1 && y >= y0 && y < y1;

  Iterable<TileCoord> get coords sync* {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        yield TileCoord(x, y);
      }
    }
  }

  @override
  String toString() => 'TileRange($x0, $y0 → $x1, $y1)';
}

/// The geometry of a map's grid, in map-local pixels (world units, with the
/// map's entity at the origin).
///
/// Follows Tiled's renderers exactly, so a map looks and hits the same here
/// as in Tiled:
///
/// * **Orthogonal** — cell (x, y) is the box at (x·w, y·h).
/// * **Isometric** — cell (x, y) is a diamond whose top corner is at
///   ((x − y)·w/2, (x + y)·h/2). (Tiled shifts a finite map right by
///   height·w/2 so it starts at zero; the engine's maps are unbounded and do
///   not, and an import moves the map's entity instead.)
/// * **Staggered** — diamonds in rows (or columns) where every other one is
///   shifted by half a tile.
/// * **Hexagonal** — hexagons, staggered the same way, with [hexSideLength]
///   of flat side.
///
/// A cell's *box* is the rectangle its shape sits in; a tile's image is
/// drawn with its bottom-left corner on the box's bottom-left, so a tile
/// taller than the grid rises above its cell, as in Tiled.
class MapGeometry {
  MapGeometry({
    this.orientation = MapOrientation.orthogonal,
    required int tileWidth,
    required int tileHeight,
    this.staggerAxis = TileStaggerAxis.y,
    this.staggerIndex = TileStaggerIndex.odd,
    int hexSideLength = 0,
  }) : // Tiled's hexagonal and staggered renderers work on even sizes.
       tileWidth = _isStaggered(orientation) ? tileWidth & ~1 : tileWidth,
       tileHeight = _isStaggered(orientation) ? tileHeight & ~1 : tileHeight,
       hexSideLength = orientation == MapOrientation.hexagonal
           ? hexSideLength
           : 0 {
    final sx = staggerAxis == TileStaggerAxis.x;
    _sideLengthX = sx ? this.hexSideLength : 0;
    _sideLengthY = sx ? 0 : this.hexSideLength;
    _sideOffsetX = (this.tileWidth - _sideLengthX) / 2;
    _sideOffsetY = (this.tileHeight - _sideLengthY) / 2;
    _columnWidth = _sideOffsetX + _sideLengthX;
    _rowHeight = _sideOffsetY + _sideLengthY;
  }

  /// The geometry of [map].
  factory MapGeometry.of(LevelMapData map) => MapGeometry(
    orientation: map.orientation,
    tileWidth: map.tileWidth,
    tileHeight: map.tileHeight,
    staggerAxis: map.staggerAxis,
    staggerIndex: map.staggerIndex,
    hexSideLength: map.hexSideLength,
  );

  static bool _isStaggered(MapOrientation o) =>
      o == MapOrientation.staggered || o == MapOrientation.hexagonal;

  final MapOrientation orientation;
  final int tileWidth;
  final int tileHeight;
  final TileStaggerAxis staggerAxis;
  final TileStaggerIndex staggerIndex;
  final int hexSideLength;

  late final int _sideLengthX;
  late final int _sideLengthY;
  late final double _sideOffsetX;
  late final double _sideOffsetY;
  late final double _columnWidth;
  late final double _rowHeight;

  bool get _staggerX => staggerAxis == TileStaggerAxis.x;
  int get _even => staggerIndex == TileStaggerIndex.even ? 1 : 0;

  /// Whether column [x] (stagger x) or row [y] (stagger y) is the shifted
  /// one.
  bool _staggered(int v) => ((v & 1) ^ _even) != 0;

  // ── Cells to pixels ──────────────────────────────────────────────────────

  /// The top-left of cell ([x], [y])'s box.
  Offset cellOrigin(int x, int y) {
    switch (orientation) {
      case MapOrientation.orthogonal:
        return Offset(x * tileWidth.toDouble(), y * tileHeight.toDouble());
      case MapOrientation.isometric:
        return Offset(
          (x - y) * tileWidth / 2 - tileWidth / 2,
          (x + y) * tileHeight / 2,
        );
      case MapOrientation.staggered:
      case MapOrientation.hexagonal:
        if (_staggerX) {
          return Offset(
            x * _columnWidth,
            y * (tileHeight + _sideLengthY) + (_staggered(x) ? _rowHeight : 0),
          );
        }
        return Offset(
          x * (tileWidth + _sideLengthX) + (_staggered(y) ? _columnWidth : 0),
          y * _rowHeight,
        );
    }
  }

  /// Cell ([x], [y])'s box.
  Rect cellBounds(int x, int y) =>
      cellOrigin(x, y) & Size(tileWidth.toDouble(), tileHeight.toDouble());

  /// The centre of cell ([x], [y]).
  Offset cellCenter(int x, int y) => cellBounds(x, y).center;

  /// The outline of cell ([x], [y]): a box, a diamond or a hexagon.
  List<Offset> cellPolygon(int x, int y) {
    final o = cellOrigin(x, y);
    final w = tileWidth.toDouble();
    final h = tileHeight.toDouble();
    switch (orientation) {
      case MapOrientation.orthogonal:
        return [o, o + Offset(w, 0), o + Offset(w, h), o + Offset(0, h)];
      case MapOrientation.isometric:
      case MapOrientation.staggered:
        return [
          o + Offset(w / 2, 0),
          o + Offset(w, h / 2),
          o + Offset(w / 2, h),
          o + Offset(0, h / 2),
        ];
      case MapOrientation.hexagonal:
        if (_staggerX) {
          return [
            o + Offset(_sideOffsetX, 0),
            o + Offset(_sideOffsetX + _sideLengthX, 0),
            o + Offset(w, h / 2),
            o + Offset(_sideOffsetX + _sideLengthX, h),
            o + Offset(_sideOffsetX, h),
            o + Offset(0, h / 2),
          ];
        }
        return [
          o + Offset(w / 2, 0),
          o + Offset(w, _sideOffsetY),
          o + Offset(w, _sideOffsetY + _sideLengthY),
          o + Offset(w / 2, h),
          o + Offset(0, _sideOffsetY + _sideLengthY),
          o + Offset(0, _sideOffsetY),
        ];
    }
  }

  /// Where a tile image [imageWidth] × [imageHeight] is drawn in cell
  /// ([x], [y]): bottom-left on the box's bottom-left, moved by the
  /// tileset's offset.
  Rect tileImageRect(
    int x,
    int y,
    double imageWidth,
    double imageHeight, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final box = cellBounds(x, y);
    return Rect.fromLTWH(
      box.left + offsetX,
      box.bottom - imageHeight + offsetY,
      imageWidth,
      imageHeight,
    );
  }

  // ── Pixels to cells ──────────────────────────────────────────────────────

  /// The cell [point] is in.
  TileCoord cellAt(Offset point) {
    switch (orientation) {
      case MapOrientation.orthogonal:
        return TileCoord(
          (point.dx / tileWidth).floor(),
          (point.dy / tileHeight).floor(),
        );
      case MapOrientation.isometric:
        final u = point.dx / tileWidth;
        final v = point.dy / tileHeight;
        return TileCoord((v + u).floor(), (v - u).floor());
      case MapOrientation.staggered:
        return _staggeredCellAt(point);
      case MapOrientation.hexagonal:
        // Tiled picks the nearest centre, which matches the outline only
        // for regular hexagons; a stretched one would give its corners to a
        // neighbour. The outline decides.
        final guess = _hexCellAt(point);
        if (_contains(cellPolygon(guess.x, guess.y), point)) return guess;
        for (final n in neighbours(guess)) {
          if (_contains(cellPolygon(n.x, n.y), point)) return n;
        }
        return guess;
    }
  }

  static bool _contains(List<Offset> poly, Offset p) {
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

  TileCoord _staggeredCellAt(Offset point) {
    var x = point.dx;
    var y = point.dy;
    if (_staggerX) {
      x -= _even == 1 ? _sideOffsetX : 0;
    } else {
      y -= _even == 1 ? _sideOffsetY : 0;
    }
    var rx = (x / tileWidth).floor();
    var ry = (y / tileHeight).floor();
    final relX = x - rx * tileWidth;
    final relY = y - ry * tileHeight;
    if (_staggerX) {
      rx = rx * 2 + _even;
    } else {
      ry = ry * 2 + _even;
    }
    final yPos = relX * (tileHeight / tileWidth);
    if (_sideOffsetY - yPos > relY) return _topLeft(rx, ry);
    if (-_sideOffsetY + yPos > relY) return _topRight(rx, ry);
    if (_sideOffsetY + yPos < relY) return _bottomLeft(rx, ry);
    if (_sideOffsetY * 3 - yPos < relY) return _bottomRight(rx, ry);
    return TileCoord(rx, ry);
  }

  TileCoord _hexCellAt(Offset point) {
    var x = point.dx;
    var y = point.dy;
    if (_staggerX) {
      x -= _even == 1 ? tileWidth : _sideOffsetX;
    } else {
      y -= _even == 1 ? tileHeight : _sideOffsetY;
    }
    var rx = (x / (_columnWidth * 2)).floor();
    var ry = (y / (_rowHeight * 2)).floor();
    final rel = Offset(x - rx * _columnWidth * 2, y - ry * _rowHeight * 2);
    if (_staggerX) {
      rx = rx * 2 + _even;
    } else {
      ry = ry * 2 + _even;
    }
    final List<Offset> centers;
    if (_staggerX) {
      final left = _sideLengthX / 2;
      final centerX = left + _columnWidth;
      final centerY = tileHeight / 2;
      centers = [
        Offset(left, centerY),
        Offset(centerX, centerY - _rowHeight),
        Offset(centerX, centerY + _rowHeight),
        Offset(centerX + _columnWidth, centerY),
      ];
    } else {
      final top = _sideLengthY / 2;
      final centerX = tileWidth / 2;
      final centerY = top + _rowHeight;
      centers = [
        Offset(centerX, top),
        Offset(centerX - _columnWidth, centerY),
        Offset(centerX + _columnWidth, centerY),
        Offset(centerX, centerY + _rowHeight),
      ];
    }
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final d = (centers[i] - rel).distanceSquared;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    const offsetsX = [
      TileCoord(0, 0),
      TileCoord(1, -1),
      TileCoord(1, 0),
      TileCoord(2, 0),
    ];
    const offsetsY = [
      TileCoord(0, 0),
      TileCoord(-1, 1),
      TileCoord(0, 1),
      TileCoord(0, 2),
    ];
    return TileCoord(rx, ry) + (_staggerX ? offsetsX : offsetsY)[nearest];
  }

  // ── Neighbours ───────────────────────────────────────────────────────────

  TileCoord _topLeft(int x, int y) {
    if (!_staggerX) {
      return _staggered(y) ? TileCoord(x, y - 1) : TileCoord(x - 1, y - 1);
    }
    return _staggered(x) ? TileCoord(x - 1, y) : TileCoord(x - 1, y - 1);
  }

  TileCoord _topRight(int x, int y) {
    if (!_staggerX) {
      return _staggered(y) ? TileCoord(x + 1, y - 1) : TileCoord(x, y - 1);
    }
    return _staggered(x) ? TileCoord(x + 1, y) : TileCoord(x + 1, y - 1);
  }

  TileCoord _bottomLeft(int x, int y) {
    if (!_staggerX) {
      return _staggered(y) ? TileCoord(x, y + 1) : TileCoord(x - 1, y + 1);
    }
    return _staggered(x) ? TileCoord(x - 1, y + 1) : TileCoord(x - 1, y);
  }

  TileCoord _bottomRight(int x, int y) {
    if (!_staggerX) {
      return _staggered(y) ? TileCoord(x + 1, y + 1) : TileCoord(x, y + 1);
    }
    return _staggered(x) ? TileCoord(x + 1, y + 1) : TileCoord(x + 1, y);
  }

  /// The cells sharing an edge with [c]: four, or six on a hexagonal map.
  List<TileCoord> neighbours(TileCoord c) {
    final x = c.x;
    final y = c.y;
    switch (orientation) {
      case MapOrientation.orthogonal:
      case MapOrientation.isometric:
        return [
          TileCoord(x, y - 1),
          TileCoord(x + 1, y),
          TileCoord(x, y + 1),
          TileCoord(x - 1, y),
        ];
      case MapOrientation.staggered:
        return [
          _topRight(x, y),
          _bottomRight(x, y),
          _bottomLeft(x, y),
          _topLeft(x, y),
        ];
      case MapOrientation.hexagonal:
        return _staggerX
            ? [
                TileCoord(x, y - 1),
                _topRight(x, y),
                _bottomRight(x, y),
                TileCoord(x, y + 1),
                _bottomLeft(x, y),
                _topLeft(x, y),
              ]
            : [
                _topRight(x, y),
                TileCoord(x + 1, y),
                _bottomRight(x, y),
                _bottomLeft(x, y),
                TileCoord(x - 1, y),
                _topLeft(x, y),
              ];
    }
  }

  // ── Areas ────────────────────────────────────────────────────────────────

  /// Every cell whose box might touch [area]: generous at the edges, never
  /// short. What culling and area tools start from.
  TileRange cellRange(Rect area) {
    switch (orientation) {
      case MapOrientation.orthogonal:
        return TileRange(
          (area.left / tileWidth).floor(),
          (area.top / tileHeight).floor(),
          (area.right / tileWidth).ceil(),
          (area.bottom / tileHeight).ceil(),
        );
      case MapOrientation.isometric:
        final corners = [
          cellAt(area.topLeft),
          cellAt(area.topRight),
          cellAt(area.bottomLeft),
          cellAt(area.bottomRight),
        ];
        return TileRange(
          corners.map((c) => c.x).reduce(math.min) - 1,
          corners.map((c) => c.y).reduce(math.min) - 1,
          corners.map((c) => c.x).reduce(math.max) + 2,
          corners.map((c) => c.y).reduce(math.max) + 2,
        );
      case MapOrientation.staggered:
      case MapOrientation.hexagonal:
        final stepX = _staggerX ? _columnWidth : tileWidth + _sideLengthX;
        final stepY = _staggerX ? tileHeight + _sideLengthY : _rowHeight;
        return TileRange(
          (area.left / stepX).floor() - 1,
          (area.top / stepY).floor() - 1,
          (area.right / stepX).ceil() + 1,
          (area.bottom / stepY).ceil() + 1,
        );
    }
  }

  /// The cells whose centre lies in [area] — what a rectangle drawn over
  /// the map selects, whatever shape its cells are.
  Iterable<TileCoord> cellsIn(Rect area) sync* {
    final range = cellRange(area);
    for (final c in range.coords) {
      if (area.contains(cellCenter(c.x, c.y))) yield c;
    }
  }

  /// The box around [range]'s cells, in pixels.
  Rect boundsOf(TileRange range) {
    if (range.isEmpty) return Rect.zero;
    var rect = cellBounds(range.x0, range.y0);
    for (final c in [
      TileCoord(range.x1 - 1, range.y0),
      TileCoord(range.x0, range.y1 - 1),
      TileCoord(range.x1 - 1, range.y1 - 1),
    ]) {
      rect = rect.expandToInclude(cellBounds(c.x, c.y));
    }
    return rect;
  }

  /// Orders cells back to front, the way they must be drawn so that taller
  /// tiles overlap the ones behind them: by the centre's height on screen,
  /// then left to right.
  int compareDrawOrder(TileCoord a, TileCoord b) {
    final ca = cellCenter(a.x, a.y);
    final cb = cellCenter(b.x, b.y);
    final byY = ca.dy.compareTo(cb.dy);
    return byY != 0 ? byY : ca.dx.compareTo(cb.dx);
  }

  // ── The square lattice beneath ──────────────────────────────────────────
  //
  // Orthogonal and isometric cells are addressed on a square lattice: a
  // cell's four edge neighbours are one step along x or y. A staggered map
  // is the same diamonds as an isometric one, only numbered to make a
  // rectangle — so it too has a lattice, and anything that reasons about
  // corners and edges (a terrain brush) or turns a block of cells (a stamp)
  // works on the lattice and maps back. Hexagons have none.

  /// Whether cells map onto a square lattice.
  bool get hasLattice => orientation != MapOrientation.hexagonal;

  /// [c] on the lattice.
  TileCoord toLattice(TileCoord c) {
    if (orientation != MapOrientation.staggered) return c;
    final x = c.x;
    final y = c.y;
    if (!_staggerX) {
      final p = y & 1;
      return _even == 0
          ? TileCoord(x + (y + p) ~/ 2, (y - p) ~/ 2 - x)
          : TileCoord(x + (y - p) ~/ 2, (y + p) ~/ 2 - x);
    }
    final p = x & 1;
    return _even == 0
        ? TileCoord(y + (x + p) ~/ 2, y - (x - p) ~/ 2)
        : TileCoord(y + (x - p) ~/ 2, y - (x + p) ~/ 2);
  }

  // ── Stable coordinates ─────────────────────────────────────────────────
  //
  // Moving a block of cells on a staggered or hexagonal map by an odd
  // number of rows changes which rows are shifted, so the same offsets land
  // on a different shape. In "stable" coordinates a block keeps its shape
  // wherever it goes: the map's own for orthogonal and isometric, the
  // diamond lattice for staggered, axial hex coordinates for hexagonal. A
  // stamp is held in them, and flips and turns are worked out in them.

  /// [c] in axial hex coordinates (hexagonal maps).
  TileCoord toAxial(TileCoord c) {
    final x = c.x;
    final y = c.y;
    if (!_staggerX) {
      final p = y & 1;
      return TileCoord(_even == 0 ? x - (y - p) ~/ 2 : x - (y + p) ~/ 2, y);
    }
    final p = x & 1;
    return TileCoord(x, _even == 0 ? y - (x - p) ~/ 2 : y - (x + p) ~/ 2);
  }

  /// The cell at axial coordinates [a] (hexagonal maps).
  TileCoord fromAxial(TileCoord a) {
    final q = a.x;
    final r = a.y;
    if (!_staggerX) {
      final p = r & 1;
      return TileCoord(_even == 0 ? q + (r - p) ~/ 2 : q + (r + p) ~/ 2, r);
    }
    final p = q & 1;
    return TileCoord(q, _even == 0 ? r + (q - p) ~/ 2 : r + (q + p) ~/ 2);
  }

  /// [c] in coordinates where a block of cells keeps its shape.
  TileCoord toStable(TileCoord c) => switch (orientation) {
    MapOrientation.hexagonal => toAxial(c),
    MapOrientation.staggered => toLattice(c),
    _ => c,
  };

  /// The cell at stable coordinates [s].
  TileCoord fromStable(TileCoord s) => switch (orientation) {
    MapOrientation.hexagonal => fromAxial(s),
    MapOrientation.staggered => fromLattice(s),
    _ => s,
  };

  /// A stable offset [d] mirrored left to right on screen.
  TileCoord mirrorH(TileCoord d) => switch (orientation) {
    MapOrientation.orthogonal => TileCoord(-d.x, d.y),
    MapOrientation.isometric || MapOrientation.staggered => TileCoord(d.y, d.x),
    MapOrientation.hexagonal =>
      _staggerX ? TileCoord(-d.x, d.y + d.x) : TileCoord(-d.x - d.y, d.y),
  };

  /// A stable offset [d] mirrored top to bottom on screen.
  TileCoord mirrorV(TileCoord d) => switch (orientation) {
    MapOrientation.orthogonal => TileCoord(d.x, -d.y),
    MapOrientation.isometric ||
    MapOrientation.staggered => TileCoord(-d.y, -d.x),
    MapOrientation.hexagonal =>
      _staggerX ? TileCoord(d.x, -d.y - d.x) : TileCoord(d.x + d.y, -d.y),
  };

  /// A stable offset [d] turned one step on screen: a quarter turn, or a
  /// sixth on a hexagonal map.
  TileCoord turn(TileCoord d, {bool clockwise = true}) {
    if (orientation == MapOrientation.hexagonal) {
      // Cube coordinates (q, r, s = −q − r): a sixth of a turn right is
      // (−r, −s, −q), left is (−s, −q, −r).
      final q = d.x;
      final r = d.y;
      return clockwise ? TileCoord(-r, q + r) : TileCoord(q + r, -q);
    }
    return clockwise ? TileCoord(-d.y, d.x) : TileCoord(d.y, -d.x);
  }

  /// [cell]'s tile turned one step the same way as [turn].
  int turnCell(int cell, {bool clockwise = true}) =>
      orientation == MapOrientation.hexagonal
      ? TileCell.rotatedHex(cell, clockwise ? 1 : -1)
      : clockwise
      ? TileCell.rotatedRight(cell)
      : TileCell.rotatedLeft(cell);

  /// The cell at lattice point [l].
  TileCoord fromLattice(TileCoord l) {
    if (orientation != MapOrientation.staggered) return l;
    final u = l.x;
    final v = l.y;
    if (!_staggerX) {
      final y = u + v;
      final p = y & 1;
      return TileCoord(_even == 0 ? u - (y + p) ~/ 2 : u - (y - p) ~/ 2, y);
    }
    final x = u - v;
    final p = x & 1;
    return TileCoord(x, _even == 0 ? u - (x + p) ~/ 2 : u - (x - p) ~/ 2);
  }
}
