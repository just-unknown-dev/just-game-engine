library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import '../../../subsystems/rendering/impl/sprite_batch.dart';
import '../../serialization/component_definition.dart';
import '../system_priorities.dart';
import 'render_pass.dart';

export 'render_pass.dart';

/// Render system - Renders ECS world-space renderables and UI components.
class RenderSystem extends System {
  @override
  int get priority => SystemPriorities.render;

  /// Optional camera used to transform world-space entities.
  final GameCamera? camera;

  /// Skips entities it returns false for, without touching them.
  ///
  /// A viewing aid for tools: an editor hiding a layer, or isolating the
  /// selection, filters here rather than flipping a component's visibility —
  /// which would be saved, and would change what the level does. Null, the
  /// default, draws everything and costs nothing.
  bool Function(Entity entity)? shouldRender;

  /// Factory for creating sprite-batch renderers from an atlas image.
  final SpriteBatchFactory _spriteBatchFactory;

  // ── Cached paint objects to avoid per-frame allocation ───────────────

  /// Reusable buffer for the depth-sorted (`Renderable.ySort`) pass — avoids
  /// per-frame list allocation. See the [ySort] handling in [render].
  final List<Renderable> _ySortBuffer = [];

  /// Cached [SpriteBatchRenderer] instances keyed by atlas image identity.
  /// Re-created only when the atlas image changes (e.g. hot-reload).
  final Map<int, SpriteBatchRenderer> _spriteBatches = {};

  /// Cached [Paint] for per-entity [ShaderComponent] saveLayer calls.
  /// Reused each frame to avoid allocation.
  final Paint _entityShaderPaint = Paint();

  /// Create a render system.
  ///
  /// [passes] run after the renderable pass, inside the camera transform, in
  /// ascending [RenderPass.order]. By default that is one
  /// [ComponentPainterPass], which draws every component whose definition
  /// has a painter — text, buttons, progress bars, and a game's own.
  RenderSystem({
    this.camera,
    SpriteBatchFactory? spriteBatchFactory,
    List<RenderPass>? passes,
  }) : _spriteBatchFactory =
           spriteBatchFactory ?? ((atlas) => SpriteBatch(atlas)),
       passes = List.unmodifiable(
         (passes ?? [ComponentPainterPass()])
           ..sort((a, b) => a.order.compareTo(b.order)),
       );

  /// The extra passes this system runs; see the constructor.
  final List<RenderPass> passes;

  @override
  List<Type> get requiredComponents => [TransformComponent];

  /// Whether some outer context has already applied the camera transform.
  /// When true, [render] skips its own save/transform/restore.
  ///
  /// **[RenderingEngine.onRenderOverlay] is NOT such a context**, despite what
  /// this doc used to claim. `RenderingEngine.render` calls `canvas.restore()`
  /// — ending the camera transform — immediately *before* invoking
  /// `onRenderOverlay`, which is where `World.render` runs. ECS systems
  /// therefore draw in **screen space** and each must apply the camera itself,
  /// which is exactly what [ColliderDebuggerSystem] and [PhysicsSystem.camera]
  /// do.
  ///
  /// So: pass [camera] to this system. Leaving it null makes every entity draw
  /// at its world coordinates interpreted as raw screen pixels — the scene
  /// collapses into the top-left corner and stops responding to panning and
  /// zooming. Nothing throws; it just renders wrongly, which makes it an
  /// unusually slow bug to track down.
  bool cameraAppliedExternally = false;

  /// Sub-frame interpolation factor in [0.0, 1.0].
  ///
  /// Set each tick by [GameWidget] from [GameLoop.interpolation] so that
  /// physics-driven entities are smoothly lerped between their previous and
  /// current positions, eliminating stutter on high-refresh-rate displays.
  /// Defaults to 1.0 (no interpolation — render at current position).
  double interpolation = 1.0;

  // ── Draw order ────────────────────────────────────────────────────────────
  //
  // world.query returns entities in archetype order, which is effectively
  // arbitrary and shifts as components are added or removed. That is fine
  // until a level has a background and a foreground, at which point "what
  // draws in front" becomes luck. LayerComponent makes it authorable, and a
  // RenderItem carries its own layer so one entity can draw at several
  // depths (a tile map's layers).
  //
  // Every renderable and every item becomes one entry in a single list,
  // sorted by (layer << 20) + zOrder, then by a sub-order — which keeps the
  // entities on a map layer between that layer's tiles and the next one's —
  // with the order it was found in as the last tie-break: `List.sort` is not
  // stable, so without it two things on the same layer could swap from one
  // frame to the next.

  /// The frame's draw list, reused so ordering does not allocate per frame.
  final List<_DrawEntry> _drawList = [];

  /// Entries recycled between frames.
  final List<_DrawEntry> _entryPool = [];

  /// Whether a sprite batch holds sprites not yet drawn, and at which key.
  bool _batchPending = false;
  int _batchKey = 0;
  int _batchSub = 0;

  _DrawEntry _takeEntry(
    Entity entity,
    RenderItem? item,
    int key,
    int sub,
    int seq,
  ) {
    final index = _drawList.length;
    final entry = index < _entryPool.length
        ? _entryPool[index]
        : (_entryPool..add(_DrawEntry())).last;
    entry
      ..entity = entity
      ..item = item
      ..key = key
      ..sub = sub
      ..seq = seq;
    _drawList.add(entry);
    return entry;
  }

  static int _compareEntries(_DrawEntry a, _DrawEntry b) {
    final byKey = a.key.compareTo(b.key);
    if (byKey != 0) return byKey;
    final bySub = a.sub.compareTo(b.sub);
    return bySub != 0 ? bySub : a.seq.compareTo(b.seq);
  }

  /// Fills [_drawList] with every renderable and item [filter] lets through,
  /// sorted when anything asked for an order.
  ///
  /// The early-out matters: most worlds never add a [LayerComponent] or an
  /// item, and they should not pay for a sort per frame. Entities without a
  /// layer sort as layer 0, so they interleave predictably with those that
  /// have one.
  void _collect(bool Function(Entity)? filter) {
    _drawList.clear();
    var seq = 0;
    var ordered = false;
    for (final entity in world.query([
      TransformComponent,
      RenderableComponent,
    ])) {
      if (filter != null && !filter(entity)) continue;
      final layer = entity.getComponent<LayerComponent>();
      var key = 0;
      if (layer != null) {
        if (layer.hiddenByMap) continue;
        ordered = true;
        // Layer and zOrder packed into one comparable int, so the sort is a
        // single integer compare rather than two lookups per comparison.
        key = (layer.layer << 20) + layer.zOrder;
      }
      _takeEntry(entity, null, key, layer?.subOrder ?? 0, seq++);
    }
    for (final entity in world.query([
      TransformComponent,
      RenderItemsComponent,
    ])) {
      if (filter != null && !filter(entity)) continue;
      if (_hiddenByMap(entity)) continue;
      for (final item in entity.getComponent<RenderItemsComponent>()!.items) {
        ordered = true;
        _takeEntry(
          entity,
          item,
          (item.layer << 20) + item.zOrder,
          item.subOrder,
          seq++,
        );
      }
    }
    if (ordered) _drawList.sort(_compareEntries);
  }

  /// Whether [entity] is on a map layer that is hidden.
  static bool _hiddenByMap(Entity entity) =>
      entity.getComponent<LayerComponent>()?.hiddenByMap ?? false;

  /// What [render] draws, in order: each entity with its item, or null for
  /// its renderable. For tests.
  @visibleForTesting
  List<(Entity, RenderItem?)> debugDrawOrder() {
    _collect(shouldRender);
    return [for (final e in _drawList) (e.entity, e.item)];
  }

  /// Draws every sprite batched so far.
  ///
  /// Called before anything that is not batched and whenever the draw key
  /// changes, so batching never reorders what the layers say: a sprite on
  /// the background still draws under a tile layer in front of it.
  void _flushBatches(Canvas canvas) {
    if (!_batchPending) return;
    for (final batch in _spriteBatches.values) {
      batch.flush(canvas);
    }
    _batchPending = false;
  }

  @override
  void render(Canvas canvas, Size size) {
    if (camera != null && !cameraAppliedExternally) {
      camera!.viewportSize = size;
      canvas.save();
      camera!.applyTransform(canvas, size);
    }

    final filter = shouldRender;
    _collect(filter);
    _batchPending = false;
    RenderContext? itemContext;

    // ── Batched sprite rendering ──────────────────────────────────────────
    // Consecutive sprites that share an atlas image and a draw key are
    // collected into a SpriteBatch and drawn in one Canvas.drawAtlas() call.
    for (final entry in _drawList) {
      final entity = entry.entity;
      if (!entity.isActive) continue;

      final item = entry.item;
      if (item != null) {
        if (!item.visible) continue;
        _flushBatches(canvas);
        item.render(
          canvas,
          itemContext ??= RenderContext(
            world: world,
            size: size,
            camera: camera,
            interpolation: interpolation,
          ),
          entity,
        );
        continue;
      }

      final transform = entity.getComponent<TransformComponent>()!;
      final renderComp = entity.getComponent<RenderableComponent>()!;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        // Sub-frame interpolation only applies to physics-driven entities.
        // PhysicsBridgeSystem captures prevPosition/prevRotation before each
        // physics step; non-physics entities (orbit, velocity, etc.) never
        // update prevPosition, so interpolating them renders them frozen at
        // their spawn position when interpolation ≈ 0 (the typical case at
        // matching UPS/FPS). Use position directly for non-physics entities.
        final hasPhysics = entity.hasComponent<PhysicsBodyRefComponent>();
        if (hasPhysics && interpolation < 1.0) {
          renderComp.renderable.position.setValues(
            transform.prevPosition.x +
                (transform.position.x - transform.prevPosition.x) *
                    interpolation,
            transform.prevPosition.y +
                (transform.position.y - transform.prevPosition.y) *
                    interpolation,
            transform.prevPosition.z +
                (transform.position.z - transform.prevPosition.z) *
                    interpolation,
          );
          renderComp.renderable.rotation =
              transform.prevRotation +
              (transform.rotation - transform.prevRotation) * interpolation;
        } else {
          renderComp.renderable.position.setFrom(transform.position);
          renderComp.renderable.rotation = transform.rotation;
        }
        renderComp.renderable.scale.setFrom(transform.scale);
      }

      if (!renderComp.renderable.visible) continue;

      // Depth-sorted entities (Renderable.ySort) skip both the batched and
      // immediate paths below — they're collected here and drawn afterward,
      // sorted by world-space Y, so e.g. a tree can draw in front of the
      // player when it's visually "further down" the screen and behind it
      // otherwise. Regular (non-ySort) entities are entirely unaffected —
      // same batch-or-immediate logic as before.
      if (renderComp.renderable.ySort) {
        _ySortBuffer.add(renderComp.renderable);
        continue;
      }

      // ── Per-entity shader detection ────────────────────────────────────
      final shaderComp = entity.getComponent<ShaderComponent>();
      final hasEntityShader =
          shaderComp != null && !shaderComp.isPostProcess && shaderComp.enabled;

      // Try to batch renderables that implement BatchableSprite.
      // Entities with a per-entity shader cannot be batched — they require an
      // isolated offscreen layer to composite the shader correctly.
      final renderable = renderComp.renderable;
      if (renderable is BatchableSprite &&
          (renderable as BatchableSprite).batchImage != null &&
          !hasEntityShader) {
        final batchable = renderable as BatchableSprite;
        final image = batchable.batchImage!;
        final key = identityHashCode(image);
        final batch = _spriteBatches.putIfAbsent(
          key,
          () => _spriteBatchFactory(image),
        );

        final srcRect =
            batchable.batchSourceRect ??
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );

        final tintColor =
            renderable.tint?.withValues(alpha: renderable.opacity) ??
            Color.fromRGBO(255, 255, 255, renderable.opacity);

        if (_batchPending &&
            (entry.key != _batchKey || entry.sub != _batchSub)) {
          _flushBatches(canvas);
        }
        _batchPending = true;
        _batchKey = entry.key;
        _batchSub = entry.sub;
        batch.add(
          sourceRect: srcRect,
          position: renderable.position.toOffset(),
          rotation: renderable.rotation,
          scale: (renderable.scale.x + renderable.scale.y) / 2,
          color: tintColor,
        );
      } else {
        // Non-sprite, image-less sprite, or entity with a per-entity shader:
        // render individually, optionally wrapped in a shader saveLayer —
        // after whatever was batched beneath it.
        _flushBatches(canvas);
        if (hasEntityShader) {
          final bounds = renderable.getBounds();
          // Fall back to a generous world-space rect if bounds are unknown.
          final effectRect =
              bounds ??
              Rect.fromCenter(
                center: renderable.position.toOffset(),
                width: size.width,
                height: size.height,
              );
          shaderComp.setUniforms?.call(
            shaderComp.shader,
            effectRect.width,
            effectRect.height,
            0.0, // per-entity mode: no time source in RenderSystem
          );
          _entityShaderPaint.imageFilter = ui.ImageFilter.shader(
            shaderComp.shader,
          );
          canvas.saveLayer(effectRect, _entityShaderPaint);
        }

        renderable.render(canvas, size);

        if (hasEntityShader) canvas.restore();
      }
    }

    // Whatever is still batched belongs to the topmost sorted content.
    _flushBatches(canvas);

    // Depth-sorted pass: draw every ySort-opted-in renderable individually,
    // ordered by world Y, on top of everything batched/drawn above. Drawing
    // individually (rather than via SpriteBatch) sacrifices atlas batching
    // for this group, but it's the only way to interleave draw order across
    // different atlases/renderable types — acceptable since this group is
    // expected to be view-culled down to a small on-screen count.
    if (_ySortBuffer.isNotEmpty) {
      _ySortBuffer.sort((a, b) => a.position.y.compareTo(b.position.y));
      for (final renderable in _ySortBuffer) {
        renderable.render(canvas, size);
      }
      _ySortBuffer.clear();
    }

    if (passes.isNotEmpty) {
      final context = RenderContext(
        world: world,
        size: size,
        camera: camera,
        interpolation: interpolation,
      );
      // What a hidden map layer holds is hidden in every pass — text too.
      bool passFilter(Entity e) =>
          !_hiddenByMap(e) && (filter == null || filter(e));
      for (final pass in passes) {
        pass.render(canvas, context, passFilter);
      }
    }

    if (camera != null && !cameraAppliedExternally) {
      canvas.restore();
    }
  }
}

/// One thing to draw this frame: an entity's renderable, or one of its
/// [RenderItem]s.
class _DrawEntry {
  late Entity entity;
  RenderItem? item;
  int key = 0;
  int sub = 0;
  int seq = 0;
}
