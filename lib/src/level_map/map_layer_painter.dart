/// Drawing a map layer: its tiles in cached `drawRawAtlas` batches, culled
/// to the view.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show Material2DFile, Material2DKind;

import '../ecs/ecs.dart';
import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'level_map_data.dart';
import 'map_geometry.dart';
import 'level_map_runtime.dart';
import '../graphics/graphics_2d/materials/material_2d_batch.dart';
import '../graphics/graphics_2d/materials/material_2d_library.dart';
import '../graphics/graphics_2d/materials/materials_2d_context.dart';
import '../graphics/graphics_2d/lighting/lighting_2d_item.dart';
import '../rendering/render_items_component.dart';

/// One map layer's tiles, as one of the level's things to draw: it sorts
/// among sprites and shapes by the layer's own sort layer and z-order, and
/// the entities on the layer draw just after it. 2-D lighting draws its
/// normals and, when it casts shadows, its silhouette.
class MapLayerRenderItem extends RenderItem implements Lighting2DItem {
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

  @override
  bool paintNormals(
    Canvas canvas,
    RenderContext context,
    Entity owner, {
    required bool flat,
  }) =>
      runtime.painter.paintNormals(canvas, context, owner, layerId, flat: flat);

  @override
  bool paintSilhouette(Canvas canvas, RenderContext context, Entity owner) =>
      runtime.painter.paintSilhouette(canvas, context, owner, layerId);
}

/// A run of tiles drawn with one call: same tileset, same side of the
/// mirror.
class _Run {
  _Run(this.slot, this.mirrored, {bool trackX = false})
    : _x = trackX ? Int32List(16) : null;

  final int slot;
  final bool mirrored;

  // Filled while building: four floats a tile, grown as needed.
  Float32List _t = Float32List(64);
  Float32List _r = Float32List(64);
  Int32List? _x;

  /// Each tile's atlas transform, four floats a tile; fixed by [finish].
  Float32List transforms = Float32List(0);

  /// Each tile's source rectangle, four floats a tile; fixed by [finish].
  Float32List rects = Float32List(0);

  /// Each tile's cell x, in a run of a staggered or hexagonal band — what
  /// its tiles are culled by as they are drawn; null in any other run.
  Int32List? xs;

  /// Where each stretch of [xs] that only grows starts, and past the last
  /// the run's length: a row of tiles, or half a row.
  Int32List? stretches;

  /// Animated tiles in this run: index, tile id, tile shown.
  final List<(int, int, int)> animated = [];

  /// The last few colour arrays asked for, by colour: the tinted, flat and
  /// shadow passes each ask for their own.
  final List<(int, Int32List)> _colors = [];

  /// How many tiles: counted while building, fixed by [finish].
  int length = 0;

  void add(double scos, double ssin, double tx, double ty, Rect src, int x) {
    final k = length * 4;
    if (k + 4 > _t.length) {
      _t = _grown(_t, k + 4);
      _r = _grown(_r, k + 4);
    }
    _t
      ..[k] = scos
      ..[k + 1] = ssin
      ..[k + 2] = tx
      ..[k + 3] = ty;
    _r
      ..[k] = src.left
      ..[k + 1] = src.top
      ..[k + 2] = src.right
      ..[k + 3] = src.bottom;
    var cellX = _x;
    if (cellX != null) {
      if (length >= cellX.length) {
        cellX = _x = Int32List(cellX.length * 2)..setRange(0, length, cellX);
      }
      cellX[length] = x;
    }
    length++;
  }

  static Float32List _grown(Float32List list, int need) {
    var size = list.length * 2;
    while (size < need) {
      size *= 2;
    }
    return Float32List(size)..setRange(0, list.length, list);
  }

  void finish() {
    transforms = _t.sublist(0, length * 4);
    rects = _r.sublist(0, length * 4);
    _t = Float32List(0);
    _r = Float32List(0);
    final cellX = _x;
    if (cellX == null) return;
    final xs = this.xs = cellX.sublist(0, length);
    final starts = <int>[0];
    for (var i = 1; i < length; i++) {
      if (xs[i] < xs[i - 1]) starts.add(i);
    }
    starts.add(length);
    stretches = Int32List.fromList(starts);
    _x = null;
  }

  Int32List colors(int argb) {
    for (final (color, list) in _colors) {
      if (color == argb) return list;
    }
    final list = Int32List(length)..fillRange(0, length, argb.toSigned(32));
    if (_colors.length >= 3) _colors.removeAt(0);
    _colors.add((argb, list));
    return list;
  }
}

/// The runs of one batch of a layer — see [_Layout] — and what they were
/// built from.
class _Batch {
  _Batch(this.signature, this.runs, {required this.complete});
  final int signature;
  final List<_Run> runs;

  /// False when a tileset or image was still loading: build again.
  final bool complete;
  int shownMs = -1;

  /// Bumped whenever an animated tile moves on to another frame.
  int version = 0;
}

/// How a layer is cut into batches, each built once and drawn as long as
/// what it was built from stays the same.
enum _Layout {
  /// A chunk each, its tiles by tileset: orthogonal tiles that stay in
  /// their cells.
  chunks,

  /// A chunk each, back to front, the chunks diagonal by diagonal:
  /// isometric tiles no wider than a cell.
  isoChunks,

  /// A band per row of chunks in view, row by row across them, as Tiled
  /// draws: orthogonal tiles that reach out of their cells, so a tall tile
  /// overlaps the row behind it across chunks.
  rows,

  /// A band per sixteen diagonals of cells (x + y), back to front across
  /// the chunks in view: isometric tiles wider than a cell, which overlap
  /// their neighbours across chunks.
  isoBands,

  /// A band per whole row of chunks, back to front, drawn only where in
  /// view: staggered and hexagonal maps, whose rows overlap across chunk
  /// boundaries.
  wholeRows,
}

/// What one [MapLayerPainter.paint] call draws with, handed from batch to
/// batch.
class _Draw {
  _Draw(
    this.canvas,
    this.batches,
    this.geometry,
    this.layerId, {
    required this.layout,
    required this.assets,
    required this.color,
    this.material = '',
    this.materialFile,
    this.time = 0,
    this.mode = _Mode.color,
    this.normalImage,
    this.flatColor = Lighting2DItem.flatNormal,
    this.spanX0,
    this.spanX1,
  });

  final Canvas canvas;
  final Map<int, _Batch> batches;
  final MapGeometry geometry;
  final int layerId;
  final _Layout layout;

  /// The signature of what every batch is built from besides its chunks.
  final int assets;
  final int? color;

  /// The layer's 2-D material, by path, and as read; its tiles are queued
  /// into the layer's material batch instead of drawn as they are.
  final String material;
  final Material2DFile? materialFile;

  /// Seconds into the game, for the material's moving effects.
  final double time;

  /// What is drawn: the tiles, their normals, or their shape flat.
  final _Mode mode;

  /// [_Mode.normals]: the layer's normal map, once read.
  final ui.Image? normalImage;

  /// [_Mode.flat]: the colour every tile is drawn.
  final int flatColor;

  /// [_Layout.wholeRows] seen by a camera: the cells, left edge inclusive
  /// and right exclusive, along x whose tiles are drawn.
  final int? spanX0, spanX1;
}

/// What a [MapLayerPainter] draws a layer as.
enum _Mode {
  /// Its tiles.
  color,

  /// Its tiles' normals, for 2-D lighting, through its material.
  normals,

  /// Its tiles' shape as a flat normal.
  flat,
}

/// One layer's drawing through its 2-D material: the batch it is queued
/// in, and what it made, kept to draw again while nothing in it changes.
class _MaterialPass {
  _MaterialPass(Material2DLibrary library) : batch = Material2DBatch(library);

  final Material2DBatch batch;

  /// What the tiles were made into, in order.
  final List<Material2DDraw> draws = [];

  /// What [draws] were made from.
  final List<Object?> key = [];

  /// Lets go of [draws]: they are made again on the next paint.
  void forget() {
    for (final d in draws) {
      batch.release(d);
    }
    draws.clear();
    key.clear();
  }

  void dispose() {
    forget();
    batch.dispose();
  }
}

/// What the painter keeps for one layer.
class _LayerState {
  /// The batches, by key: a chunk's ([TileChunkStore.keyOf]), a row's or a
  /// band's number.
  final Map<int, _Batch> batches = {};

  /// How [batches] cut the layer.
  _Layout? layout;

  /// The tileset slots the layer's cells use, and the cells and revision
  /// they were found in.
  final Set<int> slots = {};
  TileChunkStore? slotsOf;
  int slotsRevision = -1;

  /// Drawn through its 2-D material: the tiles, and their normals.
  _MaterialPass? color, normals;

  void dispose() {
    color?.dispose();
    normals?.dispose();
    color = normals = null;
    batches.clear();
  }
}

/// Draws a map's layers.
///
/// A layer is cut into batches — see [_Layout]: a chunk each where tiles
/// stay in their cells, bands across chunks where tiles overlap their
/// neighbours (tall or wide tiles, staggered and hexagonal rows) — and
/// each batch is built once into `drawRawAtlas` buffers, then drawn every
/// frame for as long as its cells, hidden cells, tilesets and images stay
/// the same. Only batches in view are drawn. A layer drawn through a 2-D
/// material keeps what its tiles were made into, too, and draws it again
/// with only the time moved on.
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

  final Map<int, _LayerState> _layers = {};

  /// The map's revision when layers it no longer has were last let go of.
  int _prunedAt = -1;

  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  // Reused from paint to paint: the chunks in view, one batch's chunks,
  // the batches to draw, a material key, culled spans, and the cells of
  // a batch being built.
  final List<TileChunkData> _found = [];
  final List<TileChunkData> _group = [];
  final List<_Batch> _visible = [];
  final List<Object?> _key = [];
  final List<int> _ranges = [];
  Float32List _spanT = Float32List(0), _spanR = Float32List(0);
  final List<int> _cellX = [], _cellY = [], _cellV = [];

  /// Draws layer [layerId] of the map on [owner] — whose position is the
  /// map's origin — onto [canvas], with the layer's offset, parallax,
  /// opacity and tint. Only batches in [context]'s camera view are drawn
  /// (all of them without a camera), each rebuilt first if its cells,
  /// tilesets or images have changed. A layer the map no longer has draws
  /// nothing.
  void paint(Canvas canvas, RenderContext context, Entity owner, int layerId) =>
      _paintLayer(canvas, context, owner, layerId, _Mode.color);

  /// Draws layer [layerId]'s normals, for 2-D lighting, as [paint] draws its
  /// tiles: through its 2-D material's normal map when it has one (or is
  /// emissive), and true; else flat when [flat] — something shaded was drawn
  /// under it, which it must hide — or not at all, false.
  bool paintNormals(
    Canvas canvas,
    RenderContext context,
    Entity owner,
    int layerId, {
    required bool flat,
  }) {
    final layer = runtime.base.layerById(layerId);
    if (layer == null) return false;
    var shaded = false;
    if (layer.material.isNotEmpty) {
      final library = context.world.context.material2DLibrary;
      final file = library.fileOf(layer.material);
      shaded =
          library.normalsProgram != null &&
          file != null &&
          file.kind == Material2DKind.sprite &&
          (file.isOn('normalMap') || file.isOn('emissive'));
    }
    if (!shaded && !flat) return false;
    _paintLayer(
      canvas,
      context,
      owner,
      layerId,
      shaded ? _Mode.normals : _Mode.flat,
    );
    return shaded;
  }

  /// Draws layer [layerId]'s tiles as what casts shadows — for 2-D
  /// lighting's mask, coloured by [Lighting2DItem.casterColor] of its
  /// shadow depth — when the layer casts shadows
  /// ([MapLayerData.castShadows]), and true; else nothing, and false.
  bool paintSilhouette(
    Canvas canvas,
    RenderContext context,
    Entity owner,
    int layerId,
  ) {
    final layer = runtime.base.layerById(layerId);
    if (layer == null || !layer.castShadows) return false;
    _paintLayer(
      canvas,
      context,
      owner,
      layerId,
      _Mode.flat,
      flatColor: Lighting2DItem.casterColor(layer.shadowDepth),
    );
    return true;
  }

  /// Lets go of everything the drawing holds: the batches, and what the
  /// layers drawn through a 2-D material made — images and shaders. Called
  /// when the runtime is disposed; a painter disposed is not drawn with
  /// again.
  void dispose() {
    for (final state in _layers.values) {
      state.dispose();
    }
    _layers.clear();
  }

  /// Lets go of the layers the map no longer has.
  void _prune() {
    final revision = runtime.base.revision;
    if (_prunedAt == revision) return;
    _prunedAt = revision;
    _layers.removeWhere((id, state) {
      if (runtime.base.layerById(id) != null) return false;
      state.dispose();
      return true;
    });
  }

  void _paintLayer(
    Canvas canvas,
    RenderContext context,
    Entity owner,
    int layerId,
    _Mode mode, {
    int flatColor = Lighting2DItem.flatNormal,
  }) {
    final layer = runtime.base.layerById(layerId);
    if (layer == null) return;
    _prune();
    final state = _layers.putIfAbsent(layerId, _LayerState.new);
    final p = owner.getComponent<TransformComponent>()?.position;
    final origin = p == null ? Offset.zero : Offset(p.x, p.y);
    var shift = origin + Offset(layer.offsetX, layer.offsetY);
    final camera = context.camera;
    if (camera != null && (layer.parallaxX != 1 || layer.parallaxY != 1)) {
      // A distant layer lags behind the camera: measured from the map's
      // parallax origin, so it is where it was placed when the camera looks
      // at that point.
      final map = runtime.base;
      final rel =
          camera.position -
          origin -
          Offset(map.parallaxOriginX, map.parallaxOriginY);
      shift += Offset(
        rel.dx * (1 - layer.parallaxX),
        rel.dy * (1 - layer.parallaxY),
      );
    }

    final geometry = runtime.geometry;
    // In the layer's own pixels, widened by as far as a tile's image can
    // reach out of its cell: the largest tile, moved by its tileset's
    // offset.
    Rect? view;
    if (camera != null) {
      var reach = math.max(geometry.tileWidth, geometry.tileHeight).toDouble();
      for (final ts in runtime.tilesets) {
        if (ts == null) continue;
        final size = math.max(ts.tileWidth, ts.tileHeight).toDouble();
        final moved = math.max(ts.tileOffsetX.abs(), ts.tileOffsetY.abs());
        reach = math.max(reach, size + moved);
      }
      view = camera.visibleBounds.shift(-shift).inflate(reach);
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

    // A layer drawn through a 2-D material: its tiles are queued into the
    // material's batch, once the file is read and the shader loaded.
    final normals = mode == _Mode.normals;
    Material2DLibrary? library;
    ui.FragmentProgram? program;
    Material2DFile? materialFile;
    _MaterialPass? pass;
    ui.Image? normalImage;
    if (layer.material.isNotEmpty && mode != _Mode.flat) {
      library = context.world.context.material2DLibrary;
      final file = library.fileOf(layer.material);
      program = normals ? library.normalsProgram : library.program;
      if (program != null &&
          file != null &&
          file.kind == Material2DKind.sprite) {
        materialFile = file;
        pass = normals
            ? state.normals ??= _MaterialPass(library)
            : state.color ??= _MaterialPass(library);
        pass.batch.beginFrame();
        if (normals && file.isOn('normalMap')) {
          normalImage = library.imageOf(file.text('normalMap.map'));
        }
      }
    }
    if (pass == null && mode != _Mode.flat) {
      // Not drawn through a material (any more): what it made goes.
      if (normals) {
        state.normals?.dispose();
        state.normals = null;
      } else {
        state.color?.dispose();
        state.color = null;
      }
    }

    final cells = runtime.cellsOf(layer);
    final bounds = cells.chunkBounds;
    if (bounds == null) return;
    final layout = switch (geometry.orientation) {
      LevelMapOrientation.staggered ||
      LevelMapOrientation.hexagonal => _Layout.wholeRows,
      LevelMapOrientation.isometric =>
        _tilesOverlap(geometry, _slotsOf(state, cells), iso: true)
            ? _Layout.isoBands
            : _Layout.isoChunks,
      LevelMapOrientation.orthogonal =>
        _tilesOverlap(geometry, _slotsOf(state, cells), iso: false)
            ? _Layout.rows
            : _Layout.chunks,
    };
    if (state.layout != layout) {
      state.batches.clear();
      state.layout = layout;
    }

    // The chunks to walk: those in view, among those there are. A whole
    // row of a staggered or hexagonal map is one batch, so only rows are
    // culled by chunk; its tiles are culled as they are drawn.
    var cx0 = bounds.cx0, cy0 = bounds.cy0;
    var cx1 = bounds.cx1, cy1 = bounds.cy1;
    int? spanX0, spanX1;
    if (view != null) {
      final r = geometry.cellRange(view);
      cy0 = math.max(cy0, TileChunkStore.chunkIndexOf(r.y0));
      cy1 = math.min(cy1, TileChunkStore.chunkIndexOf(r.y1 - 1) + 1);
      if (layout == _Layout.wholeRows) {
        spanX0 = r.x0;
        spanX1 = r.x1;
      } else {
        cx0 = math.max(cx0, TileChunkStore.chunkIndexOf(r.x0));
        cx1 = math.min(cx1, TileChunkStore.chunkIndexOf(r.x1 - 1) + 1);
      }
    }
    if (cx1 <= cx0 || cy1 <= cy0) return;

    final draw = _Draw(
      canvas,
      state.batches,
      geometry,
      layerId,
      layout: layout,
      assets: Object.hash(
        runtime.assetsRevision,
        runtime.tilesetsRevision,
        runtime.base.revision,
        layout,
      ),
      color: color,
      material: layer.material,
      materialFile: materialFile,
      time: context.time,
      mode: mode,
      normalImage: normalImage,
      flatColor: flatColor,
      spanX0: spanX0,
      spanX1: spanX1,
    );

    _visible.clear();
    _collect(draw, cells, cx0, cy0, cx1, cy1);
    canvas.save();
    canvas.translate(shift.dx, shift.dy);
    if (pass != null) {
      _drawMaterial(draw, pass, library!, program!);
    } else {
      for (final batch in _visible) {
        _drawBatch(draw, batch);
      }
    }
    canvas.restore();
    _visible.clear();
    _group.clear();
    _found.clear();
  }

  /// The tileset slots [cells] use, counted again only when they change.
  Set<int> _slotsOf(_LayerState state, TileChunkStore cells) {
    var revision = 0;
    for (TileChunkStore? s = cells; s != null; s = s.base) {
      revision += s.revision;
    }
    if (identical(state.slotsOf, cells) && state.slotsRevision == revision) {
      return state.slots;
    }
    state
      ..slotsOf = cells
      ..slotsRevision = revision;
    final slots = state.slots..clear();
    for (final chunk in cells.chunks) {
      for (final cell in chunk.cells) {
        if (!TileCell.isEmpty(cell)) slots.add(TileCell.slotOf(cell));
      }
    }
    return slots;
  }

  /// Whether a tile of the tilesets in [slots] can reach out of its cell on
  /// the grid [g] far enough to overlap a neighbour across chunks.
  ///
  /// Orthogonal ([iso] false): one bigger than a cell — either way round,
  /// since a tile can be turned a quarter — or moved by its tileset's
  /// offset. Isometric: one wider than a cell — a tall one only overlaps
  /// the diagonal behind it, which chunks drawn diagonal by diagonal
  /// already draw first — or moved.
  bool _tilesOverlap(MapGeometry g, Set<int> slots, {required bool iso}) {
    for (final slot in slots) {
      final ts = runtime.tilesetAt(slot);
      if (ts == null) continue;
      final w = ts.tileWidth, h = ts.tileHeight;
      if (ts.tileOffsetX != 0 || ts.tileOffsetY != 0) return true;
      if (iso) {
        if (w > g.tileWidth || (w != h && h > g.tileWidth)) return true;
      } else if (w > g.tileWidth ||
          h > g.tileHeight ||
          (w != h && (h > g.tileWidth || w > g.tileHeight))) {
        return true;
      }
    }
    return false;
  }

  static int _byRow(TileChunkData a, TileChunkData b) =>
      a.cy != b.cy ? a.cy.compareTo(b.cy) : a.cx.compareTo(b.cx);

  static int _byDiagonal(TileChunkData a, TileChunkData b) {
    final d = (a.cx + a.cy).compareTo(b.cx + b.cy);
    return d != 0 ? d : a.cx.compareTo(b.cx);
  }

  /// Finds the batches of the chunks in [cx0]..[cx1] × [cy0]..[cy1] (far
  /// edges exclusive), in draw order, into [_visible] — each built or
  /// brought up to date first.
  void _collect(
    _Draw draw,
    TileChunkStore cells,
    int cx0,
    int cy0,
    int cx1,
    int cy1,
  ) {
    final diagonal =
        draw.layout == _Layout.isoChunks || draw.layout == _Layout.isoBands;
    final found = _found..clear();
    if ((cx1 - cx0) * (cy1 - cy0) > cells.chunkCount * 4 + 64) {
      // A few chunks spread far apart: go through those there are rather
      // than look each place in the range up.
      for (final c in cells.chunks) {
        if (c.cy >= cy0 && c.cy < cy1 && c.cx >= cx0 && c.cx < cx1) {
          found.add(c);
        }
      }
      found.sort(diagonal ? _byDiagonal : _byRow);
    } else if (diagonal) {
      // Diagonal by diagonal (cx + cy), each left to right: back to front.
      for (var d = cx0 + cy0; d <= cx1 + cy1 - 2; d++) {
        final from = math.max(cx0, d - cy1 + 1);
        final to = math.min(cx1 - 1, d - cy0);
        for (var cx = from; cx <= to; cx++) {
          final c = cells.chunk(cx, d - cx);
          if (c != null) found.add(c);
        }
      }
    } else {
      // Row by row, each left to right.
      for (var cy = cy0; cy < cy1; cy++) {
        for (var cx = cx0; cx < cx1; cx++) {
          final c = cells.chunk(cx, cy);
          if (c != null) found.add(c);
        }
      }
    }

    final group = _group;
    switch (draw.layout) {
      case _Layout.chunks:
      case _Layout.isoChunks:
        for (final c in found) {
          group
            ..clear()
            ..add(c);
          _addBatch(draw, TileChunkStore.keyOf(c.cx, c.cy), group);
        }
      case _Layout.rows:
      case _Layout.wholeRows:
        var i = 0;
        while (i < found.length) {
          final cy = found[i].cy;
          group.clear();
          while (i < found.length && found[i].cy == cy) {
            group.add(found[i++]);
          }
          _addBatch(draw, cy, group);
        }
      case _Layout.isoBands:
        // Band k holds the tiles whose x + y is 16k to 16k + 15: the far
        // half of diagonal k - 1's chunks, and the near half of diagonal
        // k's. Found diagonal by diagonal, each a stretch of [found].
        var i = 0;
        // Where the diagonal before this one starts in [found], if any.
        var last = -1;
        while (i < found.length) {
          final d = found[i].cx + found[i].cy;
          final from = i;
          while (i < found.length && found[i].cx + found[i].cy == d) {
            i++;
          }
          group.clear();
          if (last >= 0 && found[last].cx + found[last].cy == d - 1) {
            group.addAll(found.getRange(last, from));
          }
          group.addAll(found.getRange(from, i));
          _addBatch(draw, d, group, band: d);
          // Band d + 1 now, unless diagonal d + 1 has chunks of its own and
          // draws it.
          if (i >= found.length || found[i].cx + found[i].cy != d + 1) {
            group
              ..clear()
              ..addAll(found.getRange(from, i));
            _addBatch(draw, d + 1, group, band: d + 1);
          }
          last = from;
        }
    }
  }

  /// Adds the batch [key] made of [chunks] to [_visible], built again
  /// first if they, their hidden cells, or the tilesets and images have
  /// changed since it was.
  void _addBatch(
    _Draw draw,
    int key,
    List<TileChunkData> chunks, {
    int band = 0,
  }) {
    var signature = draw.assets;
    for (final c in chunks) {
      signature = Object.hash(
        signature,
        identityHashCode(c),
        c.revision,
        runtime.hiddenRevisionOf(draw.layerId, c.cx, c.cy),
      );
    }
    var batch = draw.batches[key];
    if (batch == null || batch.signature != signature || !batch.complete) {
      batch = _build(chunks, draw, signature: signature, band: band);
      draw.batches[key] = batch;
    }
    _animate(batch);
    _visible.add(batch);
  }

  /// Draws [batch]'s runs: of a whole row, only the tiles in view.
  void _drawBatch(_Draw draw, _Batch batch) {
    final flat = draw.mode == _Mode.flat;
    final color = flat ? draw.flatColor : draw.color;
    for (final run in batch.runs) {
      final image = run.mirrored
          ? runtime.mirroredAt(run.slot)
          : runtime.imageAt(run.slot);
      if (image == null || run.length == 0) continue;
      var transforms = run.transforms, rects = run.rects;
      var n = run.length;
      final x0 = draw.spanX0, x1 = draw.spanX1;
      if (x0 != null && x1 != null && run.xs != null) {
        n = _inView(run, x0, x1);
        if (n == 0) continue;
        if (n < run.length) {
          if (_spanT.length < n * 4) {
            _spanT = Float32List(n * 8);
            _spanR = Float32List(n * 8);
          }
          var at = 0;
          for (var i = 0; i < _ranges.length; i += 2) {
            final from = _ranges[i] * 4, to = _ranges[i + 1] * 4;
            _spanT.setRange(at, at + to - from, run.transforms, from);
            _spanR.setRange(at, at + to - from, run.rects, from);
            at += to - from;
          }
          transforms = Float32List.sublistView(_spanT, 0, n * 4);
          rects = Float32List.sublistView(_spanR, 0, n * 4);
        }
      }
      Int32List? colors;
      if (color != null) {
        final all = run.colors(color);
        colors = n == run.length ? all : Int32List.sublistView(all, 0, n);
      }
      draw.canvas.drawRawAtlas(
        image,
        transforms,
        rects,
        colors,
        color == null
            ? null
            : flat
            ? BlendMode.srcIn
            : BlendMode.modulate,
        null,
        _paint,
      );
    }
  }

  /// Puts into [_ranges] the stretches of [run] — from, to — whose tiles'
  /// cells lie in [x0]..[x1] (right exclusive), and returns how many tiles
  /// they hold.
  int _inView(_Run run, int x0, int x1) {
    final xs = run.xs!, stretches = run.stretches!;
    _ranges.clear();
    var n = 0;
    for (var s = 0; s + 1 < stretches.length; s++) {
      final end = stretches[s + 1];
      final from = _lowerBound(xs, x0, stretches[s], end);
      final to = _lowerBound(xs, x1, from, end);
      if (to <= from) continue;
      _ranges
        ..add(from)
        ..add(to);
      n += to - from;
    }
    return n;
  }

  /// The first index in [from]..[to] of [xs] (which only grows there) whose
  /// value is at least [x]; [to] when none is.
  static int _lowerBound(Int32List xs, int x, int from, int to) {
    var lo = from, hi = to;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (xs[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Draws [_visible] through the layer's 2-D material: what was made last
  /// time again, with only the time moved on, when nothing it was made
  /// from has changed; else queued and made again.
  void _drawMaterial(
    _Draw draw,
    _MaterialPass pass,
    Material2DLibrary library,
    ui.FragmentProgram program,
  ) {
    final key = _key
      ..clear()
      ..add(library.revision)
      ..add(draw.material)
      ..add(draw.materialFile)
      ..add(program)
      ..add(draw.normalImage)
      ..add(draw.color)
      ..add(runtime.assetsRevision)
      ..add(draw.spanX0)
      ..add(draw.spanX1);
    for (final batch in _visible) {
      key
        ..add(batch)
        ..add(batch.version);
    }
    final m = pass.batch;
    if (_sameKey(key, pass.key)) {
      for (final d in pass.draws) {
        m.redraw(draw.canvas, d, draw.time);
      }
      return;
    }
    pass.forget();
    for (final batch in _visible) {
      _queueMaterial(draw, pass, batch);
    }
    _cut(draw, pass);
    pass.key.addAll(key);
  }

  static bool _sameKey(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Makes what [pass] has queued into a draw, draws it and keeps it.
  void _cut(_Draw draw, _MaterialPass pass) {
    final made = pass.batch.take();
    if (made == null) return;
    pass.batch.redraw(draw.canvas, made, draw.time);
    pass.draws.add(made);
  }

  /// Queues [batch]'s tiles into the layer's material batch, in the order
  /// they would have been drawn; a run from another tileset image draws
  /// what is queued first. Of a whole row, only the tiles in view.
  void _queueMaterial(_Draw draw, _MaterialPass pass, _Batch batch) {
    final m = pass.batch;
    final file = draw.materialFile!;
    final color = draw.color ?? 0xFFFFFFFF;
    final rgb = color & 0xFFFFFF, alpha = (color >>> 24) & 0xFF;
    final normals = draw.mode == _Mode.normals;
    for (final run in batch.runs) {
      final image = run.mirrored
          ? runtime.mirroredAt(run.slot)
          : runtime.imageAt(run.slot);
      if (image == null || run.length == 0) continue;
      // Normals from the layer's normal map, over the tileset's image (and
      // repeated where it is smaller); a mirrored run's are flat.
      final normalMap = normals && !run.mirrored ? draw.normalImage : null;
      if (!m.isEmpty && !m.accepts(draw.material, image, FilterQuality.none)) {
        _cut(draw, pass);
      }
      if (m.isEmpty) {
        m.begin(
          draw.material,
          file,
          image,
          FilterQuality.none,
          normals: normals,
          normalMap: normalMap,
        );
      }
      final t = run.transforms, r = run.rects;
      // An atlas transform: the frame's pixel (u, v) is drawn at
      // (scos·u − ssin·v + tx, ssin·u + scos·v + ty).
      bool add(int i) {
        final k = i * 4;
        final scos = t[k], ssin = t[k + 1], tx = t[k + 2], ty = t[k + 3];
        return m.addFrame(
          Rect.fromLTRB(r[k], r[k + 1], r[k + 2], r[k + 3]),
          a: scos,
          b: ssin,
          c: -ssin,
          d: scos,
          e: tx,
          f: ty,
          rgb: rgb,
          alpha: alpha,
          x: tx,
          y: ty,
          seed: (tx.round() * 73856093) ^ (ty.round() * 19349663),
        );
      }

      final x0 = draw.spanX0, x1 = draw.spanX1;
      if (x0 != null && x1 != null && run.xs != null) {
        _inView(run, x0, x1);
      } else {
        _ranges
          ..clear()
          ..add(0)
          ..add(run.length);
      }
      for (var s = 0; s < _ranges.length; s += 2) {
        for (var i = _ranges[s]; i < _ranges[s + 1]; i++) {
          if (add(i)) continue;
          _cut(draw, pass);
          m.begin(
            draw.material,
            file,
            image,
            FilterQuality.none,
            normals: normals,
            normalMap: normalMap,
          );
          add(i);
        }
      }
    }
  }

  _Batch _build(
    List<TileChunkData> chunks,
    _Draw draw, {
    required int signature,
    required int band,
  }) {
    final geometry = draw.geometry;
    final layout = draw.layout;
    final layerId = draw.layerId;
    const size = TileChunkStore.size;
    final xs = _cellX..clear(), ys = _cellY..clear(), vs = _cellV..clear();
    if (layout == _Layout.rows) {
      // Row by row across the band's chunks, which are left to right, each
      // row left to right: back to front, with nothing to sort.
      final hidden = [
        for (final c in chunks) runtime.hiddenInChunk(layerId, c.cx, c.cy),
      ];
      for (var row = 0; row < size; row++) {
        for (var n = 0; n < chunks.length; n++) {
          final chunk = chunks[n];
          final h = hidden[n];
          final x0 = chunk.cx * size;
          final y = chunk.cy * size + row;
          for (var col = 0; col < size; col++) {
            final i = row * size + col;
            final cell = chunk.cells[i];
            if (TileCell.isEmpty(cell) || (h != null && h.contains(i))) {
              continue;
            }
            xs.add(x0 + col);
            ys.add(y);
            vs.add(cell);
          }
        }
      }
    } else {
      for (final chunk in chunks) {
        final h = runtime.hiddenInChunk(layerId, chunk.cx, chunk.cy);
        final x0 = chunk.cx * size;
        final y0 = chunk.cy * size;
        for (var i = 0; i < TileChunkStore.cellsPerChunk; i++) {
          final cell = chunk.cells[i];
          if (TileCell.isEmpty(cell) || (h != null && h.contains(i))) continue;
          final x = x0 + i % size;
          final y = y0 + i ~/ size;
          if (layout == _Layout.isoBands &&
              TileChunkStore.chunkIndexOf(x + y) != band) {
            continue;
          }
          xs.add(x);
          ys.add(y);
          vs.add(cell);
        }
      }
    }

    // Back to front on screen — by where each cell's centre is, top to
    // bottom then left to right (MapGeometry.compareDrawOrder) — worked out
    // once a tile, not once a comparison.
    final count = xs.length;
    List<int>? order;
    if (layout == _Layout.isoChunks ||
        layout == _Layout.isoBands ||
        layout == _Layout.wholeRows) {
      final byY = Float64List(count), byX = Float64List(count);
      for (var i = 0; i < count; i++) {
        final c = geometry.cellCenter(xs[i], ys[i]);
        byY[i] = c.dy;
        byX[i] = c.dx;
      }
      order = List<int>.generate(count, (i) => i)
        ..sort((a, b) {
          final d = byY[a].compareTo(byY[b]);
          return d != 0 ? d : byX[a].compareTo(byX[b]);
        });
    }

    final hex = geometry.orientation == LevelMapOrientation.hexagonal;
    final ordered = layout != _Layout.chunks;
    final trackX = layout == _Layout.wholeRows;
    var complete = true;
    final runs = <_Run>[];
    final bySlot = <int, _Run>{};
    _Run runFor(int slot, bool mirrored) {
      if (!ordered) {
        return bySlot.putIfAbsent(slot * 2 + (mirrored ? 1 : 0), () {
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
      final r = _Run(slot, mirrored, trackX: trackX);
      runs.add(r);
      return r;
    }

    for (var j = 0; j < count; j++) {
      final e = order == null ? j : order[j];
      final x = xs[e], y = ys[e], cell = vs[e];
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
      final cx = dest.left + dest.width / 2;
      final cy = dest.top + dest.height / 2;
      final run = runFor(slot, mirrored);
      final animated = def?.isAnimated ?? false;
      final shown = animated ? def!.frameAt(id, runtime.animationMs) : id;
      run.add(
        scos,
        ssin,
        cx - scos * ax + ssin * ay,
        cy - ssin * ax - scos * ay,
        _source(slot, shown, mirrored),
        x,
      );
      if (animated) run.animated.add((run.length - 1, id, shown));
    }
    for (final r in runs) {
      r.finish();
    }
    xs.clear();
    ys.clear();
    vs.clear();
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
        batch.version++;
      }
    }
  }
}
