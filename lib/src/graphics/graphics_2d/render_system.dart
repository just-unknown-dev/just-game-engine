library;

import 'package:flutter/material.dart';

import '../../ecs/ecs.dart';
import '../../interfaces/interfaces.dart';
import '../../particles/particles.dart';
import '../../rendering/renderable.dart';
import '../../rendering/render_stats_sink.dart';
import 'materials/materials_2d_context.dart' show ContextMaterials2D;
import 'shapes/circle_2d_component.dart';
import 'shapes/rectangle_2d_component.dart';
import '../../rendering/layer_component.dart';
import '../../rendering/render_items_component.dart';
import '../../rendering/renderable_component.dart';
import '../../rendering/shader_component.dart';
import 'lighting_2d_drawer.dart';
import 'render_batcher.dart';
import 'render_bounds.dart';
import 'render_pass.dart';
import 'render_queue.dart';
import 'shaded_draw.dart';

/// Render system - Renders ECS world-space renderables and UI components.
///
/// It draws, in one sorted order, every entity's [RenderableComponent], each
/// [RenderItem] of a [RenderItemsComponent], and every
/// [ParticleEmitterComponent]'s emitter; then its [passes].
///
/// What it draws, and in what order, is its draw list ([RenderQueue], which
/// says how things are ordered); how it batches them is [RenderBatcher];
/// what 2-D lighting reads back of a frame ([renderNormals],
/// [renderOccluders]) is drawn by [Lighting2DDrawer].
class RenderSystem extends System implements PerFrame {
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

  /// Draws plain rectangles and circles together, a run of them in one
  /// `Canvas.drawVertices` call, where they would otherwise cost several
  /// canvas calls each.
  ///
  /// Taken are [Rectangle2DComponent]s with square corners and
  /// [Circle2DComponent]s whose fill and outline are plain colours (no
  /// gradient), whose outline is wider than zero, and whose entity is fully
  /// opaque, untinted and has no shader; everything else draws as before,
  /// and the draw order is kept. Off by default because triangles are not
  /// anti-aliased: a batched shape's edges are hard, and a circle is a
  /// polygon of 16 or 24 sides. Worth it for many small shapes — bullets,
  /// debris, a prototype's blocks.
  bool batchShapes;

  /// Skips renderables that lie wholly outside what the canvas shows.
  ///
  /// Once a frame the visible area is read from the canvas
  /// (`Canvas.getLocalClipBounds`, after the camera transform); a renderable
  /// whose bounds — grown to cover any turn and scale — miss it is not
  /// drawn. A renderable without bounds is always drawn, and so are render
  /// items and particle emitters.
  ///
  /// Off by default. It is only as good as each renderable's `bounds`,
  /// and a game's own renderables may report bounds that do not cover what
  /// they draw; and under a perspective camera (a pitched or yawed 3-D
  /// camera) the canvas's local clip bounds can be smaller than what is
  /// seen. With the built-in shapes and sprites on a 2-D camera, turning it
  /// on changes no pixel.
  bool cullOffscreen;

  /// Where each frame's counts are reported (see [stats]) — the engine's
  /// `RenderingEngine` for the default systems. Null reports nowhere.
  final RenderStatsSink? statsSink;

  /// This frame's counts, as they are drawn.
  final RenderCounts _counts = RenderCounts();

  // The last frame's counts; see [stats].
  int _lastDrawCalls = 0;
  int _lastRendered = 0;
  int _lastCulled = 0;
  int _lastBatchedSprites = 0;

  /// What the last [render] drew, with `RenderingEngine.stats`' keys:
  /// `drawCalls` (canvas draws, a batch as one), `renderedObjects` (things
  /// drawn — renderables, render items, particle emitters; a batched
  /// sprite or shape as one), `culledObjects` (renderables skipped as
  /// hidden or off screen) and `batchedSprites`. The extra [passes]' own
  /// drawing is not counted. The same counts go to [statsSink].
  Map<String, int> get stats => {
    'drawCalls': _lastDrawCalls,
    'renderedObjects': _lastRendered,
    'culledObjects': _lastCulled,
    'batchedSprites': _lastBatchedSprites,
  };

  /// What is drawn, in order.
  final RenderQueue _queue = RenderQueue();

  /// What batches it.
  late final RenderBatcher _batcher;

  /// Draws what 2-D lighting reads back of a frame.
  final Lighting2DDrawer _lighting = Lighting2DDrawer();

  /// Draws a renderable through its entity's own shader.
  final ShadedDraw _shaded = ShadedDraw();

  /// Create a render system.
  ///
  /// [passes] run after the renderable pass, inside the camera transform, in
  /// ascending [RenderPass.order]. By default that is one
  /// [ComponentPainterPass], which draws every component whose definition
  /// has a painter — text, buttons, progress bars, and a game's own.
  ///
  /// [batchShapes] and [cullOffscreen] are off by default; see each.
  ///
  /// [statsSink] — the engine's `RenderingEngine`, say — is told what each
  /// frame drew, so its stats count the world's drawing; see [stats].
  RenderSystem({
    this.camera,
    SpriteBatchFactory? spriteBatchFactory,
    List<RenderPass>? passes,
    this.viewOf,
    this.batchShapes = false,
    this.cullOffscreen = false,
    this.statsSink,
    this.clock,
  }) : // Sorted as a copy: the list passed in may be const, or the
       // caller's own.
       passes = List.unmodifiable(
         List.of(passes ?? [ComponentPainterPass()])
           ..sort((a, b) => a.order.compareTo(b.order)),
       ) {
    _batcher = RenderBatcher(_counts, spriteBatchFactory);
  }

  /// The extra passes this system runs; see the constructor.
  final List<RenderPass> passes;

  /// Seconds into the game, for what moves: a 2-D material (a wave, a
  /// shine), a per-entity [ShaderComponent]'s `time`, render items and
  /// painters ([RenderContext.time]) — `() => engine.time.totalTime`, say.
  /// Null stands still at 0.
  final double Function()? clock;

  /// Where painters and items get the frame's camera as matrices
  /// ([RenderContext.view]) — `() => engine.rendering.view`, say. Null
  /// leaves them without, which a 2-D painter never needs.
  final FrameView Function()? viewOf;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

  /// Whether some outer context has already applied the camera transform.
  /// When true, [render] skips its own save/transform/restore.
  ///
  /// **`RenderingEngine.overlayHooks` is NOT such a context.**
  /// `RenderingEngine.render` calls `canvas.restore()` — ending the camera
  /// transform — before it runs its overlay hooks, which is where
  /// `World.render` runs. ECS systems therefore draw in **screen space** and
  /// each must apply the camera itself, which is exactly what
  /// [Collider2DDebuggerSystem] does.
  ///
  /// So: pass [camera] to this system. Leaving it null makes every entity draw
  /// at its world coordinates interpreted as raw screen pixels — the scene
  /// collapses into the top-left corner and stops responding to panning and
  /// zooming. Nothing throws; it just renders wrongly, which makes it an
  /// unusually slow bug to track down.
  bool cameraAppliedExternally = false;

  /// Sub-frame interpolation factor in `[0.0, 1.0]`.
  ///
  /// Set each rendered frame from the frame phase's alpha ([frame]) — the
  /// game loop's [GameLoop.interpolation] — so that physics-driven entities
  /// are smoothly lerped between their previous and current positions,
  /// eliminating stutter on high-refresh-rate displays. Defaults to 1.0 (no
  /// interpolation — render at current position).
  double interpolation = 1.0;

  @override
  void frame(double deltaTime, double alpha) => interpolation = alpha;

  bool _attached = false;

  /// Whether this system is in a world: added, and not removed or disposed
  /// since. Something keeping a reference to the world's render system asks
  /// this before trusting it.
  bool get isAttached => _attached;

  @override
  void onAddedToWorld() => _attached = true;

  @override
  void onRemovedFromWorld() {
    _attached = false;
    _release();
  }

  @override
  void dispose() {
    _attached = false;
    _release();
  }

  /// How many sprite batches are kept — one per image and filter quality
  /// drawn in the last frame. For tests.
  @visibleForTesting
  int get debugSpriteBatchCount => _batcher.spriteBatchCount;

  /// The world-space rectangle the offscreen layer of [renderable]'s
  /// per-entity `ShaderComponent` covers. For tests.
  @visibleForTesting
  static Rect? debugShaderBounds(Renderable renderable) =>
      RenderBounds.shaderBounds(renderable);

  /// Drops every batch and every cached reference to the world's entities.
  void _release() {
    _batcher.clear();
    _lighting.dispose();
    _queue.clear();
  }

  /// What [render] draws, in order: each entity with its item, or null for
  /// its renderable. Particle emitters are not listed. For tests.
  @visibleForTesting
  List<(Entity, RenderItem?)> debugDrawOrder() {
    _queue.prepare(world);
    final filter = shouldRender;
    return [
      for (final e in _queue.entries)
        if (e.emitter == null &&
            e.entity.isActiveInHierarchy &&
            !(e.layer?.hiddenByMap ?? false) &&
            (filter == null || filter(e.entity)))
          (e.entity, e.item),
    ];
  }

  /// The context render items and painters draw with this frame.
  RenderContext _contextOf(Size size, double time) => RenderContext(
    world: world,
    size: size,
    camera: camera,
    interpolation: interpolation,
    view: viewOf?.call(),
    time: time,
  );

  // ── Frame ─────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    final cam = camera;
    final applyCamera = cam != null && !cameraAppliedExternally;
    if (applyCamera) {
      cam.viewportSize = size;
      canvas.save();
      cam.applyTransform(canvas, size);
    }

    final time = clock?.call() ?? 0.0;
    final batcher = _batcher..beginFrame(time);
    final counts = _counts..reset();
    _queue.prepare(world);
    final filter = shouldRender;
    final clip = cullOffscreen ? canvas.getLocalClipBounds() : null;
    final interpolating = interpolation < 1.0;
    final library = world.context.material2DLibrary;
    final definitions = world.context.definitions;
    RenderContext? itemContext;

    for (final entry in _queue.entries) {
      final entity = entry.entity;
      if (!entity.isActiveInHierarchy) continue;
      if (filter != null && !filter(entity)) continue;
      if (entry.layer?.hiddenByMap ?? false) continue;

      final item = entry.item;
      if (item != null) {
        if (!item.visible) continue;
        batcher.flush(canvas);
        item.render(canvas, itemContext ??= _contextOf(size, time), entity);
        counts
          ..drawCalls += 1
          ..rendered += 1;
        continue;
      }

      final emitter = entry.emitter;
      if (emitter != null) {
        if (!emitter.visible) continue;
        batcher.flush(canvas);
        emitter.render(canvas, size);
        counts
          ..drawCalls += 1
          ..rendered += 1;
        continue;
      }

      final renderComp = entry.renderComp!;
      final renderable = renderComp.renderable;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        final transform = entry.transform!;
        // Sub-frame interpolation only for a transform whose previous pose
        // was captured in the last fixed update ([RenderEntry.fresh]): a
        // moving physics body, or a child of one (the transform hierarchy
        // captures it with its parent's). Anything else — moved by
        // gameplay, or a static body — never captures, or not every step,
        // and its previous pose may be long out of date: drawn where it is.
        if (interpolating && entry.fresh) {
          final prev = transform.prevPosition, now = transform.position;
          renderable.position.setValues(
            prev.x + (now.x - prev.x) * interpolation,
            prev.y + (now.y - prev.y) * interpolation,
            prev.z + (now.z - prev.z) * interpolation,
          );
          renderable.rotation =
              transform.prevAngle +
              (transform.angle - transform.prevAngle) * interpolation;
        } else {
          renderable.position.setFrom(transform.position);
          renderable.rotation = transform.angle;
        }
        renderable.scale.setFrom(transform.scale);
      }

      if (!renderable.visible ||
          (clip != null && !RenderBounds.mayShow(renderable, clip))) {
        counts.culled++;
        continue;
      }

      // Depth-sorted entities (Renderable.ySort) are already in place: the
      // sort puts them after the rest of their layer and zOrder, by world
      // Y. (They used to be drawn after everything, without their shader.)

      // Entities with a per-entity shader cannot be batched — they require
      // an isolated offscreen layer to composite the shader correctly.
      final shaderComp = entry.shader;
      final hasEntityShader =
          shaderComp != null && !shaderComp.isPostProcess && shaderComp.enabled;
      if (!hasEntityShader) {
        final material = entry.material;
        if (material != null &&
            material.material.isNotEmpty &&
            batcher.addMaterial(
              canvas,
              entry,
              renderable,
              material,
              library,
              definitions,
            )) {
          continue;
        }
        if (renderable is BatchableSprite &&
            batcher.addSprite(canvas, entry, renderable)) {
          continue;
        }
        if (batchShapes &&
            batcher.addShape(canvas, entry, renderComp, renderable)) {
          continue;
        }
      }

      // Non-sprite, image-less sprite, or entity with a per-entity shader:
      // render individually — after whatever was batched beneath it.
      batcher.flush(canvas);
      if (hasEntityShader) {
        _shaded.draw(canvas, size, renderable, shaderComp, time);
      } else {
        renderable.render(canvas, size);
      }
      counts
        ..drawCalls += 1
        ..rendered += 1;
    }

    // Whatever is still batched belongs to the topmost sorted content.
    batcher
      ..flush(canvas)
      ..endFrame();

    if (passes.isNotEmpty) {
      final context = _contextOf(size, time);
      // What a hidden map layer holds is hidden in every pass — text too.
      bool passFilter(Entity e) =>
          !_hiddenByMap(e) && (filter == null || filter(e));
      for (final pass in passes) {
        pass.render(canvas, context, passFilter);
      }
    }

    if (applyCamera) canvas.restore();

    _lastDrawCalls = counts.drawCalls;
    _lastRendered = counts.rendered;
    _lastCulled = counts.culled;
    _lastBatchedSprites = counts.batchedSprites;
    statsSink?.addFrameStats(
      drawCalls: counts.drawCalls,
      renderedObjects: counts.rendered,
      culledObjects: counts.culled,
      batchedSprites: counts.batchedSprites,
    );
  }

  /// Whether [entity] is on a map layer that is hidden.
  static bool _hiddenByMap(Entity entity) =>
      entity.getComponent<LayerComponent>()?.hiddenByMap ?? false;

  // ── For 2-D lighting ──────────────────────────────────────────────────────

  /// Runs [draw] inside the camera transform, unless something outside
  /// applies it ([cameraAppliedExternally]).
  bool _inCamera(Canvas canvas, Size size, bool Function() draw) {
    final cam = camera;
    final applyCamera = cam != null && !cameraAppliedExternally;
    if (applyCamera) {
      canvas.save();
      cam.applyTransform(canvas, size);
    }
    final drew = draw();
    if (applyCamera) canvas.restore();
    return drew;
  }

  /// Draws, onto [canvas], the normals of what [render] last drew — in the
  /// same order and place — for 2-D lighting ([Lighting2DComponent]): red
  /// and green the normal's x and y in the world, blue how emissive, alpha
  /// where.
  ///
  /// A sprite, shape or tile layer whose 2-D material has a normal map (or
  /// is emissive) is drawn through it, its normals turned as it is turned.
  /// What is drawn over one of those is drawn flat, so it still hides it;
  /// anything else is left out, flat being what nothing drawn means. Call
  /// after [render], in the same frame: it draws with the poses that set.
  ///
  /// True when anything was drawn through a normal map or glows: when
  /// nothing was, the frame is flat and the normals need no image.
  bool renderNormals(Canvas canvas, Size size) {
    final time = clock?.call() ?? 0.0;
    return _inCamera(
      canvas,
      size,
      () => _lighting.drawNormals(
        canvas,
        size,
        entries: _queue.entries,
        batcher: _batcher,
        world: world,
        filter: shouldRender,
        context: () => _contextOf(size, time),
        time: time,
      ),
    );
  }

  /// Draws, onto [canvas], what casts shadows of what [render] last drew —
  /// sprites and shapes with a `ShadowCaster2DComponent` on, Level Map
  /// layers that cast them — as their shapes, coloured by how far light
  /// reaches into them: 2-D lighting's mask. True when it drew anything.
  /// Call after [render], in the same frame.
  bool renderOccluders(Canvas canvas, Size size) {
    final time = clock?.call() ?? 0.0;
    return _inCamera(
      canvas,
      size,
      () => _lighting.drawOccluders(
        canvas,
        size,
        entries: _queue.entries,
        filter: shouldRender,
        context: () => _contextOf(size, time),
      ),
    );
  }
}
