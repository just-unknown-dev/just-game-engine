/// Loads level maps and keeps their drawing current.
library;

import 'dart:async';

import '../../../subsystems/level_map/render/map_layer_painter.dart';
import '../../../subsystems/level_map/tile_assets.dart';
import '../../../subsystems/level_map/level_map_data.dart';
import '../../../subsystems/level_map/level_map_runtime.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

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
class LevelMapSystem extends System {
  @override
  int get priority => SystemPriorities.levelMap;

  @override
  List<Type> get requiredComponents => [TransformComponent, LevelMapComponent];

  /// Animation time, in milliseconds.
  double clockMs = 0;

  /// Whether [update] advances [clockMs] with the game's time.
  bool advanceClock = true;

  final Set<LevelMapComponent> _loading = {};

  /// The entities placed on a map layer last update, so one that leaves its
  /// layer draws as an ordinary entity again.
  Set<Entity> _members = {};

  @override
  void update(double deltaTime) {
    if (advanceClock) clockMs += deltaTime * 1000;
    // A copy: attaching render items changes the world's archetypes.
    for (final entity in entities.toList()) {
      final c = entity.getComponent<LevelMapComponent>()!;
      final Object? source = c.usesFile ? c.mapPath.trim() : c.inline;
      if (source == null) {
        c.runtime = null;
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
          c.runtime = LevelMapRuntime(base: source, source: source);
        } else {
          // A file: shown once it arrives.
          if (_loading.add(c)) {
            unawaited(
              LevelMaps.runtimeFor(c).whenComplete(() => _loading.remove(c)),
            );
          }
          _syncItems(entity, null);
          continue;
        }
      }
      final runtime = c.runtime!;
      runtime.animationMs = clockMs.floor();
      unawaited(runtime.syncAssets());
      _syncItems(entity, runtime);
    }
    _syncMembers();
  }

  /// The sub-order of the map layer at [index] in its map, and of what is
  /// on it: a layer's things draw after it and before the next layer.
  static int _layerSub(int index) => (2 * index) << 16;
  static int _memberSub(int index, int child) =>
      ((2 * index + 1) << 16) + child;

  /// Places every map layer's entities with their layer.
  void _syncMembers() {
    final now = <Entity>{};
    for (final map in entities) {
      final runtime = map.getComponent<LevelMapComponent>()!.runtime;
      if (runtime == null) continue;
      final layers = runtime.base.layers;
      for (final item
          in map.getComponent<RenderItemsComponent>()?.items ??
              const <RenderItem>[]) {
        if (item is! MapLayerRenderItem) continue;
        final i = layers.indexWhere((l) => l.id == item.layerId);
        if (i >= 0) item.subOrder = _layerSub(i);
      }
      final children = map.getComponent<ChildrenComponent>()?.childIds;
      if (children == null) continue;
      for (var n = 0; n < children.length; n++) {
        final child = world.getEntity(children[n]);
        final lc = child?.getComponent<LayerComponent>();
        final id = lc?.mapLayer;
        if (child == null || lc == null || id == null) continue;
        if (child.getComponent<ParentComponent>()?.parentId != map.id) {
          continue;
        }
        final i = layers.indexWhere((l) => l.id == id);
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
        for (final item
            in child.getComponent<RenderItemsComponent>()?.items ??
                const <RenderItem>[]) {
          if (item is! MapLayerRenderItem) continue;
          item
            ..layerOverride = layer.sortLayer
            ..zOrderOverride = layer.zOrder
            ..subOrder = sub;
        }
        now.add(child);
      }
    }
    for (final gone in _members.difference(now)) {
      gone.getComponent<LayerComponent>()
        ?..subOrder = 0
        ..hiddenByMap = false;
      for (final item
          in gone.getComponent<RenderItemsComponent>()?.items ??
              const <RenderItem>[]) {
        if (item is! MapLayerRenderItem) continue;
        item
          ..layerOverride = null
          ..zOrderOverride = null
          ..subOrder = 0;
      }
    }
    _members = now;
  }

  /// Gives [entity] one render item per layer of [runtime] — or none.
  void _syncItems(Entity entity, LevelMapRuntime? runtime) {
    var items = entity.getComponent<RenderItemsComponent>();
    if (runtime == null) {
      items?.items.removeWhere((i) => i is MapLayerRenderItem);
      return;
    }
    final layers = runtime.base.layers;
    final existing =
        items?.items.whereType<MapLayerRenderItem>().toList() ?? const [];
    final upToDate =
        existing.length == layers.length &&
        Iterable.generate(layers.length).every(
          (i) =>
              identical(existing[i].runtime, runtime) &&
              existing[i].layerId == layers[i].id,
        );
    if (upToDate) return;
    if (items == null) {
      items = RenderItemsComponent();
      entity.addComponent(items);
    }
    items.items
      ..removeWhere((i) => i is MapLayerRenderItem)
      ..addAll([for (final l in layers) MapLayerRenderItem(runtime, l.id)]);
  }

  /// A tileset or map file changed on disk: read it again. Without [path],
  /// everything.
  void reload([String? path]) {
    TileAssets.evict(path);
    for (final entity in entities) {
      final c = entity.getComponent<LevelMapComponent>()!;
      if (path == null || c.mapPath.trim() == path) c.runtime = null;
    }
  }

  /// Loads every map, as [LevelMaps.preload] does.
  Future<void> preload() => LevelMaps.preload(world);
}
