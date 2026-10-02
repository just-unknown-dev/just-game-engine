/// A level map as the running game holds it, and the API to read and change
/// it.
library;

import 'dart:async';
import 'dart:collection' show UnmodifiableMapView, UnmodifiableSetView;
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import '../../ecs/base/engine_context.dart';
import 'render/map_layer_painter.dart';
import 'tile_assets.dart';
import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'level_map_data.dart';
import 'map_geometry.dart';
import 'tileset_data.dart';
import 'wang/wang_filler.dart';

/// Fired when the running game changes a tile.
class TileChangedEvent extends GameEvent {
  /// A change to [cells] of layer [layerId] of the map on [map].
  TileChangedEvent({
    required this.map,
    required this.layerId,
    required this.cells,
  });

  /// The entity carrying the map.
  final Entity map;

  /// The changed layer, by its id within the map ([MapLayerData.id]).
  final int layerId;

  /// What changed: cell → new value.
  final Map<TileCoord, int> cells;
}

/// What the running game made of one map: the document it reads, its own
/// changes on top, the tilesets and images it loaded, and its drawing.
///
/// The document ([base]) is never written by the game. For a map file it is
/// shared with every other map made from that file; in the editor it is the
/// document being edited. A game's changes — [LevelMapHandle.setTile] — land
/// in copy-on-write overlays per layer, which go when the runtime does.
class LevelMapRuntime {
  /// A runtime for [base], made from [source], loading its tilesets and
  /// images through [context] (`tiles`, `sprites`).
  LevelMapRuntime({
    required this.base,
    required this.source,
    required this.context,
  });

  /// Where its tilesets and images come from.
  final EngineContext context;

  /// The map document.
  final LevelMapData base;

  /// What it was made for: the inline map object, or the file path.
  final Object source;

  final Map<int, TileChunkStore> _overlays = {};

  /// Tilesets by slot, once loaded.
  final List<TilesetData?> tilesets = [];
  final List<ui.Image?> _images = [];
  final Map<int, ui.Image> _mirrored = {};

  /// Bumped whenever tilesets or images change, for the drawing to redo.
  int assetsRevision = 0;

  /// Whether every tileset has loaded — all collision needs.
  bool tilesetsReady = false;

  int _loadedAssetsRevision = -1;
  List<String?> _loadedPaths = const [];
  Future<void>? _loading;

  /// Which load of tilesets and images is the latest: one started earlier
  /// that finishes later is dropped, not applied over it.
  int _loadGeneration = 0;

  bool _disposed = false;

  /// Layers whose collision must be rebuilt.
  final Set<int> collisionDirty = {};

  final Map<int, Set<TileCoord>> _hiddenCells = {};

  /// Cells not drawn, by layer — a crumbled block, say. A read-only copy
  /// of the map (its sets are views): change it through
  /// [LevelMapHandle.setCellsHidden], which also bumps [hiddenRevision].
  Map<int, Set<TileCoord>> get hiddenCells => UnmodifiableMapView({
    for (final MapEntry(:key, :value) in _hiddenCells.entries)
      key: UnmodifiableSetView(value),
  });

  /// The cells of layer [layerId] not drawn, read-only; null when none of
  /// its cells ever were hidden.
  Set<TileCoord>? hiddenCellsOf(int layerId) {
    final cells = _hiddenCells[layerId];
    return cells == null ? null : UnmodifiableSetView(cells);
  }

  int _hiddenRevision = 0;

  /// Bumped whenever [hiddenCells] changes, so the drawing is rebuilt.
  int get hiddenRevision => _hiddenRevision;

  /// An editor's view: layers faded (below 1) or hidden entirely. Not part
  /// of the map.
  final Map<int, double> layerAlpha = {};

  /// Where animated tiles are, in milliseconds.
  int animationMs = 0;

  late MapGeometry _geometry = MapGeometry.of(base);
  int _geometryRevision = -1;

  /// The map's grid, kept up to date with its settings.
  MapGeometry get geometry {
    if (_geometryRevision != base.revision) {
      _geometry = MapGeometry.of(base);
      _geometryRevision = base.revision;
    }
    return _geometry;
  }

  MapLayerPainter? _painter;

  /// Draws the layers.
  MapLayerPainter get painter => _painter ??= MapLayerPainter(this);

  /// [layer]'s cells as the game sees them: the document's, with the
  /// game's changes on top.
  TileChunkStore cellsOf(MapLayerData layer) =>
      _overlays[layer.id] ?? layer.cells;

  /// [layer]'s cells for writing: an overlay, made on first write.
  TileChunkStore writableCells(MapLayerData layer) =>
      _overlays.putIfAbsent(layer.id, () => TileChunkStore.over(layer.cells));

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Lets go of what this runtime made: the mirrored tileset images (GPU
  /// memory) and the drawing's cached batches. Loads still in flight are
  /// dropped when they finish. Called by whoever drops the runtime — the
  /// `LevelMapSystem` when a map is replaced, cleared or leaves the world,
  /// and [LevelMaps.release].
  ///
  /// A disposed runtime loads nothing more and draws no mirrored tiles; a
  /// map that is still wanted gets a new one.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    _loading = null;
    _disposeMirrored();
    _painter = null;
  }

  void _disposeMirrored() {
    for (final image in _mirrored.values) {
      image.dispose();
    }
    _mirrored.clear();
  }

  /// The tileset in [slot], if loaded.
  TilesetData? tilesetAt(int slot) =>
      slot >= 0 && slot < tilesets.length ? tilesets[slot] : null;

  /// The image of the tileset in [slot], if loaded.
  ui.Image? imageAt(int slot) =>
      slot >= 0 && slot < _images.length ? _images[slot] : null;

  /// The image of [slot] mirrored left to right, made the first time a
  /// mirrored tile needs it. Tiles are drawn with `drawRawAtlas`, whose
  /// transforms can turn and scale but not mirror.
  ui.Image? mirroredAt(int slot) {
    final cached = _mirrored[slot];
    if (cached != null) return cached;
    if (_disposed) return null;
    final image = imageAt(slot);
    if (image == null) return null;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(image.width.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final mirrored = picture.toImageSync(image.width, image.height);
    picture.dispose();
    return _mirrored[slot] = mirrored;
  }

  /// Loads whatever tilesets and images are missing or out of date. Safe to
  /// call every frame; returns the load in progress, which never fails: a
  /// tileset that will not load leaves its tiles undrawn and uncollidable,
  /// an image its tiles undrawn, and either is reported once through
  /// [TileAssets.log].
  Future<void> syncAssets() {
    if (_disposed) return Future.value();
    final tiles = context.tiles;
    final changed =
        _loadedAssetsRevision != tiles.revision ||
        !_samePaths(_loadedPaths, base.tilesets);
    if (!changed) return _loading ?? Future.value();
    _loadedAssetsRevision = tiles.revision;
    final paths = _loadedPaths = [...base.tilesets];
    final generation = ++_loadGeneration;
    // Tilesets already in memory are taken at once, so a map whose tilesets
    // are loaded collides in the very frame it appears.
    final ready = [
      for (final p in paths) p == null ? null : tiles.loadedTileset(p),
    ];
    var allReady = true;
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != null && ready[i] == null) allReady = false;
    }
    if (allReady) {
      _applyTilesets(ready);
      return _loading = _loadImages(generation, ready);
    }
    return _loading = _load(generation, paths);
  }

  void _applyTilesets(List<TilesetData?> sets) {
    tilesets
      ..clear()
      ..addAll(sets);
    tilesetsReady = true;
    collisionDirty.addAll(base.layers.map((l) => l.id));
    assetsRevision++;
  }

  static bool _samePaths(List<String?> a, List<String?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _load(int generation, List<String?> paths) async {
    final sets = <TilesetData?>[];
    for (final path in paths) {
      try {
        sets.add(path == null ? null : await context.tiles.tileset(path));
      } catch (_) {
        // A tileset that will not load leaves its tiles undrawn and
        // uncollidable; TileAssets has reported it, and the editor's
        // validator says which.
        sets.add(null);
      }
    }
    // Superseded — a later load started, or the runtime was disposed.
    if (generation != _loadGeneration) return;
    _applyTilesets(sets);
    await _loadImages(generation, sets);
  }

  Future<void> _loadImages(int generation, List<TilesetData?> sets) async {
    final images = <ui.Image?>[];
    for (final ts in sets) {
      if (ts == null || ts.image.isEmpty) {
        images.add(null);
        continue;
      }
      try {
        images.add(
          context.tiles.builtInImage(ts.image) ??
              await context.sprites.loadImage(ts.image),
        );
      } catch (error) {
        // Its tiles are not drawn; they still collide.
        context.tiles.report(ts.image, error, what: 'tileset image');
        images.add(null);
      }
    }
    if (generation != _loadGeneration) return;
    _images
      ..clear()
      ..addAll(images);
    _disposeMirrored();
    assetsRevision++;
  }

  /// The combined revision of the tilesets in use: bumps when one is edited
  /// in place.
  int get tilesetsRevision {
    var sum = 0;
    for (final ts in tilesets) {
      sum = sum * 31 + (ts?.revision ?? 0);
    }
    return sum;
  }
}

/// A tile, with what its tileset says about it.
class TileInfo {
  /// Tile [localId] of [tileset], found in a cell holding [cell]; [def] is
  /// what the tileset says about it, null when nothing.
  const TileInfo({
    required this.cell,
    required this.tileset,
    required this.localId,
    this.def,
  });

  /// The cell's value.
  final int cell;

  /// The loaded tileset the tile is from.
  final TilesetData tileset;

  /// The tile's id within [tileset].
  final int localId;

  /// What the tileset says about the tile, if anything.
  final TileDef? def;

  /// The tile's class, from its tileset; empty when it has none.
  String get className => def?.className ?? '';

  /// The tile's properties; empty when it has none.
  Map<String, Object?> get properties => {
    for (final name in def?.properties.names ?? const <String>[])
      name: def!.properties[name],
  };

  /// Whether the cell shows the tile mirrored left to right.
  bool get isFlippedH => TileCell.isFlippedH(cell);

  /// Whether the cell shows the tile mirrored top to bottom.
  bool get isFlippedV => TileCell.isFlippedV(cell);

  /// Whether the cell shows the tile mirrored across its diagonal (turned
  /// 60° on a hexagonal map).
  bool get isFlippedD => TileCell.isFlippedD(cell);
}

/// Reading and changing a map while the game runs.
///
/// ```dart
/// final map = LevelMaps.of(world, levelEntity)!;
/// final ground = map.layer('Ground')!;
/// final c = map.cellAt(ground, player.position);
/// if (map.tileAt(ground, c)?.className == 'Breakable') {
///   map.setTile(ground, c, TileCell.empty);
/// }
/// ```
///
/// Changes are the running game's own: the map file, or the scene's saved
/// map, is not touched. Collision follows a change within the frame.
class LevelMapHandle {
  LevelMapHandle._(this.world, this.entity, this.component, this.runtime);

  /// The world the map is in; [setTiles] fires its [TileChangedEvent]s
  /// there.
  final World world;

  /// The entity carrying the map.
  final Entity entity;

  /// The entity's map component.
  final LevelMapComponent component;

  /// The running game's map: the document, the game's changes on top.
  final LevelMapRuntime runtime;

  /// The map document: grid, tilesets, layers. Its cells are as loaded,
  /// without the game's changes — read those through [rawAt] or [tileAt].
  LevelMapData get map => runtime.base;

  /// The map's grid: where its cells are, in map-local pixels.
  MapGeometry get geometry => runtime.geometry;

  /// The map's origin in the world: its entity's position.
  ui.Offset get origin {
    final p = entity.getComponent<TransformComponent>()?.position;
    return p == null ? ui.Offset.zero : ui.Offset(p.x, p.y);
  }

  /// The layer with [idOrName] — an int id or a name.
  MapLayerData? layer(Object idOrName) {
    for (final l in map.layers) {
      if (l.id == idOrName || l.name == idOrName) return l;
    }
    return null;
  }

  /// [worldPoint] turned into [layer]'s own pixels.
  ui.Offset toLocal(MapLayerData layer, ui.Offset worldPoint) =>
      worldPoint - origin - ui.Offset(layer.offsetX, layer.offsetY);

  /// The cell of [layer] under [worldPoint].
  TileCoord cellAt(MapLayerData layer, ui.Offset worldPoint) =>
      geometry.cellAt(toLocal(layer, worldPoint));

  /// The centre of [layer]'s cell [c], in the world.
  ui.Offset cellCenter(MapLayerData layer, TileCoord c) =>
      geometry.cellCenter(c.x, c.y) +
      origin +
      ui.Offset(layer.offsetX, layer.offsetY);

  /// The raw value of [layer]'s cell [c].
  int rawAt(MapLayerData layer, TileCoord c) =>
      runtime.cellsOf(layer).cellAt(c.x, c.y);

  /// The tile at [layer]'s cell [c], or null for an empty cell.
  TileInfo? tileAt(MapLayerData layer, TileCoord c) {
    final cell = rawAt(layer, c);
    if (TileCell.isEmpty(cell)) return null;
    final ts = runtime.tilesetAt(TileCell.slotOf(cell));
    if (ts == null) return null;
    final id = TileCell.localIdOf(cell);
    return TileInfo(cell: cell, tileset: ts, localId: id, def: ts.tile(id));
  }

  /// The tile under [worldPoint] on [layer].
  TileInfo? tileAtPoint(MapLayerData layer, ui.Offset worldPoint) =>
      tileAt(layer, cellAt(layer, worldPoint));

  /// Sets [layer]'s cell [c] to [cell]. Returns whether it changed.
  bool setTile(MapLayerData layer, TileCoord c, int cell) =>
      setTiles(layer, {c: cell}) > 0;

  /// Sets several cells at once — one event, one collision rebuild.
  /// Returns how many changed.
  int setTiles(MapLayerData layer, Map<TileCoord, int> cells) {
    final store = runtime.writableCells(layer);
    final changed = <TileCoord, int>{};
    cells.forEach((c, value) {
      if (store.setCell(c.x, c.y, value)) changed[c] = value;
    });
    if (changed.isEmpty) return 0;
    if (layer.collides) runtime.collisionDirty.add(layer.id);
    world.events.fire(
      TileChangedEvent(map: entity, layerId: layer.id, cells: changed),
    );
    return changed.length;
  }

  /// Paints terrain [color] of Wang set [wangSet] of the tileset in [slot]
  /// at [targets], choosing tiles as the editor's terrain brush does.
  WangResult setTerrain(
    MapLayerData layer,
    Iterable<WangTarget> targets,
    int color, {
    int slot = 0,
    int wangSet = 0,
    math.Random? random,
  }) {
    final ts = runtime.tilesetAt(slot);
    if (ts == null || wangSet >= ts.wangSets.length) {
      return const WangResult({}, {});
    }
    final result = WangFiller(
      set: ts.wangSets[wangSet],
      tileset: ts,
      slot: slot,
      geometry: geometry,
      random: random,
    ).paint(runtime.cellsOf(layer), targets, color);
    setTiles(layer, result.changes);
    return result;
  }

  /// Stops drawing the cells [body] was built from — or starts again. A
  /// crumbling platform, gone and back.
  void setBodyHidden(MapBodyComponent body, bool hidden) {
    final l = layer(body.layerId);
    if (l != null) setCellsHidden(l, body.cells, hidden);
  }

  /// Stops drawing [cells] of [layer] — or starts again — without changing
  /// what is in them.
  void setCellsHidden(
    MapLayerData layer,
    Iterable<TileCoord> cells,
    bool hidden,
  ) {
    final set = runtime._hiddenCells.putIfAbsent(layer.id, () => {});
    final before = set.length;
    if (hidden) {
      set.addAll(cells);
    } else {
      set.removeAll(cells);
    }
    if (set.length != before) runtime._hiddenRevision++;
  }
}

/// Finding maps in a world.
abstract final class LevelMaps {
  /// What a level's own map is called.
  static const String primaryName = 'Level Map';

  /// The level's map: the entity called [primaryName], else the first map
  /// that no system generated and that is not a piece of another map. Null
  /// when the level has none. It need not have loaded.
  static Entity? primaryEntity(World world) {
    Entity? first;
    for (final e in world.query([LevelMapComponent])) {
      if (e.name == primaryName) return e;
      if (first == null &&
          !e.hasComponent<GeneratedEntityComponent>() &&
          !isPiece(world, e)) {
        first = e;
      }
    }
    return first;
  }

  /// The map [entity] is a child of, if its parent has one.
  static Entity? ownerOf(World world, Entity entity) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);
    return parent != null && parent.hasComponent<LevelMapComponent>()
        ? parent
        : null;
  }

  /// The layer of its parent's map that [entity] is on, if any — loaded or
  /// not.
  static MapLayerData? memberLayer(World world, Entity entity) {
    final id = entity.getComponent<LayerComponent>()?.mapLayer;
    if (id == null) return null;
    final owner = ownerOf(world, entity);
    final c = owner?.getComponent<LevelMapComponent>();
    final data = c?.runtime?.base ?? c?.inline;
    return data?.layerById(id);
  }

  /// Whether [entity] is a map that is a piece of another map: a child of a
  /// map entity, on one of its layers — tiles cut out of a layer to move as
  /// one thing.
  static bool isPiece(World world, Entity entity) =>
      entity.hasComponent<LevelMapComponent>() &&
      entity.getComponent<LayerComponent>()?.mapLayer != null &&
      ownerOf(world, entity) != null;

  /// The level's map ([primaryEntity]), once it has loaded.
  static LevelMapHandle? primary(World world) {
    final e = primaryEntity(world);
    return e == null ? null : of(world, e);
  }

  /// The map on [entity], once it has loaded.
  static LevelMapHandle? of(World world, Entity entity) {
    final c = entity.getComponent<LevelMapComponent>();
    final rt = c?.runtime;
    if (c == null || rt == null) return null;
    return LevelMapHandle._(world, entity, c, rt);
  }

  /// Every loaded map in [world].
  static Iterable<LevelMapHandle> all(World world) sync* {
    for (final e in world.query([LevelMapComponent])) {
      final h = of(world, e);
      if (h != null) yield h;
    }
  }

  /// The map the body [body] was built from.
  static LevelMapHandle? ofBody(World world, MapBodyComponent body) {
    final e = world.getEntity(body.mapEntityId);
    return e == null ? null : of(world, e);
  }

  /// Loads every map in [world] and its tilesets, so the first frame of a
  /// level has its ground: without it the player could fall through before
  /// the collision exists. Images may still be arriving.
  ///
  /// A map that will not load — a missing or unreadable file, one saved by a
  /// newer engine — does not stop the rest: it is left without a runtime
  /// (nothing drawn, nothing to collide with), reported once through
  /// [TileAssets.log], and returned among the failures; the returned list
  /// is empty when every map loaded. A tileset or image that will not load
  /// only leaves its tiles out, and is reported the same way.
  static Future<List<LevelMapLoadFailure>> preload(World world) async {
    final failures = <LevelMapLoadFailure>[];
    for (final e in world.query([LevelMapComponent]).toList()) {
      final c = e.getComponent<LevelMapComponent>()!;
      try {
        final rt = await runtimeFor(world, c);
        await rt?.syncAssets();
      } catch (error, stack) {
        failures.add(
          LevelMapLoadFailure(
            entity: e,
            path: c.mapPath.trim(),
            error: error,
            stackTrace: stack,
          ),
        );
      }
    }
    return failures;
  }

  /// The runtime for [c], a component in [world], made if it has none or is
  /// out of date — the one it replaces is disposed. Null when the map has
  /// nothing to show. Fails when [c]'s map file will not load (see
  /// [TileAssets.map]). Files come through `world.context`.
  static Future<LevelMapRuntime?> runtimeFor(
    World world,
    LevelMapComponent c,
  ) async {
    final Object? source = c.usesFile ? c.mapPath.trim() : c.inline;
    if (source == null) {
      release(c);
      return null;
    }
    final current = c.runtime;
    if (current != null && _sameSource(current.source, source)) return current;
    final base = source is LevelMapData
        ? source
        : await world.context.tiles.map(source as String);
    // Still wanted?
    final now = c.usesFile ? c.mapPath.trim() : c.inline;
    if (!_sameSource(now, source)) return c.runtime;
    // Made meanwhile by another call?
    final existing = c.runtime;
    if (existing != null && _sameSource(existing.source, source)) {
      return existing;
    }
    final rt = LevelMapRuntime(
      base: base,
      source: source,
      context: world.context,
    );
    existing?.dispose();
    c.runtime = rt;
    unawaited(rt.syncAssets());
    return rt;
  }

  /// Disposes [c]'s runtime, if it has one, and clears it: the map is made
  /// again from its source the next time it is needed, without the running
  /// game's changes.
  static void release(LevelMapComponent c) {
    c.runtime?.dispose();
    c.runtime = null;
  }

  /// Lets [world]'s [TileAssets] forget every map file and tileset no map in
  /// it
  /// uses — switched off or not — so a game that goes from level to level
  /// does not keep them all. Call it once the next level is loaded.
  ///
  /// Not for an editor, which keeps the maps it edits in [TileAssets].
  static void evictUnused(World world) {
    final tiles = world.context.tiles;
    final keep = <String>{};
    for (final e in world.entities) {
      final c = e.getComponent<LevelMapComponent>();
      if (c == null) continue;
      final path = c.mapPath.trim();
      if (c.usesFile) keep.add(path);
      final data =
          c.runtime?.base ?? (c.usesFile ? tiles.loadedMap(path) : c.inline);
      for (final ts in data?.tilesets ?? const <String?>[]) {
        if (ts != null) keep.add(ts);
      }
    }
    tiles.retainOnly(keep);
  }

  static bool _sameSource(Object? a, Object? b) =>
      a is String ? a == b : identical(a, b);
}

/// A map [LevelMaps.preload] could not load.
class LevelMapLoadFailure {
  /// The map on [entity], from [path], failed with [error], thrown at
  /// [stackTrace] when known.
  const LevelMapLoadFailure({
    required this.entity,
    required this.path,
    required this.error,
    this.stackTrace,
  });

  /// The entity carrying the map.
  final Entity entity;

  /// The map file it names; empty for a map kept in the scene.
  final String path;

  /// Why it would not load.
  final Object error;

  /// Where [error] was thrown; null when not known.
  final StackTrace? stackTrace;

  @override
  String toString() => 'LevelMapLoadFailure($path: $error)';
}
