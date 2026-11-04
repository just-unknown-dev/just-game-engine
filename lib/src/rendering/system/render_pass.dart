library;

import 'dart:ui';

import '../../ecs/ecs.dart';

/// One stage of [RenderSystem]'s frame, run inside the camera transform.
///
/// The system's own stage draws every [RenderableComponent]; further stages
/// are added by passing them to the system, so a game can draw its own kinds
/// of thing — a tile map, a debug layer — without editing the engine.
abstract class RenderPass {
  /// Const constructor so subclasses can be const.
  const RenderPass();

  /// Passes run in ascending order.
  int get order => 0;

  /// Draws this stage onto [canvas], already in world space. An entity
  /// [filter] turns down — on a hidden map layer, or refused by the render
  /// system's `shouldRender` — should not be drawn.
  void render(Canvas canvas, RenderContext context, RenderPassFilter filter);
}

/// Whether an entity should be drawn this frame.
typedef RenderPassFilter = bool Function(Entity entity);

/// Draws every component whose [ComponentDefinition] carries a
/// [ComponentPainter], entity transform applied, ordered by
/// [ComponentPainter.layerOf].
///
/// Replaces the render system's hardcoded pass over text, buttons and
/// progress bars: those are now painters on their definitions, and any
/// component can join by defining one.
///
/// What it paints is found again only when the world's structure or the
/// registered painters change, and then only what changed is: what is
/// still there keeps its place, what went is dropped, what came is sorted
/// in. Each frame it re-reads the layers, re-sorts by insertion — one pass
/// when nothing moved — and paints. Components on the same layer paint in
/// the order their definitions were registered, then by entity — the order
/// entities were made in — so they never swap when another entity comes or
/// goes. (They used to paint in the order they were found, which follows
/// archetype rows: destroying one entity moved another into its row.)
///
/// An entity a fixed update moved by capturing its pose (a physics body, or
/// a child of one) is painted between its last two poses, as the render
/// system draws its sprite ([RenderContext.interpolation]), so a label or
/// a health bar on it does not jitter against it.
class ComponentPainterPass extends RenderPass {
  /// Paints with [definitions], or — when null — with the definitions of the
  /// world being drawn (`world.context.definitions`).
  ComponentPainterPass({this.definitions});

  /// The definitions given at construction; null reads the drawn world's.
  final ComponentDefinitionRegistry? definitions;

  /// What the current frame paints with.
  late ComponentDefinitionRegistry _using;

  @override
  int get order => 100;

  /// Everything there is to paint, in paint order.
  final List<_Paintable> _entries = [];

  /// The entries by the component they paint.
  final Map<Component, _Paintable> _byComponent = Map.identity();

  /// Entries the last rebuild found new, sorted in by [render].
  final List<_Paintable> _added = [];

  /// The definitions with painters the entries were found for, in order.
  final List<ComponentDefinition> _painted = [];

  /// The query each painted definition's entries came from.
  final List<List<Type>> _queries = [];
  World? _builtFor;

  /// The largest of [_queries]' versions when the entries were found.
  int _builtVersion = -1;

  /// [World.updateCount] when the entries' captures were last checked.
  int _seenUpdates = -1;

  /// Counts rebuilds, to tell which entries one found.
  int _stamp = 0;

  int _queriesVersion(World world) {
    var version = -1;
    for (final query in _queries) {
      final v = world.queryVersion(query);
      if (v > version) version = v;
    }
    return version;
  }

  @override
  void render(Canvas canvas, RenderContext ctx, RenderPassFilter filter) {
    final world = ctx.world;
    _using = definitions ?? world.context.definitions;
    if (!identical(world, _builtFor)) {
      _entries.clear();
      _byComponent.clear();
      _seenUpdates = world.updateCount;
      _rebuild(world);
    } else if (_queriesVersion(world) != _builtVersion || _paintersChanged()) {
      _rebuild(world);
    }
    final updates = world.updateCount;
    if (updates != _seenUpdates) {
      _seenUpdates = updates;
      for (final e in _entries) {
        e.checkCaptures();
      }
    }
    for (final e in _entries) {
      e.layer = e.painter.layerOfAny(e.component);
    }
    _sort(_entries);
    if (_added.isNotEmpty) {
      for (final e in _added) {
        e.layer = e.painter.layerOfAny(e.component);
      }
      _added.sort(_compare);
      _merge();
    }
    if (_entries.isEmpty) return;

    final alpha = ctx.interpolation;
    for (final e in _entries) {
      final entity = e.entity;
      if (!entity.isActiveInHierarchy || !filter(entity)) continue;
      if (!e.painter.isVisibleAny(e.component)) continue;
      final t = e.transform;
      double x, y, angle;
      if (e.fresh && alpha < 1.0) {
        final prev = t.prevPosition, now = t.position;
        x = prev.x + (now.x - prev.x) * alpha;
        y = prev.y + (now.y - prev.y) * alpha;
        angle = t.prevAngle + (t.angle - t.prevAngle) * alpha;
      } else {
        x = t.position.x;
        y = t.position.y;
        angle = t.angle;
      }
      canvas
        ..save()
        ..translate(x, y);
      // A turn of 0 and a scale of 1 change nothing: not sent.
      if (angle != 0.0) canvas.rotate(angle);
      final sx = t.scale.x, sy = t.scale.y;
      if (sx != 1.0 || sy != 1.0) canvas.scale(sx, sy);
      e.painter.paintAny(canvas, entity, e.component, ctx);
      canvas.restore();
    }
  }

  bool _paintersChanged() {
    var i = 0;
    for (final definition in _using.definitions) {
      if (definition.painter == null) continue;
      if (i >= _painted.length || !identical(_painted[i], definition)) {
        return true;
      }
      i++;
    }
    return i != _painted.length;
  }

  void _rebuild(World world) {
    final stamp = ++_stamp;
    _added.clear();
    _painted.clear();
    _queries.clear();
    var order = 0;
    for (final definition in _using.definitions) {
      final painter = definition.painter;
      if (painter == null) continue;
      _painted.add(definition);
      final type = definition.componentType;
      final query = List<Type>.unmodifiable([TransformComponent, type]);
      _queries.add(query);
      for (final archetype in world.queryArchetypes(query)) {
        final ids = archetype.entityIds;
        final transforms = archetype.getColumn(TransformComponent)!;
        final components = archetype.getColumn(type)!;
        for (var row = 0; row < ids.length; row++) {
          final component = components[row];
          if (component.runtimeType != type) continue;
          final entity = archetype.entityAt(row);
          final transform = transforms[row] as TransformComponent;
          var entry = _byComponent[component];
          if (entry == null ||
              entry.stamp == stamp ||
              !identical(entry.entity, entity)) {
            entry = _Paintable(entity, component);
            _byComponent[component] = entry;
            _added.add(entry);
          }
          if (!identical(entry._transform, transform)) {
            // Nothing seen of this transform yet: painted where it is until
            // a fixed update captures it.
            entry
              ..captures = transform.captureCount
              ..fresh = false;
          }
          entry
            ..stamp = stamp
            ..painter = painter
            ..transform = transform
            ..order = order;
        }
      }
      order++;
    }
    // What this rebuild did not find is gone; the rest keeps its order.
    _entries.removeWhere((e) {
      if (e.stamp == stamp) return false;
      if (identical(_byComponent[e.component], e)) {
        _byComponent.remove(e.component);
      }
      return true;
    });
    _builtFor = world;
    _builtVersion = _queriesVersion(world);
  }

  /// Merges [_added] (sorted) into [_entries] (sorted), from the back.
  void _merge() {
    final list = _entries;
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

  static int _compare(_Paintable a, _Paintable b) {
    if (a.layer != b.layer) return a.layer < b.layer ? -1 : 1;
    if (a.order != b.order) return a.order - b.order;
    return a.entity.id.compareTo(b.entity.id);
  }

  /// By insertion — linear when the order holds — and from scratch when
  /// much of it moved. The order is total, so either gives the same list.
  static void _sort(List<_Paintable> list) {
    var descents = 0;
    for (var i = 1; i < list.length; i++) {
      if (_compare(list[i - 1], list[i]) > 0 && ++descents > 16) break;
    }
    if (descents == 0) return;
    if (descents > 16) {
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

/// One component to paint, with its entity, painter and transform.
class _Paintable {
  _Paintable(this.entity, this.component);
  final Entity entity;
  final Component component;
  late ComponentPainter painter;
  TransformComponent? _transform;
  TransformComponent get transform => _transform!;
  set transform(TransformComponent value) => _transform = value;

  /// The rebuild that last found it.
  int stamp = 0;

  /// Its definition's place among those with painters.
  int order = 0;
  int layer = 0;

  /// [transform]'s capture count when last checked, and whether the last
  /// fixed update captured it.
  int captures = 0;
  bool fresh = false;

  void checkCaptures() {
    final count = transform.captureCount;
    fresh = count != captures;
    captures = count;
  }
}
