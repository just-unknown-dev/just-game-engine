library;

import 'dart:ui';

import '../../components/components.dart';
import '../../ecs.dart';
import '../../serialization/component_definition.dart';
import '../../serialization/component_presentation.dart';
import '../../serialization/component_definition_registry.dart';

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
/// registered painters change; each frame it re-reads the layers, re-sorts
/// by insertion — one pass when nothing moved — and paints. Components with
/// the same layer paint in the order they were found.
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
  final List<_Paintable> _pool = [];

  /// The definitions with painters the entries were found for, in order.
  final List<ComponentDefinition> _painted = [];
  World? _builtFor;
  int _builtVersion = -1;

  @override
  void render(Canvas canvas, RenderContext ctx, RenderPassFilter filter) {
    final world = ctx.world;
    _using = definitions ?? world.context.definitions;
    if (!identical(world, _builtFor) ||
        world.structureVersion != _builtVersion ||
        _paintersChanged()) {
      _rebuild(world);
    }
    if (_entries.isEmpty) return;

    for (final e in _entries) {
      e.layer = e.painter.layerOfAny(e.component);
    }
    _sort();

    for (final e in _entries) {
      final entity = e.entity;
      if (!entity.isActive || !filter(entity)) continue;
      if (!e.painter.isVisibleAny(e.component)) continue;
      final t = e.transform;
      canvas
        ..save()
        ..translate(t.position.x, t.position.y);
      // A turn of 0 and a scale of 1 change nothing: not sent.
      final angle = t.angle;
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
    _pool.addAll(_entries);
    _entries.clear();
    _painted.clear();
    var seq = 0;
    for (final definition in _using.definitions) {
      final painter = definition.painter;
      if (painter == null) continue;
      _painted.add(definition);
      final type = definition.componentType;
      for (final archetype in world.queryArchetypes([
        TransformComponent,
        type,
      ])) {
        final ids = archetype.entityIds;
        final transforms = archetype.getColumn(TransformComponent)!;
        final components = archetype.getColumn(type)!;
        for (var row = 0; row < ids.length; row++) {
          final component = components[row];
          if (component.runtimeType != type) continue;
          final entity = world.getEntity(ids[row]);
          if (entity == null) continue;
          _entries.add(
            (_pool.isNotEmpty ? _pool.removeLast() : _Paintable())
              ..entity = entity
              ..component = component
              ..painter = painter
              ..transform = transforms[row] as TransformComponent
              ..seq = seq++,
          );
        }
      }
    }
    _builtFor = world;
    _builtVersion = world.structureVersion;
  }

  static int _compare(_Paintable a, _Paintable b) {
    if (a.layer != b.layer) return a.layer < b.layer ? -1 : 1;
    return a.seq - b.seq;
  }

  /// By insertion — linear when the order holds — and from scratch when
  /// much of it moved. The order is total, so either gives the same list.
  void _sort() {
    final list = _entries;
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
  late Entity entity;
  late Component component;
  late ComponentPainter painter;
  late TransformComponent transform;
  int seq = 0;
  int layer = 0;
}
