/// Loads level maps and keeps their drawing current.
library;

import 'dart:async';

import '../../../subsystems/level_map/render/map_layer_painter.dart';
import '../../../subsystems/level_map/level_map_data.dart';
import '../../../subsystems/level_map/level_map_runtime.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../../base/system_priorities.dart';

/// Brings every `LevelMapComponent` to life: loads its map (from the scene
/// or a file) and tilesets, and gives its entity one render item per layer,
/// so each layer sorts among the level's drawing on its own.
///
/// It also keeps the map's children that belong to one of its layers
/// (`LayerComponent.mapLayer`) drawing with that layer: at its depth, just
/// above its tiles and below the next layer's, in the order they are
/// children, and hidden while it is.
///
/// Also the clock animated tiles run on. It advances with the game's time;
/// an editor that stops time while authoring can set [advanceClock] off and
/// move [clockMs] itself, so tiles animate while the level is edited.
///
/// A runtime it drops — its map replaced or cleared, its component or
/// entity gone, the system itself disposed — is disposed. A map file that
/// will not load is reported once (by `TileAssets`) and not asked for again
/// until its path changes or `TileAssets` changes (a [reload], an evict).
class LevelMapSystem extends System {
  @override
  int get priority => SystemPriorities.levelMap;

  static const List<Type> _required = [TransformComponent, LevelMapComponent];

  @override
  List<Type> get requiredComponents => _required;

  /// Animation time, in milliseconds.
  double clockMs = 0;

  /// Whether [update] advances [clockMs] with the game's time.
  bool advanceClock = true;

  final Set<LevelMapComponent> _loading = {};

  /// Map files that would not load, with the path and `TileAssets.revision`
  /// they failed at.
  final Map<LevelMapComponent, (String, int)> _failed = {};

  /// Every map seen, and its entity: what to let go of when the map leaves
  /// the world.
  final Map<LevelMapComponent, Entity> _seen = {};
  int _seenStructure = -1;

  /// Maps given a runtime this update that have no render items component
  /// yet: it is attached after the pass, which must not change the world's
  /// archetypes while it walks them.
  final List<(Entity, LevelMapRuntime)> _needItems = [];

  /// The entities placed on a map layer last update, so one that leaves its
  /// layer draws as an ordinary entity again — and the set being filled
  /// this update. The two are swapped each time.
  Set<Entity> _members = {};
  Set<Entity> _nextMembers = {};

  @override
  void update(double deltaTime) {
    if (advanceClock) clockMs += deltaTime * 1000;
    final version = world.queryVersion(const [LevelMapComponent]);
    if (_seenStructure != version) {
      _seenStructure = version;
      _releaseRemoved();
    }
    final clock = clockMs.floor();
    for (final entity in entities) {
      final c = entity.getComponent<LevelMapComponent>()!;
      _seen[c] = entity;
      final Object? source = c.usesFile ? c.mapPath.trim() : c.inline;
      if (source == null) {
        LevelMaps.release(c);
        _syncItems(entity, null);
        continue;
      }
      final rt = c.runtime;
      final current =
          rt != null &&
          (source is String
              ? rt.source == source
              : identical(rt.source, source));
      if (!current) {
        if (source is LevelMapData) {
          // In the scene: ready at once. Replaced whenever the component's
          // map is — a play-test stopping, an undo.
          rt?.dispose();
          c.runtime = LevelMapRuntime(
            base: source,
            source: source,
            context: world.context,
          );
        } else {
          // A file: shown once it arrives. What was made for another file
          // goes now — drawn and collided with, it would be the wrong map.
          if (rt != null) LevelMaps.release(c);
          _loadFile(c, source as String);
          _syncItems(entity, null);
          continue;
        }
      }
      final runtime = c.runtime!;
      runtime.animationMs = clock;
      unawaited(runtime.syncAssets());
      _syncItems(entity, runtime);
    }
    if (_needItems.isNotEmpty) {
      for (final (entity, runtime) in _needItems) {
        entity.addComponent(RenderItemsComponent(_itemsFor(runtime)));
      }
      _needItems.clear();
    }
    _syncMembers();
  }

  /// Starts loading [c]'s map file at [path], unless it is loading or failed
  /// at [path] with `TileAssets` as it is.
  void _loadFile(LevelMapComponent c, String path) {
    final failed = _failed[c];
    if (failed != null &&
        failed.$1 == path &&
        failed.$2 == world.context.tiles.revision) {
      return;
    }
    if (!_loading.add(c)) return;
    _failed.remove(c);
    LevelMaps.runtimeFor(world, c).then<void>(
      (_) {
        _loading.remove(c);
        // Gone from the world, or the system disposed, while it loaded.
        if (!_seen.containsKey(c)) LevelMaps.release(c);
      },
      onError: (Object _, StackTrace _) {
        // TileAssets has reported it.
        _loading.remove(c);
        if (_seen.containsKey(c)) {
          _failed[c] = (path, world.context.tiles.revision);
        }
      },
    );
  }

  /// Disposes the runtimes of maps whose component or entity has gone.
  void _releaseRemoved() {
    _seen.removeWhere((c, entity) {
      if (entity.isAlive &&
          identical(entity.getComponent<LevelMapComponent>(), c)) {
        return false;
      }
      LevelMaps.release(c);
      _failed.remove(c);
      return true;
    });
  }

  /// The sub-order of the map layer at [index] in its map, and of what is
  /// on it: a layer's things draw after it and before the next layer.
  static int _layerSub(int index) => (2 * index) << 16;
  static int _memberSub(int index, int child) =>
      ((2 * index + 1) << 16) + child;

  /// Places every map layer's entities with their layer.
  ///
  /// Done every update rather than only when something changed: the
  /// children lists, a child's `mapLayer` and a layer's settings are plain
  /// fields nothing counts changes to. It allocates nothing on the way.
  void _syncMembers() {
    final now = _nextMembers..clear();
    for (final map in entities) {
      final runtime = map.getComponent<LevelMapComponent>()!.runtime;
      if (runtime == null) continue;
      final data = runtime.base;
      final layers = data.layers;
      final items = map.getComponent<RenderItemsComponent>()?.items;
      if (items != null) {
        for (final item in items) {
          if (item is! MapLayerRenderItem) continue;
          final i = data.indexOfLayer(item.layerId);
          if (i >= 0) item.subOrder = _layerSub(i);
        }
      }
      final children = map.getComponent<ChildrenComponent>()?.childIds;
      if (children == null) continue;
      for (var n = 0; n < children.length; n++) {
        final child = world.getEntity(children[n]);
        if (child == null) continue;
        final lc = child.getComponent<LayerComponent>();
        final id = lc?.mapLayer;
        if (lc == null || id == null) continue;
        if (child.getComponent<ParentComponent>()?.parentId != map.id) {
          continue;
        }
        final i = data.indexOfLayer(id);
        if (i < 0) continue;
        final layer = layers[i];
        final sub = _memberSub(i, n);
        lc
          ..layerId = layer.sortLayerId
          ..layer = layer.sortLayer
          ..zOrder = layer.zOrder
          ..subOrder = sub
          ..hiddenByMap = !layer.visible;
        // A piece of the map — a map itself — draws its layers there too.
        final pieceItems = child.getComponent<RenderItemsComponent>()?.items;
        if (pieceItems != null) {
          for (final item in pieceItems) {
            if (item is! MapLayerRenderItem) continue;
            item
              ..layerOverride = layer.sortLayer
              ..zOrderOverride = layer.zOrder
              ..subOrder = sub;
          }
        }
        now.add(child);
      }
    }
    for (final gone in _members) {
      if (now.contains(gone)) continue;
      gone.getComponent<LayerComponent>()
        ?..subOrder = 0
        ..hiddenByMap = false;
      final items = gone.getComponent<RenderItemsComponent>()?.items;
      if (items == null) continue;
      for (final item in items) {
        if (item is! MapLayerRenderItem) continue;
        item
          ..layerOverride = null
          ..zOrderOverride = null
          ..subOrder = 0;
      }
    }
    _nextMembers = _members;
    _members = now;
  }

  static bool _isMapItem(RenderItem item) => item is MapLayerRenderItem;

  static List<RenderItem> _itemsFor(LevelMapRuntime runtime) => [
    for (final l in runtime.base.layers) MapLayerRenderItem(runtime, l.id),
  ];

  /// Gives [entity] one render item per layer of [runtime] — or none.
  void _syncItems(Entity entity, LevelMapRuntime? runtime) {
    final items = entity.getComponent<RenderItemsComponent>();
    if (runtime == null) {
      items?.items.removeWhere(_isMapItem);
      return;
    }
    if (items == null) {
      _needItems.add((entity, runtime));
      return;
    }
    // Up to date: one item per layer of this runtime, in the layers' order.
    final layers = runtime.base.layers;
    var n = 0;
    var upToDate = true;
    for (final item in items.items) {
      if (item is! MapLayerRenderItem) continue;
      if (n >= layers.length ||
          !identical(item.runtime, runtime) ||
          item.layerId != layers[n].id) {
        upToDate = false;
        break;
      }
      n++;
    }
    if (upToDate && n == layers.length) return;
    items.items
      ..removeWhere(_isMapItem)
      ..addAll(_itemsFor(runtime));
  }

  /// A tileset or map file changed on disk: read it again. Without [path],
  /// everything.
  void reload([String? path]) {
    world.context.tiles.evict(path);
    for (final entity in entities) {
      final c = entity.getComponent<LevelMapComponent>()!;
      if (path == null || c.mapPath.trim() == path) {
        LevelMaps.release(c);
        _failed.remove(c);
      }
    }
  }

  /// Loads every map, as [LevelMaps.preload] does, and returns those that
  /// would not load.
  Future<List<LevelMapLoadFailure>> preload() => LevelMaps.preload(world);

  /// Disposes every runtime this system made or kept and takes the maps'
  /// render items away: without the system, nothing loads or animates them.
  @override
  void dispose() {
    for (final MapEntry(key: c, value: entity) in _seen.entries) {
      LevelMaps.release(c);
      entity.getComponent<RenderItemsComponent>()?.items.removeWhere(
        _isMapItem,
      );
    }
    _seen.clear();
    _failed.clear();
    _loading.clear();
    _needItems.clear();
    _members.clear();
    _nextMembers.clear();
    super.dispose();
  }
}
