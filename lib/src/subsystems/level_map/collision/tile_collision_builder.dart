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
  const MapBodySpec({
    required this.kind,
    required this.center,
    this.size,
    this.polygon,
    this.className = '',
    this.cells = const [],
  }) : assert(size != null || polygon != null);

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
abstract final class TileCollisionBuilder {
  /// The bodies for [cells], drawn on [geometry] with tilesets looked up by
  /// slot through [tilesetAt], the layer moved by [offset].
  static List<MapBodySpec> build({
    required TileChunkStore cells,
    required MapGeometry geometry,
    required TilesetData? Function(int slot) tilesetAt,
    Offset offset = Offset.zero,
  }) {
    final specs = <MapBodySpec>[];
    // Boxes waiting to be merged, by kind and class: whole cells, and every
    // shape that lands as an upright rectangle — a half-tile ledge, a
    // quarter of terrain.
    final boxes = <(String, String), List<_Box>>{};

    for (final (x, y, cell) in cells.cells) {
      final tileset = tilesetAt(TileCell.slotOf(cell));
      if (tileset == null) continue;
      final def = tileset.tile(TileCell.localIdOf(cell));
      final collision = def?.collision;
      if (collision == null || collision.shapes.isEmpty) continue;
      final className = def!.className;
      final at = TileCoord(x, y);

      final hexagonal = geometry.orientation == MapOrientation.hexagonal;
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
      for (final shape in collision.shapes) {
        final outline = [
          for (final p in shape.outline()) image.topLeft + offset + place(p),
        ];
        final box = shape is TileEllipseShape ? null : _uprightBox(outline);
        if (box != null) {
          boxes
              .putIfAbsent((collision.kind, className), () => [])
              .add(_Box(box, at));
          continue;
        }
        for (final piece in PolygonDecompose.convexPieces(outline)) {
          specs.add(_polygonSpec(piece, collision.kind, className, [at]));
        }
      }
    }

    for (final entry in boxes.entries) {
      final (kind, className) = entry.key;
      final mode = MapCollisionKinds.resolve(kind).merge;
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
