/// Drawing a map layer: its tiles in cached `drawRawAtlas` batches, culled
/// to the view.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../ecs/components/components.dart';
import '../../../ecs/ecs.dart';
import '../../../ecs/serialization/component_presentation.dart'
    show RenderContext;
import '../tile_cell.dart';
import '../tile_chunks.dart';
import '../level_map_data.dart';
import '../map_geometry.dart';
import '../level_map_runtime.dart';

/// One map layer's tiles, as one of the level's things to draw: it sorts
/// among sprites and shapes by the layer's own sort layer and z-order, and
/// the entities on the layer draw just after it.
class MapLayerRenderItem extends RenderItem {
  /// The item drawing layer [layerId] of [runtime]'s map.
  MapLayerRenderItem(this.runtime, this.layerId);

  /// The map whose layer it draws.
  final LevelMapRuntime runtime;

  /// The layer, by its id within the map.
  final int layerId;

  /// The layer's data; null once the map no longer has it, and the item
  /// then draws nothing.
  MapLayerData? get data => runtime.base.layerById(layerId);

  /// Set by `LevelMapSystem`: where the layer sits among the map's layers
  /// and the entities on them.
  @override
  int subOrder = 0;

  /// Set by `LevelMapSystem` when the map is a piece of another map's layer:
  /// it then draws where that layer does, not where its own layer says.
  int? layerOverride;

  /// The z-order of that other layer, set along with [layerOverride]; null
  /// uses this layer's own.
  int? zOrderOverride;

  @override
  int get layer => layerOverride ?? data?.sortLayer ?? 0;

  @override
  int get zOrder => zOrderOverride ?? data?.zOrder ?? 0;

  @override
  bool get visible {
    final d = data;
    return d != null && d.visible && (runtime.layerAlpha[layerId] ?? 1) > 0;
  }

  @override
  void render(Canvas canvas, RenderContext context, Entity owner) =>
      runtime.painter.paint(canvas, context, owner, layerId);
}

/// A run of tiles drawn with one call: same tileset, same side of the
/// mirror.
class _Run {
  _Run(this.slot, this.mirrored);

  final int slot;
  final bool mirrored;
  final List<double> _t = [];
  final List<double> _r = [];
  late Float32List transforms;
  late Float32List rects;

  /// Animated tiles in this run: index, tile id, tile shown.
  final List<(int, int, int)> animated = [];

  Int32List? _colors;
  int _colorsFor = 0;

  /// How many tiles: counted while building, fixed by [finish].
  int length = 0;

  void add(double scos, double ssin, double tx, double ty, Rect src) {
    _t.addAll([scos, ssin, tx, ty]);
    _r.addAll([src.left, src.top, src.right, src.bottom]);
    length++;
  }

  void finish() {
    transforms = Float32List.fromList(_t);
    rects = Float32List.fromList(_r);
    _t.clear();
    _r.clear();
  }

  Int32List colors(int argb) {
    if (_colors == null || _colorsFor != argb) {
      _colors = Int32List(length)..fillRange(0, length, argb.toSigned(32));
      _colorsFor = argb;
    }
    return _colors!;
  }
}

/// The runs of one chunk (orthogonal, isometric) or one band of chunk rows
/// (staggered, hexagonal), and what they were built from.
class _Batch {
  _Batch(this.signature, this.runs, {required this.complete});
  final int signature;
  final List<_Run> runs;

  /// False when a tileset or image was still loading: build again.
  final bool complete;
  int shownMs = -1;
}

/// What one [MapLayerPainter.paint] call draws with, handed from batch to
/// batch.
class _Draw {
  _Draw(
    this.canvas,
    this.batches,
    this.geometry,
    this.layerId, {
    required this.ordered,
    required this.assets,
    required this.color,
  });

  final Canvas canvas;
  final Map<int, _Batch> batches;
  final MapGeometry geometry;
  final int layerId;
  final bool ordered;

  /// The signature of what every batch is built from besides its chunks.
  final int assets;
  final int? color;
}

/// Draws a map's layers.
///
/// A layer is cut into batches — a chunk each on orthogonal and isometric
/// maps, a band of chunk rows on staggered and hexagonal ones (whose rows
/// overlap across chunk boundaries), and on orthogonal ones whose tiles can
/// reach out of their cells (the band then holds the chunks in view) — and
/// each batch is built once into
/// `drawRawAtlas` buffers, then drawn every frame for as long as its cells,
/// tilesets and images stay the same. Only batches in view are drawn.
///
/// Tiles are drawn back to front on screen, so a tall tile overlaps the
/// row behind it. A tile mirrored by its flags is drawn from a mirrored copy
/// of its tileset image, because an atlas transform can turn and scale but
/// not mirror; with that, each of the eight turns and mirrors of a square
/// tile is "mirrored image or not" plus a number of quarter turns.
class MapLayerPainter {
  /// A painter for [runtime]'s layers, with no batches built yet.
  MapLayerPainter(this.runtime);

  /// The map whose layers it draws.
  final LevelMapRuntime runtime;
  final Map<int, Map<int, _Batch>> _batches = {};
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  /// Draws layer [layerId] of the map on [owner] — whose position is the
  /// map's origin — onto [canvas], with the layer's offset, parallax,
  /// opacity and tint. Only batches in [context]'s camera view are drawn
  /// (all of them without a camera), each rebuilt first if its cells,
  /// tilesets or images have changed. A layer the map no longer has draws
  /// nothing.
  void paint(Canvas canvas, RenderContext context, Entity owner, int layerId) {
    final layer = runtime.base.layerById(layerId);
    if (layer == null) return;
    final p = owner.getComponent<TransformComponent>()?.position;
    final origin = p == null ? Offset.zero : Offset(p.x, p.y);
    var shift = origin + Offset(layer.offsetX, layer.offsetY);
    final camera = context.camera;
    if (camera != null && (layer.parallaxX != 1 || layer.parallaxY != 1)) {
      // A distant layer lags behind the camera: measured from the map's
      // origin, so it lines up where the camera looks at the origin.
      final rel = camera.position - origin;
      shift += Offset(
        rel.dx * (1 - layer.parallaxX),
        rel.dy * (1 - layer.parallaxY),
      );
    }

    final geometry = runtime.geometry;
    // In the layer's own pixels, widened by the largest tile, whose image
    // can reach out of its cell.
    Rect? view;
    if (camera != null) {
      var reach = math.max(geometry.tileWidth, geometry.tileHeight).toDouble();
      for (final ts in runtime.tilesets) {
        if (ts != null) {
          reach = math.max(
            reach,
            math.max(ts.tileWidth, ts.tileHeight).toDouble(),
          );
        }
      }
      view = camera.getVisibleBounds().shift(-shift).inflate(reach);
    }

    final alpha = (layer.opacity * (runtime.layerAlpha[layerId] ?? 1)).clamp(
      0.0,
      1.0,
    );
    final tint = layer.tint;
    int? color;
    if (tint != null || alpha < 1) {
      final base = tint ?? 0xFFFFFFFF;
      final a = (((base >>> 24) & 0xFF) * alpha).round();
      color = (a << 24) | (base & 0xFFFFFF);
    }

    final cells = runtime.cellsOf(layer);
    final bounds = cells.chunkBounds;
    if (bounds == null) return;
    final orientation = geometry.orientation;
    final banded =
        orientation == MapOrientation.staggered ||
        orientation == MapOrientation.hexagonal;
    final iso = orientation == MapOrientation.isometric;
    // Orthogonal tiles that can reach out of their cells are drawn row by
    // row across the layer, as Tiled draws them: a band of chunks per chunk
    // row, in order. (Drawn a chunk at a time, one run per tileset, a tall
    // tile could be drawn before — and under — the row behind it, or under
    // the next chunk.)
    final rows =
        banded ||
        (orientation == MapOrientation.orthogonal && _tilesOverlap(geometry));

    // The chunks to walk: those in view, among those there are. A banded
    // layer's batch is a whole row of chunks, so only rows are culled.
    var cx0 = bounds.cx0, cy0 = bounds.cy0;
    var cx1 = bounds.cx1, cy1 = bounds.cy1;
    if (view != null) {
      final r = geometry.cellRange(view);
      cy0 = math.max(cy0, r.y0 >> 4);
      cy1 = math.min(cy1, ((r.y1 - 1) >> 4) + 1);
      if (!banded) {
        cx0 = math.max(cx0, r.x0 >> 4);
        cx1 = math.min(cx1, ((r.x1 - 1) >> 4) + 1);
      }
    }
    if (cx1 <= cx0 || cy1 <= cy0) return;

    var batches = _batches[layerId];
    if (batches == null) _batches[layerId] = batches = {};
    final draw = _Draw(
      canvas,
      batches,
      geometry,
      layerId,
      ordered: rows || iso,
      assets: Object.hash(
        runtime.assetsRevision,
        runtime.tilesetsRevision,
        runtime.base.revision,
        runtime.hiddenRevision,
        rows,
      ),
      color: color,
    );

    canvas.save();
    canvas.translate(shift.dx, shift.dy);
    final group = _group;
    if ((cx1 - cx0) * (cy1 - cy0) > cells.chunkCount * 4 + 64) {
      // A few chunks spread far apart: walk those there are.
      _drawSparse(draw, cells, cx0, cy0, cx1, cy1, banded: rows, iso: iso);
    } else if (rows) {
      // A band per row of chunks, top to bottom.
      for (var cy = cy0; cy < cy1; cy++) {
        group.clear();
        for (var cx = cx0; cx < cx1; cx++) {
          final c = cells.chunk(cx, cy);
          if (c != null) group.add(c);
        }
        if (group.isNotEmpty) _drawGroup(draw, cy, group);
      }
    } else if (iso) {
      // Diagonal by diagonal (cx + cy), each left to right: back to front.
      for (var d = cx0 + cy0; d <= cx1 + cy1 - 2; d++) {
        final from = math.max(cx0, d - cy1 + 1);
        final to = math.min(cx1 - 1, d - cy0);
        for (var cx = from; cx <= to; cx++) {
          final c = cells.chunk(cx, d - cx);
          if (c != null) _drawChunk(draw, c);
        }
      }
    } else {
      // Row by row, each left to right.
      for (var cy = cy0; cy < cy1; cy++) {
        for (var cx = cx0; cx < cx1; cx++) {
          final c = cells.chunk(cx, cy);
          if (c != null) _drawChunk(draw, c);
        }
      }
    }
    group.clear();
    canvas.restore();
  }

  /// Whether a tile of the map's tilesets can reach out of its cell on the
  /// grid [g]: one bigger than a cell — either way round, since a tile can
  /// be turned a quarter — or moved by its tileset's offset.
  bool _tilesOverlap(MapGeometry g) {
    for (final ts in runtime.tilesets) {
      if (ts == null) continue;
      final w = ts.tileWidth, h = ts.tileHeight;
      if (w > g.tileWidth ||
          h > g.tileHeight ||
          ts.tileOffsetX != 0 ||
          ts.tileOffsetY != 0 ||
          (w != h && (h > g.tileWidth || w > g.tileHeight))) {
        return true;
      }
    }
    return false;
  }

  /// The chunks of the batch being drawn, reused from batch to batch.
  final List<TileChunkData> _group = [];

  void _drawChunk(_Draw draw, TileChunkData chunk) {
    _group
      ..clear()
      ..add(chunk);
    _drawGroup(draw, TileChunkStore.keyOf(chunk.cx, chunk.cy), _group);
  }

  /// The chunks in range, found by going through the chunks there are
  /// rather than looking each place in the range up, and sorted into draw
  /// order: cheaper when a few chunks lie far apart.
  void _drawSparse(
    _Draw draw,
    TileChunkStore cells,
    int cx0,
    int cy0,
    int cx1,
    int cy1, {
    required bool banded,
    required bool iso,
  }) {
    final list = [
      for (final c in cells.chunks)
        if (c.cy >= cy0 && c.cy < cy1 && c.cx >= cx0 && c.cx < cx1) c,
    ];
    list.sort((a, b) {
      if (iso) {
        final d = (a.cx + a.cy).compareTo(b.cx + b.cy);
        if (d != 0) return d;
        return a.cx.compareTo(b.cx);
      }
      final d = a.cy.compareTo(b.cy);
      return d != 0 ? d : a.cx.compareTo(b.cx);
    });
    if (!banded) {
      for (final c in list) {
        _drawChunk(draw, c);
      }
      return;
    }
    var i = 0;
    while (i < list.length) {
      final cy = list[i].cy;
      final band = <TileChunkData>[];
      while (i < list.length && list[i].cy == cy) {
        band.add(list[i++]);
      }
      _drawGroup(draw, cy, band);
    }
  }

  /// Draws the batch [key] made of [chunks], built again first if they,
  /// or the tilesets and images, have changed since it was.
  void _drawGroup(_Draw draw, int key, List<TileChunkData> chunks) {
    var signature = draw.assets;
    for (final c in chunks) {
      signature = Object.hash(signature, identityHashCode(c), c.revision);
    }
    var batch = draw.batches[key];
    if (batch == null || batch.signature != signature || !batch.complete) {
      batch = _build(
        chunks,
        draw.geometry,
        draw.layerId,
        ordered: draw.ordered,
        signature: signature,
      );
      draw.batches[key] = batch;
    }
    _animate(batch);
    final color = draw.color;
    for (final run in batch.runs) {
      final image = run.mirrored
          ? runtime.mirroredAt(run.slot)
          : runtime.imageAt(run.slot);
      if (image == null || run.length == 0) continue;
      draw.canvas.drawRawAtlas(
        image,
        run.transforms,
        run.rects,
        color == null ? null : run.colors(color),
        color == null ? null : BlendMode.modulate,
        null,
        _paint,
      );
    }
  }

  _Batch _build(
    List<TileChunkData> chunks,
    MapGeometry geometry,
    int layerId, {
    required bool ordered,
    required int signature,
  }) {
    final hidden = runtime.hiddenCellsOf(layerId);
    final hex = geometry.orientation == MapOrientation.hexagonal;
    final entries = <(int, int, int)>[];
    for (final chunk in chunks) {
      final x0 = chunk.cx * TileChunkStore.size;
      final y0 = chunk.cy * TileChunkStore.size;
      for (var i = 0; i < TileChunkStore.cellsPerChunk; i++) {
        final cell = chunk.cells[i];
        if (TileCell.isEmpty(cell)) continue;
        final x = x0 + (i & 15);
        final y = y0 + (i >> 4);
        if (hidden != null && hidden.contains(TileCoord(x, y))) continue;
        entries.add((x, y, cell));
      }
    }
    if (ordered) {
      entries.sort(
        (a, b) => geometry.compareDrawOrder(
          TileCoord(a.$1, a.$2),
          TileCoord(b.$1, b.$2),
        ),
      );
    }

    var complete = true;
    final runs = <_Run>[];
    final bySlot = <(int, bool), _Run>{};
    _Run runFor(int slot, bool mirrored) {
      if (!ordered) {
        return bySlot.putIfAbsent((slot, mirrored), () {
          final r = _Run(slot, mirrored);
          runs.add(r);
          return r;
        });
      }
      // In order: a new run whenever the tileset or mirror changes, so
      // tiles still overlap back to front.
      if (runs.isNotEmpty &&
          runs.last.slot == slot &&
          runs.last.mirrored == mirrored) {
        return runs.last;
      }
      final r = _Run(slot, mirrored);
      runs.add(r);
      return r;
    }

    for (final (x, y, cell) in entries) {
      final slot = TileCell.slotOf(cell);
      final ts = runtime.tilesetAt(slot);
      final image = runtime.imageAt(slot);
      if (ts == null || image == null) {
        complete = false;
        continue;
      }
      final id = TileCell.localIdOf(cell);
      if (!ts.contains(id)) continue;
      final def = ts.tile(id);

      final (:mirrored, :radians, :sideways) = TileCell.drawTransform(
        cell,
        hexagonal: hex,
      );
      if (mirrored && runtime.mirroredAt(slot) == null) {
        complete = false;
        continue;
      }

      final tw = ts.tileWidth.toDouble();
      final th = ts.tileHeight.toDouble();
      final dest = geometry.tileImageRect(
        x,
        y,
        sideways ? th : tw,
        sideways ? tw : th,
        offsetX: ts.tileOffsetX,
        offsetY: ts.tileOffsetY,
      );
      final scos = math.cos(radians);
      final ssin = math.sin(radians);
      final ax = tw / 2;
      final ay = th / 2;
      final c = dest.center;
      final run = runFor(slot, mirrored);
      final shown = def?.isAnimated ?? false
          ? def!.frameAt(id, runtime.animationMs)
          : id;
      run.add(
        scos,
        ssin,
        c.dx - scos * ax + ssin * ay,
        c.dy - ssin * ax - scos * ay,
        _source(slot, shown, mirrored),
      );
      if (def?.isAnimated ?? false) {
        run.animated.add((run.length - 1, id, shown));
      }
    }
    for (final r in runs) {
      r.finish();
    }
    return _Batch(signature, runs, complete: complete)
      ..shownMs = runtime.animationMs;
  }

  Rect _source(int slot, int tileId, bool mirrored) {
    final ts = runtime.tilesetAt(slot)!;
    final src = ts.sourceRect(tileId);
    if (!mirrored) return src;
    final width = runtime.imageAt(slot)!.width.toDouble();
    return Rect.fromLTRB(
      width - src.right,
      src.top,
      width - src.left,
      src.bottom,
    );
  }

  /// Moves animated tiles on to the frame of the moment, in place.
  void _animate(_Batch batch) {
    if (batch.shownMs == runtime.animationMs) return;
    batch.shownMs = runtime.animationMs;
    for (final run in batch.runs) {
      final ts = runtime.tilesetAt(run.slot);
      if (ts == null) continue;
      for (var i = 0; i < run.animated.length; i++) {
        final (index, id, shown) = run.animated[i];
        final now = ts.tile(id)?.frameAt(id, runtime.animationMs) ?? id;
        if (now == shown) continue;
        final src = _source(run.slot, now, run.mirrored);
        run.rects
          ..[index * 4] = src.left
          ..[index * 4 + 1] = src.top
          ..[index * 4 + 2] = src.right
          ..[index * 4 + 3] = src.bottom;
        run.animated[i] = (index, id, now);
      }
    }
  }
}
