/// What 2-D lighting draws of a `RenderSystem`'s frame: its normals, and
/// what casts shadows.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show Material2DFile, Material2DKind;
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../../graphics/graphics_2d/materials/material_2d_batch.dart';
import '../../graphics/graphics_2d/materials/material_2d_component.dart';
import '../../graphics/graphics_2d/materials/material_2d_library.dart';
import '../../graphics/graphics_2d/materials/material_2d_shapes.dart';
import '../../graphics/graphics_2d/materials/materials_2d_context.dart'
    show ContextMaterials2D;
import '../../level_map/map_layer_painter.dart'
    show MapLayerPainter, MapLayerRenderItem;
import '../renderable.dart';
import '../sprite.dart';
import 'render_batcher.dart';
import 'render_queue.dart';

/// Draws, for `Lighting2DPass`, the normals and the shadow casters of what a
/// `RenderSystem` drew — in the same order and place, from its
/// [RenderQueue].
@internal
final class Lighting2DDrawer {
  /// The normals batch: sprites whose 2-D material has a normal map.
  Material2DBatch? _normalBatch;

  /// Draws a renderable's shape as a flat normal (see [drawNormals]).
  final Paint _flatPaint = Paint()
    ..colorFilter = const ColorFilter.mode(
      Color(MapLayerPainter.flatNormal),
      BlendMode.srcIn,
    );

  /// Draws a shadow caster's shape (see [drawOccluders]).
  final Paint _casterPaint = Paint();

  /// Lets go of the normals batch.
  void dispose() {
    _normalBatch?.dispose();
    _normalBatch = null;
  }

  /// Whether [entry] is drawn this frame: its entity on, not refused by
  /// [filter], not on a hidden map layer.
  static bool _drawn(RenderEntry entry, bool Function(Entity)? filter) =>
      entry.entity.isActiveInHierarchy &&
      (filter == null || filter(entry.entity)) &&
      !(entry.layer?.hiddenByMap ?? false);

  /// Draws, onto [canvas] (in world space), the normals of [entries] — red
  /// and green the normal's x and y in the world, blue how emissive, alpha
  /// where — with the poses the frame drew them at.
  ///
  /// A sprite, shape or tile layer whose 2-D material has a normal map (or
  /// is emissive) is drawn through it, its normals turned as it is turned.
  /// What is drawn over one of those is drawn flat, so it still hides it;
  /// anything else is left out, flat being what nothing drawn means.
  ///
  /// True when anything was drawn through a normal map or glows: when
  /// nothing was, the frame is flat and the normals need no image.
  bool drawNormals(
    Canvas canvas,
    Size size, {
    required List<RenderEntry> entries,
    required RenderBatcher batcher,
    required World world,
    required bool Function(Entity)? filter,
    required RenderContext Function() context,
    required double time,
  }) {
    final library = world.context.material2DLibrary;
    final batch = _normalBatch ??= Material2DBatch(library);
    batch.beginFrame();
    final definitions = world.context.definitions;
    var shaded = false;
    // What is drawn flat goes into one layer a run of it — between shaded
    // things — not a layer each: every layer is a render target of its own,
    // and a GPU runs out of them (Impeller on OpenGL ES aborts).
    var flatOpen = false;
    void closeFlat() {
      if (!flatOpen) return;
      canvas.restore();
      flatOpen = false;
    }

    RenderContext? itemContext;
    for (final entry in entries) {
      if (!_drawn(entry, filter)) continue;
      final item = entry.item;
      if (item != null) {
        if (!item.visible || item is! MapLayerRenderItem) continue;
        closeFlat();
        batch.flush(canvas, time);
        final drew = item.runtime.painter.paintNormals(
          canvas,
          itemContext ??= context(),
          entry.entity,
          item.layerId,
          flat: shaded,
        );
        shaded = shaded || drew;
        continue;
      }
      if (entry.emitter != null) continue;
      final renderable = entry.renderComp!.renderable;
      if (!renderable.visible) continue;
      final material = entry.material;
      final file = material == null || material.material.isEmpty
          ? null
          : library.fileOf(material.material);
      if (file != null &&
          file.kind == Material2DKind.sprite &&
          (file.isOn('normalMap') || file.isOn('emissive'))) {
        // Shaded things are queued: what is flat so far stays under them.
        closeFlat();
        if (_addNormals(
          canvas,
          batch,
          batcher,
          entry,
          renderable,
          material!,
          file,
          library,
          definitions,
          time,
        )) {
          shaded = true;
          continue;
        }
      }
      if (!shaded) continue;
      if (!flatOpen) {
        batch.flush(canvas, time);
        canvas.saveLayer(null, _flatPaint);
        flatOpen = true;
      }
      renderable.render(canvas, size);
    }
    closeFlat();
    batch.flush(canvas, time);
    return shaded;
  }

  /// Queues [renderable]'s normals into [batch]: its sheet's (or shape's)
  /// shape, with its material's normal map once read (a sprite's), else
  /// flat.
  bool _addNormals(
    Canvas canvas,
    Material2DBatch batch,
    RenderBatcher batcher,
    RenderEntry entry,
    Renderable renderable,
    Material2DComponent material,
    Material2DFile file,
    Material2DLibrary library,
    ComponentDefinitionRegistry definitions,
    double time,
  ) {
    if (library.normalsProgram == null) return false;
    ui.Image? sheet;
    ShapeSheet? shape;
    var quality = FilterQuality.medium;
    if (renderable is Sprite) {
      sheet = renderable.image;
      quality = renderable.filterQuality;
    } else {
      shape = batcher.sheetOf(
        canvas,
        entry,
        renderable,
        batcher.lookOf(entry, definitions),
      );
      sheet = shape?.image;
    }
    if (sheet == null) return false;
    final unitScale = shape?.resolution ?? 1.0;
    final map = file.isOn('normalMap') && shape == null
        ? library.imageOf(file.text('normalMap.map'))
        : null;
    if (!batch.isEmpty &&
        !batch.accepts(
          material.material,
          sheet,
          quality,
          unitScale: unitScale,
        )) {
      batch.flush(canvas, time);
    }
    bool add() {
      if (batch.isEmpty) {
        batch.begin(
          material.material,
          file,
          sheet!,
          quality,
          normals: true,
          normalMap: map,
          unitScale: unitScale,
        );
      }
      if (shape == null) {
        return batch.addSprite(
          renderable as Sprite,
          seed: entry.entity.id,
          overrides: material.overrides,
        );
      }
      return batch.addBox(
        shape.frame,
        shape.bounds,
        x: renderable.position.x,
        y: renderable.position.y,
        rotation: renderable.rotation,
        scaleX: renderable.scale.x,
        scaleY: renderable.scale.y,
        opacity: renderable.opacity,
        seed: entry.entity.id,
      );
    }

    if (!add()) {
      if (batch.isEmpty) return false;
      batch.flush(canvas, time);
      if (!add()) return false;
    }
    return true;
  }

  /// Draws, onto [canvas] (in world space), what casts shadows of [entries]
  /// — sprites and shapes with a `ShadowCaster2DComponent` on, Level Map
  /// layers that cast them — as their shapes, coloured by
  /// [MapLayerPainter.casterColor] of how far light reaches into them:
  /// 2-D lighting's mask. True when it drew anything.
  bool drawOccluders(
    Canvas canvas,
    Size size, {
    required List<RenderEntry> entries,
    required bool Function(Entity)? filter,
    required RenderContext Function() context,
  }) {
    var drew = false;
    // Casters of one depth share a layer, coloured as that depth: a layer
    // each would be a render target each (see [drawNormals]).
    double? layerDepth;
    void closeLayer() {
      if (layerDepth == null) return;
      canvas.restore();
      layerDepth = null;
    }

    RenderContext? itemContext;
    for (final entry in entries) {
      if (!_drawn(entry, filter)) continue;
      final item = entry.item;
      if (item != null) {
        if (!item.visible || item is! MapLayerRenderItem) continue;
        closeLayer();
        final cast = item.runtime.painter.paintSilhouette(
          canvas,
          itemContext ??= context(),
          entry.entity,
          item.layerId,
        );
        drew = drew || cast;
        continue;
      }
      if (entry.emitter != null) continue;
      final caster = entry.caster;
      if (caster == null || !caster.enabled) continue;
      final renderable = entry.renderComp!.renderable;
      if (!renderable.visible) continue;
      if (layerDepth != caster.depth) {
        closeLayer();
        _casterPaint.colorFilter = ColorFilter.mode(
          Color(MapLayerPainter.casterColor(caster.depth)),
          BlendMode.srcIn,
        );
        canvas.saveLayer(null, _casterPaint);
        layerDepth = caster.depth;
      }
      renderable.render(canvas, size);
      drew = true;
    }
    closeLayer();
    return drew;
  }
}
