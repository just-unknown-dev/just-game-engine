/// Turning a layer's tiles into the static bodies that collide like them.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../tile_cell.dart';
import '../tile_chunks.dart';
import '../level_map_data.dart';
import '../map_geometry.dart';
import '../tileset_data.dart';
import 'polygon_decompose.dart';
import 'map_collision_kinds.dart';

/// One static body a layer's collision is made of, from its tiles.
class MapBodySpec {
  /// A body of collision [kind] at [center]: a box of [size], or the
  /// convex [polygon]. Exactly one of the two must be given; neither or
  /// both throws an [ArgumentError].
  MapBodySpec({
    required this.kind,
    required this.center,
    this.size,
    this.polygon,
    this.className = '',
    this.cells = const [],
  }) {
    if ((size == null) == (polygon == null)) {
      throw ArgumentError(
        'A map body is a box (size) or a polygon (polygon): give exactly one',
      );
    }
  }

  /// Its collision kind's id.
  final String kind;

  /// Where the body sits, map-local (add the map's position for the world).
  final Offset center;

  /// A box this big, centred on [center] — or null for a [polygon].
  final Size? size;

  /// A convex polygon of at most eight points, relative to [center].
  final List<Offset>? polygon;

  /// The class of the tiles it was built from.
  final String className;

  /// The cells it covers.
  final List<TileCoord> cells;

  /// Whether it is a box ([size]) rather than a [polygon].
  bool get isBox => size != null;

  /// The body's extent, map-local.
  Rect get bounds {
    final s = size;
    if (s != null) {
      return Rect.fromCenter(center: center, width: s.width, height: s.height);
    }
    final pts = polygon!;
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.shift(center);
  }
}

/// One upright box of collision, before merging, and the cell it is from.
class _Box {
  const _Box(this.rect, this.cell);
  final Rect rect;
  final TileCoord cell;
}

/// Builds a layer's collision from what its tiles' tilesets say.
///
/// Each tile's collision shapes are in its image's pixels, placed where the
/// image is drawn and turned with the tile. Tiles that fill their whole
/// cell on an orthogonal map — nearly all of a platformer's ground — are
/// merged with their neighbours of the same kind and class into as few
/// boxes as the kind allows: fewer bodies, and no seam every tile for a
/// running character to catch on. Everything else becomes convex polygons.
///
/// Ramps are joined the same way. On an orthogonal map, for a kind merged
/// by [TileMergeMode.area], a run of floor slopes — tiles filled below one
/// sloping line from the cell's left side to its right, such as 45° and
/// 22.5° ramps — becomes one convex polygon together with the whole cells
/// beneath it (down to the lowest slope's cell) and the level ground or
/// the slope down beyond its crest: no seam between its tiles, and no
/// buried corner flush with its surface, at its foot or at its crest, for a
/// sliding corner to catch on. A run ends where the ground turns up again
/// (the next rise's foot, a wall), where it is not solid down to the
/// polygon's bottom, and where the polygon would pass eight points.
abstract final class TileCollisionBuilder {
  /// The bodies for [cells], drawn on [geometry] with tilesets looked up by
  /// slot through [tilesetAt], the layer moved by [offset]. How each kind
  /// merges comes from [kinds] — the engine's own when null.
  static List<MapBodySpec> build({
    required TileChunkStore cells,
    required MapGeometry geometry,
    required TilesetData? Function(int slot) tilesetAt,
    Offset offset = Offset.zero,
    MapCollisionKinds? kinds,
  }) {
    final known = kinds ?? MapCollisionKinds.builtIn;
    final specs = <MapBodySpec>[];
    // Boxes waiting to be merged, by kind and class: whole cells, and every
    // shape that lands as an upright rectangle — a half-tile ledge, a
    // quarter of terrain.
    final boxes = <(String, String), List<_Box>>{};
    // What runs of floor slopes may join, by kind and class.
    final runs = <(String, String), _RunCells>{};
    final orthogonal = geometry.orientation == LevelMapOrientation.orthogonal;

    for (final (x, y, cell) in cells.cells) {
      final tileset = tilesetAt(TileCell.slotOf(cell));
      if (tileset == null) continue;
      final def = tileset.tile(TileCell.localIdOf(cell));
      final collision = def?.collision;
      if (collision == null || collision.shapes.isEmpty) continue;
      final className = def!.className;
      final at = TileCoord(x, y);

      final hexagonal = geometry.orientation == LevelMapOrientation.hexagonal;
      final tw = tileset.tileWidth.toDouble();
      final th = tileset.tileHeight.toDouble();
      // Mirrored across its diagonal, a square tile's image turns on its
      // side: drawn th wide and tw tall.
      final transposed = TileCell.isFlippedD(cell) && !hexagonal;
      final image = geometry.tileImageRect(
        x,
        y,
        transposed ? th : tw,
        transposed ? tw : th,
        offsetX: tileset.tileOffsetX,
        offsetY: tileset.tileOffsetY,
      );
      final place = placement(cell, tw, th, hexagonal: hexagonal);
      final group = (collision.kind, className);
      // A cell a run of slopes may take: one shape, of a kind merged by area.
      final runCell =
          orthogonal &&
              collision.shapes.length == 1 &&
              known.resolve(collision.kind).merge == TileMergeMode.area
          ? geometry.cellBounds(x, y).shift(offset)
          : null;
      // Only an orthogonal map has runs to join.
      final run = orthogonal
          ? (runs.putIfAbsent(group, _RunCells.new)..occupied.add(at))
          : null;
      for (final shape in collision.shapes) {
        final outline = [
          for (final p in shape.outline()) image.topLeft + offset + place(p),
        ];
        final box = shape is TileEllipseShape ? null : _uprightBox(outline);
        if (box != null) {
          final b = _Box(box, at);
          boxes.putIfAbsent(group, () => []).add(b);
          if (runCell != null && _sameRect(box, runCell)) run!.whole[at] = b;
          continue;
        }
        final slope = runCell == null ? null : _FloorSlope.of(outline, runCell);
        if (slope != null) {
          run!.slopes[at] = slope;
          continue;
        }
        for (final piece in PolygonDecompose.convexPieces(outline)) {
          specs.add(_polygonSpec(piece, collision.kind, className, [at]));
        }
      }
    }

    for (final MapEntry(key: (kind, className), value: run) in runs.entries) {
      if (run.slopes.isEmpty) continue;
      for (final (polygon, covered) in run.hills()) {
        specs.add(_polygonSpec(polygon, kind, className, covered));
      }
      boxes[(kind, className)]?.removeWhere(run.taken.contains);
    }

    for (final entry in boxes.entries) {
      final (kind, className) = entry.key;
      final mode = known.resolve(kind).merge;
      for (final (rect, covered) in _mergeBoxes(entry.value, mode)) {
        specs.add(
          MapBodySpec(
            kind: kind,
            center: rect.center,
            size: rect.size,
            className: className,
            cells: covered,
          ),
        );
      }
    }
    return specs;
  }

  /// Whether [a] and [b] are the same rectangle, to 1/1024 of a pixel.
  static bool _sameRect(Rect a, Rect b) =>
      _key(a.left) == _key(b.left) &&
      _key(a.top) == _key(b.top) &&
      _key(a.right) == _key(b.right) &&
      _key(a.bottom) == _key(b.bottom);

  /// [outline] as a rectangle, if it is one standing upright.
  static Rect? _uprightBox(List<Offset> outline) {
    if (outline.length != 4) return null;
    int k(double v) => (v * 1024).round();
    final xs = {for (final p in outline) k(p.dx)};
    final ys = {for (final p in outline) k(p.dy)};
    if (xs.length != 2 || ys.length != 2) return null;
    // Every corner a different one of the four.
    final corners = {for (final p in outline) (k(p.dx), k(p.dy))};
    if (corners.length != 4) return null;
    var r = Rect.fromPoints(outline[0], outline[2]);
    for (final p in outline) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.isEmpty ? null : r;
  }

  /// [boxes] joined where [mode] allows: along rows, boxes of the same top
  /// and bottom that touch; then, for [TileMergeMode.area], down columns,
  /// rows of the same left and right that touch. A joined box is exactly
  /// the boxes it covers — it changes nothing a body collides with, but
  /// leaves no seam inside it for a running character to catch on.
  /// Returns each box and the cells it came from.
  static List<(Rect, List<TileCoord>)> _mergeBoxes(
    List<_Box> boxes,
    TileMergeMode mode,
  ) {
    if (mode == TileMergeMode.none) {
      return [
        for (final b in boxes) (b.rect, [b.cell]),
      ];
    }
    int k(double v) => (v * 1024).round();
    List<TileCoord> distinct(Iterable<TileCoord> cells) =>
        cells.toSet().toList();

    final bands = <(int, int), List<_Box>>{};
    for (final b in boxes) {
      bands.putIfAbsent((k(b.rect.top), k(b.rect.bottom)), () => []).add(b);
    }
    final rows = <(Rect, List<TileCoord>)>[];
    for (final band in bands.values) {
      band.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      var rect = band.first.rect;
      var covered = <TileCoord>[band.first.cell];
      for (final b in band.skip(1)) {
        if (k(b.rect.left) == k(rect.right)) {
          rect = rect.expandToInclude(b.rect);
          covered.add(b.cell);
        } else {
          rows.add((rect, distinct(covered)));
          rect = b.rect;
          covered = [b.cell];
        }
      }
      rows.add((rect, distinct(covered)));
    }
    if (mode == TileMergeMode.rows) return rows;

    final columns = <(int, int), List<(Rect, List<TileCoord>)>>{};
    for (final r in rows) {
      columns.putIfAbsent((k(r.$1.left), k(r.$1.right)), () => []).add(r);
    }
    final out = <(Rect, List<TileCoord>)>[];
    for (final column in columns.values) {
      column.sort((a, b) => a.$1.top.compareTo(b.$1.top));
      var rect = column.first.$1;
      var covered = [...column.first.$2];
      for (final r in column.skip(1)) {
        if (k(r.$1.top) == k(rect.bottom)) {
          rect = rect.expandToInclude(r.$1);
          covered.addAll(r.$2);
        } else {
          out.add((rect, distinct(covered)));
          rect = r.$1;
          covered = [...r.$2];
        }
      }
      out.add((rect, distinct(covered)));
    }
    return out;
  }

  static MapBodySpec _polygonSpec(
    List<Offset> piece,
    String kind,
    String className,
    List<TileCoord> cells,
  ) {
    var r = Rect.fromPoints(piece.first, piece.first);
    for (final p in piece) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    final c = r.center;
    return MapBodySpec(
      kind: kind,
      center: c,
      polygon: [for (final p in piece) p - c],
      className: className,
      cells: cells,
    );
  }

  /// Where a point of a [width] × [height] tile image lands once the tile
  /// is turned by [cell]'s flags, relative to the drawn image's top-left.
  ///
  /// Square and diamond tiles mirror across the diagonal, then left to
  /// right, then top to bottom — Tiled's order. A tile mirrored across the
  /// diagonal is drawn [height] wide and [width] tall. Hexagonal tiles
  /// mirror, then turn 60° per diagonal flag and 120° per rotation flag
  /// about their centre.
  static Offset Function(Offset) placement(
    int cell,
    double width,
    double height, {
    bool hexagonal = false,
  }) {
    final h = TileCell.isFlippedH(cell);
    final v = TileCell.isFlippedV(cell);
    final d = TileCell.isFlippedD(cell);
    if (hexagonal) {
      final degrees = (d ? 60 : 0) + (TileCell.isRotated120(cell) ? 120 : 0);
      final angle = degrees * math.pi / 180;
      final c = Offset(width / 2, height / 2);
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      return (p) {
        var q = p - c;
        q = Offset(h ? -q.dx : q.dx, v ? -q.dy : q.dy);
        return c + Offset(q.dx * cos - q.dy * sin, q.dx * sin + q.dy * cos);
      };
    }
    final drawnW = d ? height : width;
    final drawnH = d ? width : height;
    return (p) {
      var u = p.dx / width;
      var w = p.dy / height;
      if (d) (u, w) = (w, u);
      if (h) u = 1 - u;
      if (v) w = 1 - w;
      return Offset(u * drawnW, w * drawnH);
    };
  }

  /// [cells] merged into boxes (in cells) the way [mode] allows.
  static List<TileRange> mergeCells(Set<TileCoord> cells, TileMergeMode mode) {
    if (mode == TileMergeMode.none) {
      return [for (final c in cells) TileRange(c.x, c.y, c.x + 1, c.y + 1)];
    }
    // Runs along each row.
    final byRow = <int, List<int>>{};
    for (final c in cells) {
      byRow.putIfAbsent(c.y, () => []).add(c.x);
    }
    final rows = byRow.keys.toList()..sort();
    final runsByRow = <int, List<(int, int)>>{};
    for (final y in rows) {
      final xs = byRow[y]!..sort();
      final runs = <(int, int)>[];
      var start = xs.first;
      var prev = xs.first;
      for (final x in xs.skip(1)) {
        if (x == prev + 1) {
          prev = x;
          continue;
        }
        runs.add((start, prev + 1));
        start = prev = x;
      }
      runs.add((start, prev + 1));
      runsByRow[y] = runs;
    }
    if (mode == TileMergeMode.rows) {
      return [
        for (final y in rows)
          for (final (x0, x1) in runsByRow[y]!) TileRange(x0, y, x1, y + 1),
      ];
    }
    // Stack runs of the same span on consecutive rows into one box.
    final out = <TileRange>[];
    var open = <(int, int), int>{}; // span → first row
    int? lastRow;
    for (final y in rows) {
      final spans = runsByRow[y]!.toSet();
      final next = <(int, int), int>{};
      for (final entry in open.entries) {
        if (lastRow == y - 1 && spans.contains(entry.key)) {
          next[entry.key] = entry.value;
        } else {
          out.add(
            TileRange(entry.key.$1, entry.value, entry.key.$2, lastRow! + 1),
          );
        }
      }
      for (final span in spans) {
        next.putIfAbsent(span, () => y);
      }
      open = next;
      lastRow = y;
    }
    for (final entry in open.entries) {
      out.add(TileRange(entry.key.$1, entry.value, entry.key.$2, lastRow! + 1));
    }
    return out;
  }
}

/// [v] to 1/1024 of a pixel, so that points computed two ways compare.
int _key(double v) => (v * 1024).round();

/// A tile shape that fills its cell below one sloping line from the cell's
/// left side to its right — a 45° or 22.5° ramp's triangle or trapezoid —
/// as placed on the map (y down).
class _FloorSlope {
  _FloorSlope(this.outline, this.cell, this.leftTop, this.rightTop);

  /// Its outline, for the polygon it is when no run takes it.
  final List<Offset> outline;

  /// The cell it fills the bottom of.
  final Rect cell;

  /// Where the sloping line meets the cell's left and right sides.
  final double leftTop, rightTop;

  /// [outline] as a floor slope of [cell], or null when it is anything else
  /// (a box, a ceiling slope, a spike, a rounded corner).
  static _FloorSlope? of(List<Offset> outline, Rect cell) {
    final p = PolygonDecompose.clean(outline);
    if (p.length < 3 || p.length > 4 || !PolygonDecompose.isConvex(p)) {
      return null;
    }
    final l = _key(cell.left), r = _key(cell.right);
    final t = _key(cell.top), b = _key(cell.bottom);
    double? leftTop, rightTop;
    var bottomLeft = false, bottomRight = false;
    for (final q in p) {
      final x = _key(q.dx), y = _key(q.dy);
      if (y < t || y > b) return null;
      if (x != l && x != r) return null;
      if (y == b) {
        if (x == l) {
          bottomLeft = true;
        } else {
          bottomRight = true;
        }
      } else if (x == l) {
        if (leftTop != null) return null;
        leftTop = q.dy;
      } else {
        if (rightTop != null) return null;
        rightTop = q.dy;
      }
    }
    if (!bottomLeft || !bottomRight) return null;
    leftTop ??= cell.bottom;
    rightTop ??= cell.bottom;
    if (_key(leftTop) == _key(rightTop)) return null;
    return _FloorSlope(outline, cell, leftTop, rightTop);
  }
}

/// One column of a run: its top piece (a floor slope, or a whole cell of
/// level ground) and the whole cells beneath it.
class _RunColumn {
  _RunColumn(this.top, this.cell, this.leftTop, this.rightTop, this.fill);

  /// The top piece's cell.
  final TileCoord top;

  /// That cell's box.
  final Rect cell;

  /// Where its top meets the cell's left and right sides.
  final double leftTop, rightTop;

  /// The whole cells beneath it, top down, with nothing missing between.
  final List<_Box> fill;

  /// How far its top drops (y down) per pixel to the right.
  double get gradient => (rightTop - leftTop) / cell.width;

  /// How deep it is solid: the bottom of its last whole cell beneath.
  double get fillBottom => fill.isEmpty ? cell.bottom : fill.last.rect.bottom;
}

/// The cells of one kind and class that runs of floor slopes may join, and
/// the runs made of them.
class _RunCells {
  /// Every cell holding a shape of this kind and class.
  final Set<TileCoord> occupied = {};

  /// Its tiles that fill their whole cell with one box.
  final Map<TileCoord, _Box> whole = {};

  /// Its floor slopes.
  final Map<TileCoord, _FloorSlope> slopes = {};

  /// The boxes the runs took, which the box merge leaves out.
  final Set<_Box> taken = Set.identity();

  final Set<TileCoord> _used = {};

  /// Each run, from its leftmost slope not yet in one: a convex polygon,
  /// and the cells it covers (that slope first).
  List<(List<Offset>, List<TileCoord>)> hills() {
    final out = <(List<Offset>, List<TileCoord>)>[];
    final byColumn = <int, List<TileCoord>>{};
    for (final c in slopes.keys) {
      byColumn.putIfAbsent(c.x, () => []).add(c);
    }
    final seeds = slopes.keys.toList()
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    for (final seed in seeds) {
      if (_used.contains(seed)) continue;
      _used.add(seed);
      final run = _Run(_column(seed));
      _grow(run, byColumn, right: true);
      _grow(run, byColumn, right: false);
      out.add(_close(seed, run));
    }
    return out;
  }

  /// The column whose top piece is the slope or whole cell at [at].
  _RunColumn _column(TileCoord at) {
    final slope = slopes[at];
    if (slope != null) {
      return _RunColumn(
        at,
        slope.cell,
        slope.leftTop,
        slope.rightTop,
        _fillBelow(at),
      );
    }
    final cell = whole[at]!.rect;
    return _RunColumn(at, cell, cell.top, cell.top, _fillBelow(at));
  }

  /// The whole cells straight beneath [at] that no run has taken.
  List<_Box> _fillBelow(TileCoord at) {
    final fill = <_Box>[];
    for (var y = at.y + 1; ; y++) {
      final c = TileCoord(at.x, y);
      final box = whole[c];
      if (box == null || _used.contains(c)) break;
      fill.add(box);
    }
    return fill;
  }

  /// The column beside [from], on its right or else its left, that carries
  /// the run on from the height [from]'s top ends at there: a slope, or a
  /// whole cell with nothing of this kind and class on top of it. Null when
  /// there is none.
  _RunColumn? _next(
    _RunColumn from,
    Map<int, List<TileCoord>> byColumn, {
    required bool right,
  }) {
    final x = from.top.x + (right ? 1 : -1);
    final edge = _key(right ? from.cell.right : from.cell.left);
    final y = right ? from.rightTop : from.leftTop;
    final height = _key(y);
    for (final c in byColumn[x] ?? const <TileCoord>[]) {
      if (_used.contains(c)) continue;
      final s = slopes[c]!;
      if (_key(right ? s.cell.left : s.cell.right) != edge) continue;
      if (_key(right ? s.leftTop : s.rightTop) == height) return _column(c);
    }
    // Level ground: the cell whose top is at that height.
    final row = from.top.y + ((y - from.cell.top) / from.cell.height).round();
    final c = TileCoord(x, row);
    final box = whole[c];
    if (box == null ||
        _used.contains(c) ||
        _key(box.rect.top) != height ||
        _key(right ? box.rect.left : box.rect.right) != edge ||
        occupied.contains(TileCoord(x, row - 1))) {
      return null;
    }
    return _column(c);
  }

  /// Adds columns to [run] on its right, or else its left, while it takes
  /// them.
  void _grow(
    _Run run,
    Map<int, List<TileCoord>> byColumn, {
    required bool right,
  }) {
    while (true) {
      final end = right ? run.columns.last : run.columns.first;
      final next = _next(end, byColumn, right: right);
      if (next == null || !run.add(next, right: right)) return;
      _used.add(next.top);
    }
  }

  /// The polygon [run] makes and the cells it covers, [seed] first; the
  /// whole cells it covers leave the box merge.
  (List<Offset>, List<TileCoord>) _close(TileCoord seed, _Run run) {
    final points = run.polygon;
    final bottom = _key(run.bottom);
    final cells = <TileCoord>[seed];
    for (final c in run.columns) {
      if (c.top != seed) cells.add(c.top);
      final ground = whole[c.top];
      if (ground != null) taken.add(ground);
      for (final box in c.fill) {
        if (_key(box.rect.bottom) > bottom) break;
        cells.add(box.cell);
        taken.add(box);
        _used.add(box.cell);
      }
    }
    return (points, cells);
  }
}

/// The columns of one run, left to right, and what they make together.
class _Run {
  _Run(_RunColumn first)
    : columns = [first],
      bottom = first.cell.bottom,
      _solid = first.fillBottom;

  /// Its columns, left to right.
  final List<_RunColumn> columns;

  /// Where its polygon ends below: the bottom of its lowest top piece's cell.
  double bottom;

  /// How deep every column is solid.
  double _solid;

  /// How often its top turns, left to right.
  int _turns = 0;

  /// Takes [next] on its right, or else its left, if its polygon stays
  /// convex (going right, its top only ever turns down), solid down to its
  /// bottom, and within eight points; whether it did.
  bool add(_RunColumn next, {required bool right}) {
    final end = right ? columns.last : columns.first;
    final turn = right
        ? next.gradient - end.gradient
        : end.gradient - next.gradient;
    if (turn < -1e-9) return false;
    final bottom = math.max(this.bottom, next.cell.bottom);
    final solid = math.min(_solid, next.fillBottom);
    if (_key(solid) < _key(bottom)) return false;
    final turns = _turns + (turn > 1e-9 ? 1 : 0);
    final first = right ? columns.first : next;
    final last = right ? next : columns.last;
    // The top's ends and turns, and a bottom corner below each end that is
    // not on the bottom already.
    final points =
        turns +
        2 +
        (_key(first.leftTop) == _key(bottom) ? 0 : 1) +
        (_key(last.rightTop) == _key(bottom) ? 0 : 1);
    if (points > PolygonDecompose.maxVertices) return false;
    if (right) {
      columns.add(next);
    } else {
      columns.insert(0, next);
    }
    this.bottom = bottom;
    _solid = solid;
    _turns = turns;
    return true;
  }

  /// Its convex polygon: down each side to [bottom], along the top through
  /// each turn.
  List<Offset> get polygon {
    final first = columns.first, last = columns.last;
    final top = [Offset(first.cell.left, first.leftTop)];
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      final turns =
          i + 1 == columns.length ||
          (columns[i + 1].gradient - c.gradient).abs() > 1e-9;
      if (turns) top.add(Offset(c.cell.right, c.rightTop));
    }
    final points = PolygonDecompose.clean([
      Offset(first.cell.left, bottom),
      ...top,
      Offset(last.cell.right, bottom),
    ]);
    assert(
      points.length >= 3 &&
          points.length <= PolygonDecompose.maxVertices &&
          PolygonDecompose.isConvex(points),
      'a run of slopes made a polygon Box2D cannot take: $points',
    );
    return points;
  }
}
