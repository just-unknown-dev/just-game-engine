/// Builds the static bodies map layers collide with, from their tiles.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart' show Vector3;
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../../subsystems/level_map/collision/tile_collision_builder.dart';
import '../../../subsystems/level_map/collision/map_collision_kinds.dart';
import '../../../subsystems/level_map/tile_cell.dart';
import '../../../subsystems/level_map/level_map_data.dart';
import '../../../subsystems/level_map/level_map_runtime.dart';
import '../../../subsystems/level_map/tile_properties.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

/// Gives every map layer marked *collides* the static bodies its tiles'
/// collision shapes describe.
///
/// Bodies are ordinary entities — a transform, a static `PhysicsBodyComponent`,
/// a [MapBodyComponent] saying what they are — so contacts with them are
/// reported like any other, and standing on them grounds a character. They
/// carry a `GeneratedEntityComponent`: built from the map, never saved.
///
/// A layer's bodies are rebuilt, at most once a frame, whenever its cells,
/// settings or tilesets change, or the map moves. Runs before physics, so a
/// change is in this frame's step.
///
/// An editor switches this system off while a level is being authored —
/// the scene is what is edited, not bodies built from it — and calls
/// [clearGenerated]; bodies are built when play starts.
class MapCollisionSystem extends System {
  @override
  int get priority => SystemPriorities.mapCollision;

  @override
  List<Type> get requiredComponents => [TransformComponent, LevelMapComponent];

  /// Tile bodies by map entity, then by layer.
  final Map<int, Map<int, List<Entity>>> _bodies = {};

  /// What each layer's tile bodies were built from.
  final Map<int, Map<int, int>> _built = {};

  /// How many bodies exist now. For tests and diagnostics.
  int get bodyCount => _bodies.values.fold(
    0,
    (a, m) => a + m.values.fold(0, (b, l) => b + l.length),
  );

  @override
  void update(double deltaTime) {
    final live = <int>{};
    for (final entity in entities.toList()) {
      live.add(entity.id);
      final c = entity.getComponent<LevelMapComponent>()!;
      final rt = c.runtime;
      if (rt == null || !rt.tilesetsReady) continue;
      _syncMap(entity, rt);
    }
    for (final id in _bodies.keys.toList()) {
      if (!live.contains(id)) _removeMap(id);
    }
  }

  void _syncMap(Entity entity, LevelMapRuntime rt) {
    final byLayer = _bodies.putIfAbsent(entity.id, () => {});
    final built = _built.putIfAbsent(entity.id, () => {});
    final p = entity.getComponent<TransformComponent>()!.position;
    final origin = Offset(p.x, p.y);
    final layers = {for (final l in rt.base.layers) l.id: l};

    for (final id in byLayer.keys.toList()) {
      final layer = layers[id];
      if (layer == null || !layer.collides) {
        _destroy(byLayer.remove(id)!);
        built.remove(id);
      }
    }
    for (final layer in rt.base.layers) {
      if (!layer.collides) continue;
      final cells = rt.cellsOf(layer);
      final signature = Object.hash(
        identityHashCode(rt),
        identityHashCode(cells),
        cells.revision,
        rt.base.revision,
        rt.tilesetsRevision,
        rt.assetsRevision,
        origin,
        layer.offsetX,
        layer.offsetY,
      );
      if (built[layer.id] == signature &&
          !rt.collisionDirty.contains(layer.id)) {
        continue;
      }
      rt.collisionDirty.remove(layer.id);
      built[layer.id] = signature;
      final old = byLayer.remove(layer.id);
      if (old != null) _destroy(old);
      byLayer[layer.id] = _buildLayer(entity, rt, layer, origin);
    }
  }

  List<Entity> _buildLayer(
    Entity map,
    LevelMapRuntime rt,
    MapLayerData layer,
    Offset origin,
  ) {
    final specs = TileCollisionBuilder.build(
      cells: rt.cellsOf(layer),
      geometry: rt.geometry,
      tilesetAt: rt.tilesetAt,
      offset: Offset(layer.offsetX, layer.offsetY),
    );
    return [
      for (final spec in specs)
        _body(map, layer, origin, spec, _propertiesOf(rt, layer, spec)),
    ];
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
    final kind = MapCollisionKinds.resolve(spec.kind);
    final at = origin + spec.center;
    final body = world.createEntityWithComponents([
      TransformComponent(position: Vector3(at.dx, at.dy, 0)),
      PhysicsBodyComponent(
        shape: spec.isBox
            ? RectangleShape(spec.size!.width, spec.size!.height)
            : PolygonShape([...spec.polygon!]),
        isStatic: true,
        isOneWay: kind.oneWay,
        isSensor: kind.sensor,
        fixedRotation: true,
        // The level does not bounce what lands on it, and a level's worth of
        // collider outlines is noise.
        restitution: 0,
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
  /// cells.
  static TileProperties _propertiesOf(
    LevelMapRuntime rt,
    MapLayerData layer,
    MapBodySpec spec,
  ) {
    if (spec.cells.isEmpty) return TileProperties();
    final at = spec.cells.first;
    final cell = rt.cellsOf(layer).cellAt(at.x, at.y);
    return rt
            .tilesetAt(TileCell.slotOf(cell))
            ?.tile(TileCell.localIdOf(cell))
            ?.properties ??
        TileProperties();
  }

  void _destroy(List<Entity> bodies) {
    for (final b in bodies) {
      if (b.isAlive) world.destroyEntity(b);
    }
  }

  void _removeMap(int id) {
    _built.remove(id);
    for (final list in _bodies.remove(id)?.values ?? const <List<Entity>>[]) {
      _destroy(list);
    }
  }

  /// Destroys every body this system built. The next update, if the system
  /// is active, builds them again.
  void clearGenerated() {
    for (final id in _bodies.keys.toList()) {
      _removeMap(id);
    }
  }
}
