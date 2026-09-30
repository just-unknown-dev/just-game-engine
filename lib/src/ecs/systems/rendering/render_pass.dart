library;

import 'dart:ui';

import '../../components/components.dart';
import '../../ecs.dart';
import '../../serialization/component_definition.dart';
import '../../serialization/component_definition_registry.dart';

/// One stage of [RenderSystem]'s frame, run inside the camera transform.
///
/// The system's own stage draws every [RenderableComponent]; further stages
/// are added by passing them to the system, so a game can draw its own kinds
/// of thing — a tile map, a debug layer — without editing the engine.
abstract class RenderPass {
  const RenderPass();

  /// Passes run in ascending order.
  int get order => 0;

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
class ComponentPainterPass extends RenderPass {
  ComponentPainterPass({ComponentDefinitionRegistry? definitions})
    : _definitions = definitions;

  final ComponentDefinitionRegistry? _definitions;

  ComponentDefinitionRegistry get definitions =>
      _definitions ?? ComponentDefinitionRegistry.instance;

  @override
  int get order => 100;

  final List<_Paintable> _buffer = [];

  @override
  void render(Canvas canvas, RenderContext ctx, RenderPassFilter filter) {
    _buffer.clear();
    for (final definition in definitions.definitions) {
      final painter = definition.painter;
      if (painter == null) continue;
      for (final entity in ctx.world.query([
        TransformComponent,
        definition.componentType,
      ])) {
        if (!entity.isActive || !filter(entity)) continue;
        for (final component in entity.components) {
          if (component.runtimeType != definition.componentType) continue;
          if (!painter.isVisibleAny(component)) continue;
          _buffer.add(_Paintable(entity, component, painter));
        }
      }
    }
    if (_buffer.isEmpty) return;
    _buffer.sort((a, b) => a.layer.compareTo(b.layer));

    for (final item in _buffer) {
      final t = item.entity.getComponent<TransformComponent>()!;
      canvas
        ..save()
        ..translate(t.position.x, t.position.y)
        ..rotate(t.angle)
        ..scale(t.scale.x, t.scale.y);
      item.painter.paintAny(canvas, item.entity, item.component, ctx);
      canvas.restore();
    }
    _buffer.clear();
  }
}

class _Paintable {
  _Paintable(this.entity, this.component, this.painter)
    : layer = painter.layerOfAny(component);
  final Entity entity;
  final Component component;
  final ComponentPainter painter;
  final int layer;
}
