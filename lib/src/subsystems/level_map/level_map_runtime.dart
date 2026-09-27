/// A level map as the running game holds it, and the API to read and change
/// it.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import '../../ecs/systems/rendering/sprite_systems.dart';
import 'render/map_layer_painter.dart';
import 'built_in_tilesets.dart';
import 'tile_assets.dart';
import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'level_map_data.dart';
import 'map_geometry.dart';
import 'tileset_data.dart';
import 'wang/wang_filler.dart';

/// Fired when the running game changes a tile.
class TileChangedEvent extends GameEvent {
  TileChangedEvent({
    required this.map,
    required this.layerId,
    required this.cells,
  });

  /// The entity carrying the map.
  final Entity map;
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
  LevelMapRuntime({required this.base, required this.source});

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

  /// Layers whose collision must be rebuilt.
  final Set<int> collisionDirty = {};

  /// Cells not drawn, by layer — a crumbled block, say.
  final Map<int, Set<TileCoord>> hiddenCells = {};
  int hiddenRevision = 0;

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

  /// Draws the layers.
  late final MapLayerPainter painter = MapLayerPainter(this);

  /// [layer]'s cells as the game sees them: the document's, with the
  /// game's changes on top.
  TileChunkStore cellsOf(MapLayerData layer) =>
      _overlays[layer.id] ?? layer.cells;

  /// [layer]'s cells for writing: an overlay, made on first write.
  TileChunkStore writableCells(MapLayerData layer) =>
      _overlays.putIfAbsent(layer.id, () => TileChunkStore.over(layer.cells));

  /// Whether the game has changed [layer].
  bool isChanged(MapLayerData layer) => _overlays.containsKey(layer.id);

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
    final image = imageAt(slot);
    if (image == null) return null;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(image.width.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    final mirrored = recorder.endRecording().toImageSync(
      image.width,
      image.height,
    );
    return _mirrored[slot] = mirrored;
  }

  /// Loads whatever tilesets and images are missing or out of date. Safe to
  /// call every frame; returns the load in progress.
  Future<void> syncAssets() {
    final changed =
        _loadedAssetsRevision != TileAssets.revision ||
        !_samePaths(_loadedPaths, base.tilesets);
    if (!changed) return _loading ?? Future.value();
    _loadedAssetsRevision = TileAssets.revision;
    final paths = _loadedPaths = [...base.tilesets];
    // Tilesets already in memory are taken at once, so a map whose tilesets
    // are loaded collides in the very frame it appears.
    final ready = [
      for (final p in paths) p == null ? null : TileAssets.loadedTileset(p),
    ];
    var allReady = true;
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != null && ready[i] == null) allReady = false;
    }
    if (allReady) {
      _applyTilesets(ready);
      return _loading = _loadImages(paths, ready);
    }
    return _loading = _load(paths);
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

  Future<void> _load(List<String?> paths) async {
    final sets = <TilesetData?>[];
    for (final path in paths) {
      try {
        sets.add(path == null ? null : await TileAssets.tileset(path));
      } catch (_) {
        // A tileset that will not load leaves its tiles undrawn and
        // uncollidable; the editor's validator says which.
        sets.add(null);
      }
    }
    if (!_samePaths(paths, _loadedPaths)) return; // superseded
    _applyTilesets(sets);
    await _loadImages(paths, sets);
  }

  Future<void> _loadImages(List<String?> paths, List<TilesetData?> sets) async {
    final images = <ui.Image?>[];
    for (final ts in sets) {
      try {
        images.add(
          ts == null || ts.image.isEmpty
              ? null
              : BuiltInTilesets.image(ts.image) ??
                    await SpriteAssets.loader.loadImage(ts.image),
        );
      } catch (_) {
        images.add(null);
      }
    }
    if (!_samePaths(paths, _loadedPaths)) return;
    _images
      ..clear()
      ..addAll(images);
    _mirrored.clear();
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
  const TileInfo({
    required this.cell,
    required this.tileset,
    required this.localId,
    this.def,
  });

  /// The cell's value.
  final int cell;
  final TilesetData tileset;

  /// The tile's id within [tileset].
  final int localId;

  /// What the tileset says about the tile, if anything.
  final TileDef? def;

  String get className => def?.className ?? '';

  /// The tile's properties; empty when it has none.
  Map<String, Object?> get properties => {
    for (final name in def?.properties.names ?? const <String>[])
      name: def!.properties[name],
  };

  bool get isFlippedH => TileCell.isFlippedH(cell);
  bool get isFlippedV => TileCell.isFlippedV(cell);
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

  final World world;

  /// The entity carrying the map.
  final Entity entity;
  final LevelMapComponent component;
  final LevelMapRuntime runtime;

  LevelMapData get map => runtime.base;
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

  /// [world] turned into [layer]'s own pixels.
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
    final set = runtime.hiddenCells.putIfAbsent(layer.id, () => {});
    final before = set.length;
    if (hidden) {
      set.addAll(cells);
    } else {
      set.removeAll(cells);
    }
    if (set.length != before) runtime.hiddenRevision++;
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
  static Future<void> preload(World world) async {
    for (final e in world.query([LevelMapComponent]).toList()) {
      final c = e.getComponent<LevelMapComponent>()!;
      final rt = await runtimeFor(c);
      await rt?.syncAssets();
    }
  }

  /// The runtime for [c], made if it has none or is out of date. Null when
  /// the map has nothing to show.
  static Future<LevelMapRuntime?> runtimeFor(LevelMapComponent c) async {
    final Object? source = c.usesFile ? c.mapPath.trim() : c.inline;
    if (source == null) {
      c.runtime = null;
      return null;
    }
    final current = c.runtime;
    if (current != null && _sameSource(current.source, source)) return current;
    final base = source is LevelMapData
        ? source
        : await TileAssets.map(source as String);
    // Still wanted?
    final now = c.usesFile ? c.mapPath.trim() : c.inline;
    if (!_sameSource(now, source)) return c.runtime;
    final rt = LevelMapRuntime(base: base, source: source);
    c.runtime = rt;
    unawaited(rt.syncAssets());
    return rt;
  }

  static bool _sameSource(Object? a, Object? b) =>
      a is String ? a == b : identical(a, b);
}
