/// Builds the static bodies map layers collide with, from their tiles.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart' show Vector2, Vector3;
import 'package:just_physics_engine/just_physics_engine.dart';

import 'collision/tile_collision_builder.dart';
import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'level_map_data.dart';
import 'level_map_runtime.dart';
import 'tile_properties.dart';
import 'tileset_data.dart';
import '../ecs/ecs.dart';
import '../physics/physics_2d/physics_2d_components.dart';
import 'level_map_component.dart';
import 'map_body_component.dart';
import 'level_map_context.dart';

/// Gives every map layer marked *collides* the static bodies its tiles'
/// collision shapes describe.
///
/// Bodies are ordinary entities — a transform, a static `RigidBody2DComponent` and a
/// `Collider2DComponent`, a [MapBodyComponent] saying what they are — so contacts
/// with them are
/// reported like any other, and standing on them grounds a character. They
/// carry a `GeneratedEntityComponent`: built from the map, never saved.
///
/// A layer's bodies are brought up to date, at most once a frame, whenever
/// its cells, settings or tilesets change. Runs before physics, so a change
/// is in this frame's step. A change of cells — a block broken, a door
/// opened — keeps every body it leaves as it was: only those that differ
/// are destroyed and made, so nothing standing elsewhere on the layer loses
/// its contact. A map that moves takes its bodies with it. A map with no
/// runtime — its source cleared, a file that would not load, a reload in
/// progress — has no bodies.
///
/// An editor switches this system off while a level is being authored —
/// the scene is what is edited, not bodies built from it — and calls
/// [clearGenerated]; bodies are built when play starts. Removed from its
/// world, the system destroys the bodies it built.
class MapCollisionSystem extends System {
  @override
  int get priority => SystemPriorities.mapCollision;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    LevelMapComponent,
  ];

  /// What was built for each map, by its entity's id.
  final Map<int, _BuiltMap> _maps = {};

  /// How many bodies exist now. For tests and diagnostics.
  int get bodyCount => _maps.values.fold(
    0,
    (a, m) => a + m.layers.values.fold(0, (b, l) => b + l.count),
  );

  @override
  void update(double deltaTime) {
    final live = <int>{};
    for (final entity in entities.toList()) {
      live.add(entity.id);
      final c = entity.getComponent<LevelMapComponent>()!;
      final rt = c.runtime;
      if (rt == null) {
        // No map — its source cleared, or a file that will not load: its
        // bodies go with it rather than collide invisibly.
        _removeMap(entity.id);
        continue;
      }
      // Tilesets still loading: what was built stays until they arrive.
      if (!rt.tilesetsReady) continue;
      _syncMap(entity, rt);
    }
    for (final id in _maps.keys.toList()) {
      if (!live.contains(id)) _removeMap(id);
    }
  }

  void _syncMap(Entity entity, LevelMapRuntime rt) {
    final p = entity.getComponent<TransformComponent>()!.position;
    final origin = Offset(p.x, p.y);
    final map = _maps.putIfAbsent(entity.id, () => _BuiltMap(rt, origin));
    if (!identical(map.runtime, rt) || !_same(map.tilesets, rt.tilesets)) {
      // Another runtime, or other tilesets: nothing built stands for them.
      _destroyMap(map);
      map
        ..runtime = rt
        ..tilesets = [...rt.tilesets];
    }
    if (map.origin != origin) {
      // The map moved: its bodies go with it, as they are.
      map.origin = origin;
      for (final layer in map.layers.values) {
        layer.moveTo(origin);
      }
    }

    final layers = {for (final l in rt.base.layers) l.id: l};
    for (final id in map.layers.keys.toList()) {
      final layer = layers[id];
      if (layer == null || !layer.collides) {
        map.layers.remove(id)!.destroy(world);
      }
    }
    for (final layer in rt.base.layers) {
      if (!layer.collides) continue;
      final cells = rt.cellsOf(layer);
      // Everything a body is built from besides the cells: whatever else
      // changed, every body is made again.
      final settings = Object.hash(
        rt.base.revision,
        rt.tilesetsRevision,
        layer.offsetX,
        layer.offsetY,
      );
      final dirty = rt.collisionDirty.remove(layer.id);
      var built = map.layers[layer.id];
      if (built != null && built.settings != settings) {
        built.destroy(world);
        built = null;
      }
      if (built != null &&
          !dirty &&
          identical(built.cells, cells) &&
          built.cellsRevision == cells.revision) {
        continue;
      }
      built ??= map.layers[layer.id] = _BuiltLayer(settings);
      built
        ..cells = cells
        ..cellsRevision = cells.revision;
      _buildLayer(entity, rt, layer, origin, built);
    }
  }

  static bool _same(List<TilesetData?> a, List<TilesetData?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Brings [built]'s bodies in line with [layer]'s tiles: a body built
  /// from the same thing as before stays, the rest are destroyed and made.
  void _buildLayer(
    Entity map,
    LevelMapRuntime rt,
    MapLayerData layer,
    Offset origin,
    _BuiltLayer built,
  ) {
    final cells = rt.cellsOf(layer);
    final specs = TileCollisionBuilder.build(
      cells: cells,
      geometry: rt.geometry,
      tilesetAt: rt.tilesetAt,
      offset: Offset(layer.offsetX, layer.offsetY),
      kinds: world.context.collisionKinds,
    );
    final old = built.bodies;
    final next = <_BodyKey, List<Entity>>{};
    for (final spec in specs) {
      final first = spec.cells.isEmpty
          ? TileCell.empty
          : cells.cellAt(spec.cells.first.x, spec.cells.first.y);
      final key = _BodyKey(spec, first);
      final kept = old[key];
      Entity? body;
      while (kept != null && kept.isNotEmpty && body == null) {
        final candidate = kept.removeLast();
        if (candidate.isAlive) body = candidate;
      }
      body ??= _body(
        map,
        layer,
        origin,
        spec,
        _propertiesOf(rt, layer, spec, first),
      );
      (next[key] ??= []).add(body);
    }
    for (final rest in old.values) {
      _destroy(rest);
    }
    built.bodies = next;
  }

  /// One static body, as [spec] describes, decorated by its kind with
  /// [properties] — its tile's.
  Entity _body(
    Entity map,
    MapLayerData layer,
    Offset origin,
    MapBodySpec spec,
    TileProperties properties,
  ) {
    final kind = world.context.collisionKinds.resolve(spec.kind);
    final at = origin + spec.center;
    final body = world.createEntityWithComponents([
      TransformComponent(position: Vector3(at.dx, at.dy, 0)),
      // The level does not bounce what lands on it, and a level's worth of
      // collider outlines is noise.
      RigidBody2DComponent(
        bodyType: Body2DType.static,
        isSensor: kind.sensor,
        lockRotation: true,
        // The friction tile ground has always had, so games play the same.
        friction: 0.2,
        restitution: 0,
      ),
      spec.isBox
          ? Collider2DComponent(
              size: Vector2(spec.size!.width, spec.size!.height),
              oneWay: kind.oneWay,
              showDebugOutline: false,
            )
          : Collider2DComponent(
              shape: Collider2DShape.polygon,
              points: [...spec.polygon!],
              oneWay: kind.oneWay,
              showDebugOutline: false,
            ),
      MapBodyComponent(
        mapEntityId: map.id,
        layerId: layer.id,
        kind: spec.kind,
        className: spec.className,
        cells: spec.cells,
      ),
      GeneratedEntityComponent(ownerId: map.id, source: 'mapCollision'),
    ]);
    kind.decorate?.call(body, spec, properties);
    return body;
  }

  /// The properties of the tile [spec] was built from — the first of its
  /// cells, which holds [cell].
  static TileProperties _propertiesOf(
    LevelMapRuntime rt,
    MapLayerData layer,
    MapBodySpec spec,
    int cell,
  ) {
    if (spec.cells.isEmpty) return TileProperties();
    return rt
            .tilesetAt(TileCell.slotOf(cell))
            ?.tile(TileCell.localIdOf(cell))
            ?.properties ??
        TileProperties();
  }

  void _destroy(Iterable<Entity> bodies) {
    for (final b in bodies) {
      if (b.isAlive) world.destroyEntity(b);
    }
  }

  void _destroyMap(_BuiltMap map) {
    for (final layer in map.layers.values) {
      layer.destroy(world);
    }
    map.layers.clear();
  }

  void _removeMap(int id) {
    final map = _maps.remove(id);
    if (map != null) _destroyMap(map);
  }

  /// Destroys every body this system built. The next update, if the system
  /// is active, builds them again.
  void clearGenerated() {
    for (final id in _maps.keys.toList()) {
      _removeMap(id);
    }
  }

  /// Takes back what it put in the world: the bodies it built. Without the
  /// system nothing keeps them up to date, and a system added in its place
  /// builds its own.
  @override
  void onRemovedFromWorld() => clearGenerated();
}

/// What was built for one map entity.
class _BuiltMap {
  _BuiltMap(this.runtime, this.origin);

  /// The runtime the bodies were built from.
  LevelMapRuntime runtime;

  /// Its tilesets when they were, by slot.
  List<TilesetData?> tilesets = const [];

  /// Where the map was.
  Offset origin;

  /// By layer id.
  final Map<int, _BuiltLayer> layers = {};
}

/// The bodies of one layer, and what they were built from.
class _BuiltLayer {
  _BuiltLayer(this.settings);

  /// Everything but the cells the bodies were built from.
  final int settings;

  /// The cells, and their revision, when last built.
  TileChunkStore? cells;
  int cellsRevision = -1;

  /// Each body by what it was built from; two of the same are rare but
  /// possible (a tile with a shape twice).
  Map<_BodyKey, List<Entity>> bodies = {};

  int get count => bodies.values.fold(0, (n, list) => n + list.length);

  /// Moves every body to its place on a map at [origin].
  void moveTo(Offset origin) {
    for (final MapEntry(:key, value: list) in bodies.entries) {
      final at = origin + key.spec.center;
      for (final body in list) {
        if (!body.isAlive) continue;
        body.getComponent<TransformComponent>()?.setPositionXY(at.dx, at.dy);
      }
    }
  }

  /// Destroys every body, in [world].
  void destroy(World world) {
    for (final list in bodies.values) {
      for (final b in list) {
        if (b.isAlive) world.destroyEntity(b);
      }
    }
    bodies = {};
  }
}

/// What one body is built from: its spec, and the cell value of the tile
/// whose properties decorate it.
class _BodyKey {
  _BodyKey(this.spec, this.cell) : _hash = _hashOf(spec, cell);

  final MapBodySpec spec;
  final int cell;
  final int _hash;

  static List<TileCoord> _sorted(List<TileCoord> cells) =>
      [...cells]
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

  static int _hashOf(MapBodySpec s, int cell) => Object.hash(
    s.kind,
    s.className,
    s.center,
    s.size,
    s.polygon == null ? null : Object.hashAll(s.polygon!),
    Object.hashAllUnordered(s.cells),
    cell,
  );

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (other is! _BodyKey) return false;
    if (_hash != other._hash || cell != other.cell) return false;
    final a = spec, b = other.spec;
    if (a.kind != b.kind ||
        a.className != b.className ||
        a.center != b.center ||
        a.size != b.size) {
      return false;
    }
    final pa = a.polygon, pb = b.polygon;
    if ((pa == null) != (pb == null)) return false;
    if (pa != null) {
      if (pa.length != pb!.length) return false;
      for (var i = 0; i < pa.length; i++) {
        if (pa[i] != pb[i]) return false;
      }
    }
    if (a.cells.length != b.cells.length) return false;
    final ca = _sorted(a.cells), cb = _sorted(b.cells);
    for (var i = 0; i < ca.length; i++) {
      if (ca[i] != cb[i]) return false;
    }
    return true;
  }
}
