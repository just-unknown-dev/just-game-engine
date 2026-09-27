/// A tile layer's cells, stored sparsely in 16×16 chunks.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';

import 'tile_cell.dart';

/// Sixteen by sixteen cells of one layer.
class TileChunkData {
  TileChunkData(this.cx, this.cy, [Uint32List? cells])
    : cells = cells ?? Uint32List(TileChunkStore.cellsPerChunk);

  /// Which chunk: the cell (cx * 16, cy * 16) is its top-left.
  final int cx;
  final int cy;

  /// Row by row. Write through [TileChunkStore.setCell] so the revision
  /// and the saved form keep up.
  final Uint32List cells;

  /// Bumped on every change: what a renderer keys its cached buffers on.
  int revision = 0;

  /// This chunk as the codec last wrote it; null once it changes.
  String? encoded;

  /// Whether every cell is empty.
  bool get isEmpty {
    for (final c in cells) {
      if (!TileCell.isEmpty(c)) return false;
    }
    return true;
  }

  TileChunkData copy() => TileChunkData(cx, cy, Uint32List.fromList(cells))
    ..revision = revision
    ..encoded = encoded;
}

/// A layer's cells: any number of them, in any direction, only where
/// something is painted.
///
/// An infinite map has no size to allocate up front, and a level is mostly
/// empty air, so cells live in 16×16 chunks that exist only where a tile
/// was placed — the same scheme Tiled uses for infinite maps.
///
/// A store made with [TileChunkStore.over] reads through to a base store and
/// copies a chunk the first time it writes to it: the running game changes
/// its own copy of a map (a crumbled block, an opened door) while the loaded
/// map — shared with every other user of the file, or the editor's document
/// — stays as it was.
class TileChunkStore {
  TileChunkStore() : base = null;

  /// A store whose writes land in its own copies of [base]'s chunks.
  TileChunkStore.over(TileChunkStore this.base);

  /// Cells per side of a chunk.
  static const int size = 16;

  /// Cells in a chunk.
  static const int cellsPerChunk = size * size;

  /// What this store reads through to, when it is an overlay.
  final TileChunkStore? base;

  final Map<int, TileChunkData> _own = {};

  /// Bumped on every change to any cell: a cheap "has anything changed".
  int revision = 0;

  /// The key of chunk ([cx], [cy]). Chunks range over ±32767 in each
  /// direction — half a million cells — and the key stays a 32-bit value
  /// so it is exact on the web.
  static int keyOf(int cx, int cy) =>
      ((cx + 0x8000) & 0xFFFF) * 0x10000 + ((cy + 0x8000) & 0xFFFF);

  /// The chunk holding cell [x] or [y] along one axis.
  static int chunkIndexOf(int v) => v >> 4;

  /// The chunk ([cx], [cy]), or null where nothing was ever painted.
  TileChunkData? chunk(int cx, int cy) =>
      _own[keyOf(cx, cy)] ?? base?.chunk(cx, cy);

  /// The cell at ([x], [y]); [TileCell.empty] where nothing is.
  int cellAt(int x, int y) {
    final c = chunk(x >> 4, y >> 4);
    return c == null ? TileCell.empty : c.cells[((y & 15) << 4) | (x & 15)];
  }

  /// Sets the cell at ([x], [y]). Returns whether it changed.
  bool setCell(int x, int y, int cell) {
    final cx = x >> 4;
    final cy = y >> 4;
    final key = keyOf(cx, cy);
    var target = _own[key];
    final index = ((y & 15) << 4) | (x & 15);
    if (target == null) {
      final inherited = base?.chunk(cx, cy);
      final current = inherited?.cells[index] ?? TileCell.empty;
      if (current == cell) return false;
      target = inherited?.copy() ?? TileChunkData(cx, cy);
      _own[key] = target;
    } else if (target.cells[index] == cell) {
      return false;
    }
    target.cells[index] = cell.toUnsigned(32);
    target
      ..revision += 1
      ..encoded = null;
    revision++;
    return true;
  }

  /// Every chunk this store has, its own and the ones it reads through to.
  Iterable<TileChunkData> get chunks sync* {
    yield* _own.values;
    final base = this.base;
    if (base == null) return;
    for (final c in base.chunks) {
      if (!_own.containsKey(keyOf(c.cx, c.cy))) yield c;
    }
  }

  /// Every painted cell, with its position.
  Iterable<(int x, int y, int cell)> get cells sync* {
    for (final chunk in chunks) {
      final x0 = chunk.cx * size;
      final y0 = chunk.cy * size;
      for (var i = 0; i < cellsPerChunk; i++) {
        final cell = chunk.cells[i];
        if (!TileCell.isEmpty(cell)) yield (x0 + (i & 15), y0 + (i >> 4), cell);
      }
    }
  }

  /// Whether no cell holds a tile.
  bool get isEmpty => cells.isEmpty;

  /// The rectangle of cells holding tiles, right and bottom exclusive — or
  /// null when there are none.
  Rect? get usedBounds {
    int? minX, minY, maxX, maxY;
    for (final (x, y, _) in cells) {
      if (minX == null || x < minX) minX = x;
      if (minY == null || y < minY) minY = y;
      if (maxX == null || x > maxX) maxX = x;
      if (maxY == null || y > maxY) maxY = y;
    }
    if (minX == null) return null;
    return Rect.fromLTRB(
      minX.toDouble(),
      minY!.toDouble(),
      maxX! + 1.0,
      maxY! + 1.0,
    );
  }

  /// Removes every cell. An overlay then reads through to its base again.
  void clear() {
    if (_own.isEmpty) return;
    _own.clear();
    revision++;
  }

  /// A separate store with the same cells, overlay flattened in.
  TileChunkStore copy() {
    final out = TileChunkStore();
    for (final c in chunks) {
      out._own[keyOf(c.cx, c.cy)] = c.copy();
    }
    return out;
  }

  // ── The saved form ─────────────────────────────────────────────────────
  //
  // {"cx,cy": base64(zlib(uint32 little-endian × 256))} — one short string
  // per painted chunk, empty chunks left out. Each chunk's string is cached
  // until it changes, because the editor encodes a whole map far more often
  // than it would seem: on save, when play starts, and whenever an undo
  // step snapshots the entity the map is on.

  /// The cells as they are saved.
  Map<String, String> toJson() {
    final out = <String, String>{};
    final ordered = chunks.toList()
      ..sort(
        (a, b) => a.cy != b.cy ? a.cy.compareTo(b.cy) : a.cx.compareTo(b.cx),
      );
    for (final c in ordered) {
      if (c.isEmpty) continue;
      out['${c.cx},${c.cy}'] = c.encoded ??= _encode(c.cells);
    }
    return out;
  }

  /// Reads what [toJson] wrote. A chunk that cannot be read is skipped
  /// rather than failing the whole map.
  static TileChunkStore fromJson(Object? json) {
    final store = TileChunkStore();
    if (json is! Map) return store;
    for (final entry in json.entries) {
      final parts = '${entry.key}'.split(',');
      if (parts.length != 2) continue;
      final cx = int.tryParse(parts[0]);
      final cy = int.tryParse(parts[1]);
      final text = entry.value;
      if (cx == null || cy == null || text is! String) continue;
      final cells = _decode(text);
      if (cells == null) continue;
      store._own[keyOf(cx, cy)] = TileChunkData(cx, cy, cells)..encoded = text;
    }
    return store;
  }

  static String _encode(Uint32List cells) {
    final bytes = ByteData(cells.length * 4);
    for (var i = 0; i < cells.length; i++) {
      bytes.setUint32(i * 4, cells[i], Endian.little);
    }
    return base64Encode(ZLibEncoder().encodeBytes(bytes.buffer.asUint8List()));
  }

  static Uint32List? _decode(String text) {
    try {
      final bytes = Uint8List.fromList(
        ZLibDecoder().decodeBytes(base64Decode(text)),
      );
      if (bytes.length != cellsPerChunk * 4) return null;
      final view = ByteData.sublistView(bytes);
      final out = Uint32List(cellsPerChunk);
      for (var i = 0; i < cellsPerChunk; i++) {
        out[i] = view.getUint32(i * 4, Endian.little);
      }
      return out;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
