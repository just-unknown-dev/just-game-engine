/// The draw list of a `RenderSystem`: what it draws, in order.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../../graphics/graphics_2d/lighting/shadow_caster_2d_component.dart';
import '../../graphics/graphics_2d/materials/material_2d_component.dart';
import '../../particles/particles.dart';
import '../layer_component.dart';
import '../render_items_component.dart';
import '../renderable.dart';
import '../renderable_component.dart';
import '../shader_component.dart';

/// One thing a `RenderSystem` draws: an entity's renderable, its particle
/// emitter, or one of its [RenderItem]s — with the entity's components,
/// found when the list was last built.
@internal
final class RenderEntry {
  RenderEntry._(this.key, this.entity);

  /// What the entry draws, as the list knows it by: the
  /// [RenderableComponent], the [ParticleEmitter] or the [RenderItem].
  final Object key;

  /// The entity it belongs to.
  final Entity entity;

  /// Which of its entity's things it is: 0 its renderable, 1 its emitter,
  /// `2 + i` its `i`-th render item. With the entity's id, the last
  /// tie-breaks of the draw order (see [RenderQueue]).
  int slot = 0;

  /// The list build that last found it.
  int _stamp = 0;

  RenderItem? item;
  ParticleEmitter? emitter;
  TransformComponent? transform;
  RenderableComponent? renderComp;
  LayerComponent? layer;
  ShaderComponent? shader;
  Material2DComponent? material;
  ShadowCaster2DComponent? caster;

  /// What the renderable looked like when last asked, and the frame it was
  /// asked in (see `RenderBatcher.lookOf`).
  Object? look;
  int lookFrame = -1;

  /// [transform]'s capture count when last checked.
  int captures = 0;

  /// Whether [transform]'s previous pose was captured in the last fixed
  /// update, so it is drawn between that pose and its pose.
  bool fresh = false;

  /// After a fixed update: whether the transform captured its previous
  /// pose in it.
  void checkCaptures() {
    final t = transform;
    if (t == null) return;
    final count = t.captureCount;
    fresh = count != captures;
    captures = count;
  }

  // The sort key, refreshed every frame.
  int layerKey = 0;
  int zKey = 0;
  int sub = 0;

  /// Whether the renderable sorts by its height on screen
  /// (`Renderable.ySort`), and that height — its world y.
  bool ySort = false;
  double yKey = 0.0;

  void refreshKey() {
    final i = item;
    if (i != null) {
      layerKey = i.layer;
      zKey = i.zOrder;
      sub = i.subOrder;
      ySort = false;
      yKey = 0.0;
      return;
    }
    final l = layer;
    final Renderable? r = renderComp?.renderable ?? emitter;
    if (l != null) {
      layerKey = l.layer;
      zKey = l.zOrder;
      sub = l.subOrder;
    } else if (r != null) {
      // No LayerComponent: the renderable's own layer and zOrder count.
      layerKey = r.layer;
      zKey = r.zOrder;
      sub = 0;
    } else {
      layerKey = 0;
      zKey = 0;
      sub = 0;
    }
    ySort = r != null && r.ySort;
    if (!ySort) {
      yKey = 0.0;
      return;
    }
    // Read before the renderable is moved to its transform this frame.
    final t = transform;
    yKey = t != null && (renderComp?.syncTransform ?? false)
        ? t.position.y
        : r!.position.y;
  }
}

/// Every renderable, particle emitter and render item of a world, in draw
/// order — the list a `RenderSystem` draws from.
///
/// ## The order
///
/// world.query returns entities in archetype order, which is effectively
/// arbitrary and shifts as components are added or removed. That is fine
/// until a level has a background and a foreground, at which point "what
/// draws in front" becomes luck. `LayerComponent` makes it authorable, and a
/// [RenderItem] carries its own layer so one entity can draw at several
/// depths (a tile map's layers).
///
/// Every renderable, emitter and item becomes one [RenderEntry], sorted by
/// layer, then zOrder, then a sub-order — which keeps the entities on a map
/// layer between that layer's tiles and the next one's — then, for a
/// renderable that asks for it (`Renderable.ySort`), by world y after the
/// rest of its place; the last tie-breaks are the kind of thing —
/// renderables, then particle emitters, then render items — then the
/// entity's id (the order entities were made in), then an item's place in
/// its list. So two things on the same layer never swap from one frame to
/// the next, nor when another entity comes or goes. (The last tie-break
/// used to be the order the list found things in, which follows archetype
/// rows: destroying one entity moves another into its row, and overlapping
/// sprites swapped.) An
/// entity's `LayerComponent` gives its layer and zOrder; without one, its
/// renderable's own `layer` and `zOrder` do. Layer and zOrder are compared
/// as two numbers: they used to be packed into one by shifting the layer
/// left 20 bits, which on the web — where a shift makes an unsigned 32-bit
/// number — sorted every negative layer after all the others.
///
/// ## Keeping it
///
/// The list is kept between frames. It is brought up to date only when the
/// world's structure changes (an entity or a component added or removed, an
/// entity switched on or off) or an entity's render items change, and then
/// only what changed is: the entries still there are kept as they are, in
/// order, what went is dropped, and what came is sorted and merged in. (It
/// used to be built and sorted again from scratch: one bullet made and one
/// destroyed a frame cost every renderable of the level a frame.) Each
/// frame refreshes the keys and re-sorts by insertion, which costs one pass
/// when nothing moved. Each entry holds its entity's components, found once
/// per archetype, so a frame looks nothing up.
@internal
final class RenderQueue {
  /// Every entry, in draw order.
  final List<RenderEntry> entries = [];

  /// The entries by what they draw.
  final Map<Object, RenderEntry> _byKey = Map.identity();

  /// Entries the last build found new, sorted and merged in by [prepare].
  final List<RenderEntry> _added = [];

  /// The render items each entity had when the list was built.
  final List<_ItemsWatch> _watches = [];

  World? _builtFor;

  /// The largest of the list's queries' versions when it was built.
  int _builtVersion = -1;

  /// [World.updateCount] when the entries' captures were last checked.
  int _seenUpdates = -1;

  /// Counts builds, to tell which entries a build found.
  int _stamp = 0;

  /// Beyond this many out-of-order neighbours the list is sorted from
  /// scratch rather than by insertion.
  static const int _insertionLimit = 16;

  static const List<Type> _renderableQuery = [
    TransformComponent,
    RenderableComponent,
  ];
  static const List<Type> _emitterQuery = [ParticleEmitterComponent];
  static const List<Type> _itemsQuery = [
    TransformComponent,
    RenderItemsComponent,
  ];

  /// Forgets everything: the next [prepare] builds the list anew.
  void clear() {
    entries.clear();
    _byKey.clear();
    _added.clear();
    _watches.clear();
    _builtFor = null;
    _builtVersion = -1;
  }

  /// The largest version of the queries the list is built from: it moves
  /// on only when what they match changes.
  static int _queriesVersion(World w) => math.max(
    w.queryVersion(_renderableQuery),
    math.max(w.queryVersion(_emitterQuery), w.queryVersion(_itemsQuery)),
  );

  /// Brings the list up to date with [world] and into order.
  void prepare(World world) {
    if (!identical(_builtFor, world)) {
      clear();
      _seenUpdates = world.updateCount;
      _build(world);
    } else if (_builtVersion != _queriesVersion(world) || _itemsChanged()) {
      _build(world);
    }
    final updates = world.updateCount;
    if (updates != _seenUpdates) {
      _seenUpdates = updates;
      for (final e in entries) {
        e.checkCaptures();
      }
    }
    for (final e in entries) {
      e.refreshKey();
    }
    _sort(entries);
    if (_added.isNotEmpty) {
      for (final e in _added) {
        e.refreshKey();
      }
      _added.sort(_compare);
      _mergeAdded();
    }
  }

  bool _itemsChanged() {
    for (final watch in _watches) {
      final items = watch.component.items;
      final seen = watch.items;
      if (items.length != seen.length) return true;
      for (var i = 0; i < seen.length; i++) {
        if (!identical(items[i], seen[i])) return true;
      }
    }
    return false;
  }

  /// The entry for [key] of [entity] in this build: the one there was, or a
  /// new one (queued in [_added]).
  RenderEntry _claim(Object key, Entity entity, int slot, int stamp) {
    final known = _byKey[key];
    if (known != null &&
        known._stamp != stamp &&
        identical(known.entity, entity)) {
      return known
        .._stamp = stamp
        ..slot = slot;
    }
    final entry = RenderEntry._(key, entity)
      .._stamp = stamp
      ..slot = slot;
    // A thing found twice in one build (one item in two lists) has an entry
    // per place; only the first is kept by key.
    if (known == null || known._stamp != stamp) _byKey[key] = entry;
    _added.add(entry);
    return entry;
  }

  void _build(World world) {
    final stamp = ++_stamp;
    _added.clear();
    _watches.clear();

    for (final archetype in world.queryArchetypes(_renderableQuery)) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final renderables = archetype.getColumn(RenderableComponent)!;
      final layers = archetype.getColumn(LayerComponent);
      final shaders = archetype.getColumn(ShaderComponent);
      final materials = archetype.getColumn(Material2DComponent);
      final casters = archetype.getColumn(ShadowCaster2DComponent);
      for (var row = 0; row < ids.length; row++) {
        final component = renderables[row] as RenderableComponent;
        final transform = transforms[row] as TransformComponent;
        final entry = _claim(component, archetype.entityAt(row), 0, stamp);
        if (!identical(entry.transform, transform)) {
          // Nothing seen of this transform yet: its previous pose is fresh
          // when it was captured in the world's latest update (a moving
          // body's, every step); anything else is drawn where it is until
          // a fixed update captures it.
          entry
            ..captures = transform.captureCount
            ..fresh = transform.capturedInUpdate == world.updateCount;
        }
        entry
          ..transform = transform
          ..renderComp = component
          ..layer = layers?[row] as LayerComponent?
          ..shader = shaders?[row] as ShaderComponent?
          ..material = materials?[row] as Material2DComponent?
          ..caster = casters?[row] as ShadowCaster2DComponent?;
      }
    }

    // Particle emitters draw their particles, which are in world space.
    for (final archetype in world.queryArchetypes(_emitterQuery)) {
      final ids = archetype.entityIds;
      final emitters = archetype.getColumn(ParticleEmitterComponent)!;
      final layers = archetype.getColumn(LayerComponent);
      final renderables = archetype.getColumn(RenderableComponent);
      for (var row = 0; row < ids.length; row++) {
        final emitter = (emitters[row] as ParticleEmitterComponent).emitter;
        // Already drawn as the entity's renderable (how emitters had to be
        // shown before the render system drew them).
        final shown = renderables?[row] as RenderableComponent?;
        if (identical(shown?.renderable, emitter)) continue;
        _claim(emitter, archetype.entityAt(row), 1, stamp)
          ..emitter = emitter
          ..layer = layers?[row] as LayerComponent?;
      }
    }

    for (final archetype in world.queryArchetypes(_itemsQuery)) {
      final ids = archetype.entityIds;
      final itemColumn = archetype.getColumn(RenderItemsComponent)!;
      final layers = archetype.getColumn(LayerComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final component = itemColumn[row] as RenderItemsComponent;
        final layer = layers?[row] as LayerComponent?;
        final items = component.items;
        _watches.add(_ItemsWatch(component, List.of(items)));
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          _claim(item, entity, 2 + i, stamp)
            ..item = item
            ..layer = layer;
        }
      }
    }

    // What this build did not find is gone; the rest keeps its order.
    entries.removeWhere((e) {
      if (e._stamp == stamp) return false;
      if (identical(_byKey[e.key], e)) _byKey.remove(e.key);
      return true;
    });
    _builtFor = world;
    _builtVersion = _queriesVersion(world);
  }

  /// Merges [_added] (sorted) into [entries] (sorted), from the back.
  void _mergeAdded() {
    final list = entries;
    var i = list.length - 1;
    var j = _added.length - 1;
    list.addAll(_added);
    var write = list.length - 1;
    while (j >= 0) {
      if (i >= 0 && _compare(list[i], _added[j]) > 0) {
        list[write--] = list[i--];
      } else {
        list[write--] = _added[j--];
      }
    }
    _added.clear();
  }

  static int _compare(RenderEntry a, RenderEntry b) {
    if (a.layerKey != b.layerKey) return a.layerKey < b.layerKey ? -1 : 1;
    if (a.zKey != b.zKey) return a.zKey < b.zKey ? -1 : 1;
    if (a.sub != b.sub) return a.sub < b.sub ? -1 : 1;
    // What sorts by height (Renderable.ySort) draws after the rest of its
    // place, the highest on screen first.
    if (a.ySort != b.ySort) return a.ySort ? 1 : -1;
    final byY = a.yKey.compareTo(b.yKey);
    if (byY != 0) return byY;
    // Renderables, then emitters, then render items — as they were always
    // found — each kind in the order its entities were made.
    final kind = (a.slot < 2 ? a.slot : 2) - (b.slot < 2 ? b.slot : 2);
    if (kind != 0) return kind;
    final byId = a.entity.id.compareTo(b.entity.id);
    if (byId != 0) return byId;
    return a.slot - b.slot;
  }

  /// Sorts [list]: by insertion when only a few are out of place — one pass
  /// when none are — and from scratch otherwise. The order is total (the
  /// entity and slot break every tie), so either gives the same list.
  static void _sort(List<RenderEntry> list) {
    var descents = 0;
    for (var i = 1; i < list.length; i++) {
      if (_compare(list[i - 1], list[i]) > 0 && ++descents > _insertionLimit) {
        break;
      }
    }
    if (descents == 0) return;
    if (descents > _insertionLimit) {
      list.sort(_compare);
      return;
    }
    for (var i = 1; i < list.length; i++) {
      final e = list[i];
      var j = i - 1;
      if (_compare(list[j], e) <= 0) continue;
      while (j >= 0 && _compare(list[j], e) > 0) {
        list[j + 1] = list[j];
        j--;
      }
      list[j + 1] = e;
    }
  }
}

/// An entity's render items as they were when the draw list was built.
class _ItemsWatch {
  _ItemsWatch(this.component, this.items);
  final RenderItemsComponent component;
  final List<RenderItem> items;
}
