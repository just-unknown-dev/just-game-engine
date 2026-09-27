/// Drawing a map layer: its tiles in cached `drawRawAtlas` batches, culled
/// to the view.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../ecs/components/components.dart';
import '../../../ecs/ecs.dart';
import '../../../ecs/serialization/component_definition.dart'
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
  MapLayerRenderItem(this.runtime, this.layerId);

  final LevelMapRuntime runtime;
  final int layerId;

  MapLayerData? get data => runtime.base.layerById(layerId);

  /// Set by `LevelMapSystem`: where the layer sits among the map's layers
  /// and the entities on them.
  @override
  int subOrder = 0;

  /// Set by `LevelMapSystem` when the map is a piece of another map's layer:
  /// it then draws where that layer does, not where its own layer says.
  int? layerOverride;
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

/// Draws a map's layers.
///
/// A layer is cut into batches — a chunk each on orthogonal and isometric
/// maps, a band of chunk rows on staggered and hexagonal ones (whose rows
/// overlap across chunk boundaries) — and each batch is built once into
/// `drawRawAtlas` buffers, then drawn every frame for as long as its cells,
/// tilesets and images stay the same. Only batches in view are drawn.
///
/// Tiles are drawn back to front on screen, so a tall tile overlaps the
/// row behind it. A tile mirrored by its flags is drawn from a mirrored copy
/// of its tileset image, because an atlas transform can turn and scale but
/// not mirror; with that, each of the eight turns and mirrors of a square
/// tile is "mirrored image or not" plus a number of quarter turns.
class MapLayerPainter {
  MapLayerPainter(this.runtime);

  final LevelMapRuntime runtime;
  final Map<int, Map<int, _Batch>> _batches = {};
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  /// Forgets every built batch.
  void invalidate() => _batches.clear();

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
    final batches = _batches.putIfAbsent(layerId, () => {});
    final banded =
        geometry.orientation == MapOrientation.staggered ||
        geometry.orientation == MapOrientation.hexagonal;

    canvas.save();
    canvas.translate(shift.dx, shift.dy);
    for (final (key, chunks) in _groups(cells, view, geometry, banded)) {
      final signature = _signature(chunks, layerId);
      var batch = batches[key];
      if (batch == null || batch.signature != signature || !batch.complete) {
        batch = _build(
          chunks,
          geometry,
          layerId,
          ordered: banded || geometry.orientation == MapOrientation.isometric,
          signature: signature,
        );
        batches[key] = batch;
      }
      _animate(batch);
      for (final run in batch.runs) {
        final image = run.mirrored
            ? runtime.mirroredAt(run.slot)
            : runtime.imageAt(run.slot);
        if (image == null || run.length == 0) continue;
        canvas.drawRawAtlas(
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
    canvas.restore();
  }

  /// The chunks to draw, in draw order, grouped into batches.
  Iterable<(int, List<TileChunkData>)> _groups(
    TileChunkStore cells,
    Rect? view,
    MapGeometry geometry,
    bool banded,
  ) sync* {
    TileRange? chunkRange;
    if (view != null) {
      final r = geometry.cellRange(view);
      chunkRange = TileRange(
        r.x0 >> 4,
        r.y0 >> 4,
        ((r.x1 - 1) >> 4) + 1,
        ((r.y1 - 1) >> 4) + 1,
      );
    }
    final all = cells.chunks.where(
      (c) =>
          chunkRange == null ||
          (banded
              ? c.cy >= chunkRange.y0 && c.cy < chunkRange.y1
              : chunkRange.contains(c.cx, c.cy)),
    );
    if (banded) {
      final bands = <int, List<TileChunkData>>{};
      for (final c in all) {
        bands.putIfAbsent(c.cy, () => []).add(c);
      }
      final keys = bands.keys.toList()..sort();
      for (final cy in keys) {
        yield (cy, bands[cy]!);
      }
      return;
    }
    final list = all.toList()
      ..sort((a, b) {
        if (geometry.orientation == MapOrientation.isometric) {
          final d = (a.cx + a.cy).compareTo(b.cx + b.cy);
          if (d != 0) return d;
          return a.cx.compareTo(b.cx);
        }
        final d = a.cy.compareTo(b.cy);
        return d != 0 ? d : a.cx.compareTo(b.cx);
      });
    for (final c in list) {
      yield (TileChunkStore.keyOf(c.cx, c.cy), [c]);
    }
  }

  int _signature(List<TileChunkData> chunks, int layerId) {
    var s = Object.hash(
      runtime.assetsRevision,
      runtime.tilesetsRevision,
      runtime.base.revision,
      runtime.hiddenRevision,
    );
    for (final c in chunks) {
      s = Object.hash(s, identityHashCode(c), c.revision);
    }
    return s;
  }

  _Batch _build(
    List<TileChunkData> chunks,
    MapGeometry geometry,
    int layerId, {
    required bool ordered,
    required int signature,
  }) {
    final hidden = runtime.hiddenCells[layerId];
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
