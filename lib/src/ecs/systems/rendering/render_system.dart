library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import '../../../subsystems/particles/particles.dart';
import '../../../subsystems/rendering/impl/renderable.dart';
import '../../../subsystems/rendering/impl/sprite_batching.dart';
import '../../../subsystems/rendering/frame_view.dart';
import '../../../subsystems/rendering/render_stats.dart';
import '../../../subsystems/rendering/shader_filter_support.dart';
import '../../serialization/component_presentation.dart';
import '../../base/system_priorities.dart';
import 'render_pass.dart';
import 'shape_batch.dart';

export 'render_pass.dart';

/// Render system - Renders ECS world-space renderables and UI components.
///
/// It draws, in one sorted order, every entity's [RenderableComponent], each
/// [RenderItem] of a [RenderItemsComponent], and every
/// [ParticleEmitterComponent]'s emitter.
class RenderSystem extends System implements FrameSystem {
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
  /// Taken are [RectangleComponent]s with square corners and
  /// [CircleComponent]s whose fill and outline are plain colours (no
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
  /// Off by default. It is only as good as each renderable's `getBounds`,
  /// and a game's own renderables may report bounds that do not cover what
  /// they draw; and under a perspective camera (a pitched or yawed 3-D
  /// camera) the canvas's local clip bounds can be smaller than what is
  /// seen. With the built-in shapes and sprites on a 2-D camera, turning it
  /// on changes no pixel.
  bool cullOffscreen;

  /// Where each frame's counts are reported (see [stats]) — the engine's
  /// `RenderingEngine` for the default systems. Null reports nowhere.
  final RenderStatsSink? statsSink;

  // This frame's counts, then the last frame's; see [stats].
  int _drawCalls = 0;
  int _rendered = 0;
  int _culled = 0;
  int _batchedSprites = 0;
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

  /// Sprite batches by atlas image — the image object itself, not a hash of
  /// it — then by filter quality. A batch not used in a frame is dropped at
  /// its end, so an image the level no longer shows is not held.
  final SpriteBatchCache _spriteBatches;

  /// The batch holding sprites not drawn yet — at most one: a sprite from
  /// another image draws what is queued first, so batching never reorders.
  final List<SpriteBatchRenderer> _pendingSprites = [];

  /// Reused to work out how each sprite is batched.
  final SpriteBatchPlan _plan = SpriteBatchPlan();

  final ShapeBatch _shapeBatch = ShapeBatch();

  /// Cached [Paint] for per-entity [ShaderComponent] saveLayer calls.
  /// Reused each frame to avoid allocation.
  final Paint _entityShaderPaint = Paint();

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
  }) : _spriteBatches = SpriteBatchCache(spriteBatchFactory),
       // Sorted as a copy: the list passed in may be const, or the
       // caller's own.
       passes = List.unmodifiable(
         List.of(passes ?? [ComponentPainterPass()])
           ..sort((a, b) => a.order.compareTo(b.order)),
       );

  /// The extra passes this system runs; see the constructor.
  final List<RenderPass> passes;

  /// Where painters and items get the frame's camera as matrices
  /// ([RenderContext.view]) — `() => engine.rendering.view`, say. Null
  /// leaves them without, which a 2-D painter never needs.
  final FrameView Function()? viewOf;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

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
  int get debugSpriteBatchCount => _spriteBatches.length;

  /// The world-space rectangle the offscreen layer of [renderable]'s
  /// per-entity `ShaderComponent` covers. For tests.
  @visibleForTesting
  static Rect? debugShaderBounds(Renderable renderable) =>
      _shaderBounds(renderable);

  /// Drops every batch and every cached reference to the world's entities.
  void _release() {
    _spriteBatches.clear();
    _pendingSprites.clear();
    _shapeBatch.clear();
    _entryPool.clear();
    _entries.clear();
    _watches.clear();
    _builtFor = null;
  }

  // ── Draw order ────────────────────────────────────────────────────────────
  //
  // world.query returns entities in archetype order, which is effectively
  // arbitrary and shifts as components are added or removed. That is fine
  // until a level has a background and a foreground, at which point "what
  // draws in front" becomes luck. LayerComponent makes it authorable, and a
  // RenderItem carries its own layer so one entity can draw at several
  // depths (a tile map's layers).
  //
  // Every renderable, emitter and item becomes one entry in a single list,
  // sorted by layer, then zOrder, then a sub-order — which keeps the
  // entities on a map layer between that layer's tiles and the next one's —
  // then, for a renderable that asks for it (Renderable.ySort), by world y
  // after the rest of its place, with the order it was found in as the last
  // tie-break, so two things on the same layer never swap from one frame to
  // the next. An entity's LayerComponent gives its layer and zOrder; without
  // one, its renderable's own `layer` and `zOrder` do. Layer and zOrder
  // are compared as two numbers: they used to be packed into one by
  // shifting the layer left 20 bits, which on the web — where a shift makes
  // an unsigned 32-bit number — sorted every negative layer after all the
  // others.
  //
  // The list is kept between frames. It is rebuilt only when the world's
  // structure changes (an entity or a component added or removed) or an
  // entity's render items change; otherwise each frame refreshes the keys
  // and re-sorts by insertion, which costs one pass when nothing moved.
  // Each entry holds its entity's components, found once per archetype, so
  // a frame looks nothing up.

  /// Every entry, in draw order.
  final List<_DrawEntry> _entries = [];

  /// Entries recycled between rebuilds.
  final List<_DrawEntry> _entryPool = [];

  /// The render items each entity had when the list was built.
  final List<_ItemsWatch> _watches = [];

  World? _builtFor;

  /// The largest of the draw list's queries' versions when it was built.
  int _builtVersion = -1;

  /// [World.updateCount] when the entries' captures were last checked.
  int _seenUpdates = -1;

  /// What a rebuild knew of each transform's captures, so a rebuild does
  /// not stop interpolation for a step: its count times two, plus one when
  /// it was fresh.
  final Map<TransformComponent, int> _knownCaptures = Map.identity();

  /// Beyond this many out-of-order neighbours a frame sorts from scratch
  /// rather than by insertion.
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

  _DrawEntry _takeEntry() =>
      _entryPool.isNotEmpty ? _entryPool.removeLast() : _DrawEntry();

  /// The largest version of the queries the draw list is built from: it
  /// moves on only when what they match changes.
  int _queriesVersion() {
    final w = world;
    return math.max(
      w.queryVersion(_renderableQuery),
      math.max(w.queryVersion(_emitterQuery), w.queryVersion(_itemsQuery)),
    );
  }

  /// Brings the draw list up to date and into order.
  void _prepare() {
    if (!identical(_builtFor, world) ||
        _builtVersion != _queriesVersion() ||
        _itemsChanged()) {
      _rebuild();
    }
    final updates = world.updateCount;
    if (updates != _seenUpdates) {
      _seenUpdates = updates;
      for (final e in _entries) {
        e.checkCaptures();
      }
    }
    for (final e in _entries) {
      e.refreshKey();
    }
    _sortEntries();
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

  void _rebuild() {
    final known = _knownCaptures..clear();
    if (identical(_builtFor, world)) {
      for (final e in _entries) {
        final t = e.transform;
        if (t != null) known[t] = e.captures * 2 + (e.fresh ? 1 : 0);
      }
    } else {
      _seenUpdates = world.updateCount;
    }
    for (final e in _entries) {
      e.clear();
    }
    _entryPool.addAll(_entries);
    _entries.clear();
    _watches.clear();
    var seq = 0;

    for (final archetype in world.queryArchetypes(_renderableQuery)) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final renderables = archetype.getColumn(RenderableComponent)!;
      final layers = archetype.getColumn(LayerComponent);
      final shaders = archetype.getColumn(ShaderComponent);
      final hasPhysics = archetype.types.contains(PhysicsBodyRefComponent);
      final bodies = archetype.getColumn(PhysicsBodyRefComponent);
      for (var row = 0; row < ids.length; row++) {
        final transform = transforms[row] as TransformComponent;
        final physicsRef = bodies?[row] as PhysicsBodyRefComponent?;
        final entry = _takeEntry()
          ..entity = archetype.entityAt(row)
          ..transform = transform
          ..renderComp = renderables[row] as RenderableComponent
          ..layer = layers?[row] as LayerComponent?
          ..shader = shaders?[row] as ShaderComponent?
          ..hasPhysics = hasPhysics
          ..physicsRef = physicsRef
          ..seq = seq++;
        final seen = known[transform];
        if (seen != null) {
          entry
            ..captures = seen >> 1
            ..fresh = seen & 1 == 1;
        } else {
          // Nothing seen of it yet: a moving body's previous pose is taken
          // to be fresh, as physics captures it every step.
          entry
            ..captures = transform.captureCount
            ..fresh = hasPhysics && !(physicsRef?.body.isStatic ?? false);
        }
        _entries.add(entry);
      }
    }

    // Particle emitters draw their particles, which are in world space.
    for (final archetype in world.queryArchetypes(_emitterQuery)) {
      final ids = archetype.entityIds;
      final emitters = archetype.getColumn(ParticleEmitterComponent)!;
      final layers = archetype.getColumn(LayerComponent);
      final renderables = archetype.getColumn(RenderableComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final emitter = (emitters[row] as ParticleEmitterComponent).emitter;
        // Already drawn as the entity's renderable (how emitters had to be
        // shown before the render system drew them).
        final shown = renderables?[row] as RenderableComponent?;
        if (identical(shown?.renderable, emitter)) continue;
        _entries.add(
          _takeEntry()
            ..entity = entity
            ..emitter = emitter
            ..layer = layers?[row] as LayerComponent?
            ..seq = seq++,
        );
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
        for (final item in items) {
          _entries.add(
            _takeEntry()
              ..entity = entity
              ..item = item
              ..layer = layer
              ..seq = seq++,
          );
        }
      }
    }

    known.clear();
    _builtFor = world;
    _builtVersion = _queriesVersion();
  }

  static int _compareEntries(_DrawEntry a, _DrawEntry b) {
    if (a.layerKey != b.layerKey) return a.layerKey < b.layerKey ? -1 : 1;
    if (a.zKey != b.zKey) return a.zKey < b.zKey ? -1 : 1;
    if (a.sub != b.sub) return a.sub < b.sub ? -1 : 1;
    // What sorts by height (Renderable.ySort) draws after the rest of its
    // place, the highest on screen first.
    if (a.ySort != b.ySort) return a.ySort ? 1 : -1;
    final byY = a.yKey.compareTo(b.yKey);
    if (byY != 0) return byY;
    return a.seq - b.seq;
  }

  /// Sorts [_entries]: by insertion when only a few are out of place — one
  /// pass when none are — and from scratch otherwise. The order is total
  /// (the sequence number breaks every tie), so either gives the same list.
  void _sortEntries() {
    final list = _entries;
    var descents = 0;
    for (var i = 1; i < list.length; i++) {
      if (_compareEntries(list[i - 1], list[i]) > 0 &&
          ++descents > _insertionLimit) {
        break;
      }
    }
    if (descents == 0) return;
    if (descents > _insertionLimit) {
      list.sort(_compareEntries);
      return;
    }
    for (var i = 1; i < list.length; i++) {
      final e = list[i];
      var j = i - 1;
      if (_compareEntries(list[j], e) <= 0) continue;
      while (j >= 0 && _compareEntries(list[j], e) > 0) {
        list[j + 1] = list[j];
        j--;
      }
      list[j + 1] = e;
    }
  }

  /// What [render] draws, in order: each entity with its item, or null for
  /// its renderable. Particle emitters are not listed. For tests.
  @visibleForTesting
  List<(Entity, RenderItem?)> debugDrawOrder() {
    _prepare();
    final filter = shouldRender;
    return [
      for (final e in _entries)
        if (e.emitter == null &&
            e.entity.isActiveInHierarchy &&
            !(e.layer?.hiddenByMap ?? false) &&
            (filter == null || filter(e.entity)))
          (e.entity, e.item),
    ];
  }

  // ── Batches ───────────────────────────────────────────────────────────────

  /// The draw key of what the pending batches hold.
  int _batchLayer = 0, _batchZ = 0, _batchSub = 0;

  bool _sameBatchKey(_DrawEntry e) =>
      e.layerKey == _batchLayer && e.zKey == _batchZ && e.sub == _batchSub;

  void _setBatchKey(_DrawEntry e) {
    _batchLayer = e.layerKey;
    _batchZ = e.zKey;
    _batchSub = e.sub;
  }

  /// Draws every sprite batched so far.
  ///
  /// Called before anything that is not batched and whenever the draw key
  /// changes, so batching never reorders what the layers say: a sprite on
  /// the background still draws under a tile layer in front of it.
  void _flushSprites(Canvas canvas) {
    if (_pendingSprites.isEmpty) return;
    for (final batch in _pendingSprites) {
      batch.flush(canvas);
      _drawCalls++;
    }
    _pendingSprites.clear();
  }

  /// Draws every batched sprite and shape.
  void _flushBatches(Canvas canvas) {
    _flushSprites(canvas);
    if (!_shapeBatch.isEmpty) {
      _shapeBatch.flush(canvas);
      _drawCalls++;
    }
  }

  /// Queues [renderable] into a sprite batch; false when it must be drawn
  /// by itself. See [SpriteBatchPlan.plan] for which sprites batch.
  bool _addSprite(Canvas canvas, _DrawEntry entry, Renderable renderable) {
    final plan = _plan;
    if (!plan.plan(renderable)) return false;
    if (!_shapeBatch.isEmpty || !_sameBatchKey(entry)) _flushBatches(canvas);
    _setBatchKey(entry);
    final batch = _spriteBatches.batchFor(plan.image!, plan.quality);
    // Only the newest batch takes more: joining an older one would draw
    // this sprite under what another image's batch queued since.
    if (_pendingSprites.isEmpty || !identical(_pendingSprites.last, batch)) {
      _flushSprites(canvas);
      _pendingSprites.add(batch);
    }
    plan.addTo(batch);
    _rendered++;
    _batchedSprites++;
    return true;
  }

  /// Queues the shape [comp] draws into the shape batch; false when it must
  /// be drawn by itself.
  bool _addShape(
    Canvas canvas,
    _DrawEntry entry,
    RenderableComponent comp,
    Renderable renderable,
  ) {
    if (comp is! RectangleComponent && comp is! CircleComponent) return false;
    // Sprites queued before this shape, or shapes under another key, draw
    // first: a batch never moves anything ahead of what came before it.
    if (_pendingSprites.isNotEmpty ||
        (!_shapeBatch.isEmpty && !_sameBatchKey(entry))) {
      _flushBatches(canvas);
    }
    if (!_shapeBatch.tryAdd(comp, renderable)) return false;
    _setBatchKey(entry);
    _rendered++;
    return true;
  }

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

    _spriteBatches.beginFrame();
    _drawCalls = _rendered = _culled = _batchedSprites = 0;
    _prepare();
    final filter = shouldRender;
    final clip = cullOffscreen ? canvas.getLocalClipBounds() : null;
    final interpolating = interpolation < 1.0;
    RenderContext? itemContext;

    for (final entry in _entries) {
      final entity = entry.entity;
      if (!entity.isActiveInHierarchy) continue;
      if (filter != null && !filter(entity)) continue;
      if (entry.layer?.hiddenByMap ?? false) continue;

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
            view: viewOf?.call(),
          ),
          entity,
        );
        _drawCalls++;
        _rendered++;
        continue;
      }

      final emitter = entry.emitter;
      if (emitter != null) {
        if (!emitter.visible) continue;
        _flushBatches(canvas);
        emitter.render(canvas, size);
        _drawCalls++;
        _rendered++;
        continue;
      }

      final renderComp = entry.renderComp!;
      final renderable = renderComp.renderable;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        final transform = entry.transform!;
        // Sub-frame interpolation only for a transform whose previous pose
        // was captured in the last fixed update ([_DrawEntry.fresh]): a
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
          (clip != null && !_mayShow(renderable, clip))) {
        _culled++;
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
        if (renderable is BatchableSprite &&
            _addSprite(canvas, entry, renderable)) {
          continue;
        }
        if (batchShapes && _addShape(canvas, entry, renderComp, renderable)) {
          continue;
        }
      }

      // Non-sprite, image-less sprite, or entity with a per-entity shader:
      // render individually — after whatever was batched beneath it.
      _flushBatches(canvas);
      if (hasEntityShader) {
        _renderShaded(canvas, size, renderable, shaderComp);
      } else {
        renderable.render(canvas, size);
      }
      _drawCalls++;
      _rendered++;
    }

    // Whatever is still batched belongs to the topmost sorted content.
    _flushBatches(canvas);
    _spriteBatches.endFrame();

    if (passes.isNotEmpty) {
      final context = RenderContext(
        world: world,
        size: size,
        camera: camera,
        interpolation: interpolation,
        view: viewOf?.call(),
      );
      // What a hidden map layer holds is hidden in every pass — text too.
      bool passFilter(Entity e) =>
          !_hiddenByMap(e) && (filter == null || filter(e));
      for (final pass in passes) {
        pass.render(canvas, context, passFilter);
      }
    }

    if (applyCamera) canvas.restore();

    _lastDrawCalls = _drawCalls;
    _lastRendered = _rendered;
    _lastCulled = _culled;
    _lastBatchedSprites = _batchedSprites;
    statsSink?.addFrameStats(
      drawCalls: _drawCalls,
      renderedObjects: _rendered,
      culledObjects: _culled,
      batchedSprites: _batchedSprites,
    );
  }

  /// Whether [entity] is on a map layer that is hidden.
  static bool _hiddenByMap(Entity entity) =>
      entity.getComponent<LayerComponent>()?.hiddenByMap ?? false;

  /// Draws [renderable] through its [ShaderComponent]: an offscreen layer
  /// over its bounds, filtered by the shader.
  ///
  /// Where shaders cannot filter layers (the web, Skia) the renderable is
  /// drawn without the effect; see [ShaderFilterSupport].
  void _renderShaded(
    Canvas canvas,
    Size size,
    Renderable renderable,
    ShaderComponent shaderComp,
  ) {
    if (!ShaderFilterSupport.check('A per-entity ShaderComponent')) {
      renderable.render(canvas, size);
      return;
    }
    final effectRect =
        _shaderBounds(renderable) ??
        // Fall back to a generous world-space rect if bounds are unknown.
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
    // Made every frame on purpose: a shader filter copies the uniforms when
    // it is made, so a kept one would freeze an animated effect.
    _entityShaderPaint.imageFilter = ui.ImageFilter.shader(shaderComp.shader);
    canvas.saveLayer(effectRect, _entityShaderPaint);
    renderable.render(canvas, size);
    canvas.restore();
  }

  /// The world-space rectangle a shaded [renderable]'s layer covers.
  ///
  /// World-space bounds (a sprite's) are used as they are when the
  /// renderable is not turned; they are not turned with it, so for a turned
  /// one they are turned about its position, as it draws, and the box
  /// around them is used — as they were, the layer clipped a turned
  /// sprite's corners. Local bounds (a shape's, centred on its origin) are
  /// placed as the renderable is: used as they were, they put the layer —
  /// which clips — around the world origin, and the shape vanished.
  static Rect? _shaderBounds(Renderable renderable) {
    final bounds = renderable.getBounds();
    if (bounds == null) return null;
    if (renderable.boundsAreWorldSpace) {
      final angle = renderable.rotation;
      if (angle == 0.0) return bounds;
      final px = renderable.position.x, py = renderable.position.y;
      final c = math.cos(angle).abs(), s = math.sin(angle).abs();
      final dx = math.max((bounds.left - px).abs(), (bounds.right - px).abs());
      final dy = math.max((bounds.top - py).abs(), (bounds.bottom - py).abs());
      return Rect.fromCenter(
        center: Offset(px, py),
        width: 2 * (dx * c + dy * s),
        height: 2 * (dx * s + dy * c),
      );
    }
    return _placed(renderable, bounds);
  }

  /// Local [bounds] turned, scaled and moved as [renderable] is drawn: the
  /// world-space rectangle holding them.
  static Rect _placed(Renderable renderable, Rect bounds) {
    final px = renderable.position.x, py = renderable.position.y;
    final sx = renderable.scale.x, sy = renderable.scale.y;
    final angle = renderable.rotation;
    final cos = angle == 0.0 ? 1.0 : math.cos(angle);
    final sin = angle == 0.0 ? 0.0 : math.sin(angle);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var corner = 0; corner < 4; corner++) {
      final x = (corner & 1) == 0 ? bounds.left * sx : bounds.right * sx;
      final y = (corner & 2) == 0 ? bounds.top * sy : bounds.bottom * sy;
      final wx = px + cos * x - sin * y, wy = py + sin * x + cos * y;
      minX = math.min(minX, wx);
      maxX = math.max(maxX, wx);
      minY = math.min(minY, wy);
      maxY = math.max(maxY, wy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Whether [renderable] may draw inside [clip]: false only when its
  /// bounds, grown to cover any turn and scale, miss it entirely.
  static bool _mayShow(Renderable renderable, Rect clip) {
    final bounds = renderable.getBounds();
    if (bounds == null) return true;
    final (cx, cy, reach) = _reach(
      renderable,
      bounds,
      local: !renderable.boundsAreWorldSpace,
    );
    return cx + reach >= clip.left &&
        cx - reach <= clip.right &&
        cy + reach >= clip.top &&
        cy - reach <= clip.bottom;
  }

  /// A centre and a radius around it that hold everything [renderable]
  /// draws within [bounds], however it is turned or scaled.
  ///
  /// [local] bounds are around the renderable's origin: they turn and scale
  /// with it about its position. World-space bounds are taken as already
  /// placed, but not necessarily turned or scaled — a sprite's are not
  /// turned — so they are grown about the position by the largest scale.
  static (double, double, double) _reach(
    Renderable renderable,
    Rect bounds, {
    required bool local,
  }) {
    final px = renderable.position.x, py = renderable.position.y;
    final scale = math.max(renderable.scale.x.abs(), renderable.scale.y.abs());
    final ox = local ? 0.0 : px, oy = local ? 0.0 : py;
    final dx = math.max((bounds.left - ox).abs(), (bounds.right - ox).abs());
    final dy = math.max((bounds.top - oy).abs(), (bounds.bottom - oy).abs());
    final corner = math.sqrt(dx * dx + dy * dy);
    return (px, py, local ? corner * scale : corner * math.max(1.0, scale));
  }
}

/// One thing to draw: an entity's renderable, its emitter, or one of its
/// [RenderItem]s — with the entity's components, found when the list was
/// built.
class _DrawEntry {
  late Entity entity;
  RenderItem? item;
  ParticleEmitter? emitter;
  TransformComponent? transform;
  RenderableComponent? renderComp;
  LayerComponent? layer;
  ShaderComponent? shader;
  bool hasPhysics = false;
  PhysicsBodyRefComponent? physicsRef;
  int seq = 0;

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

  void clear() {
    item = null;
    emitter = null;
    transform = null;
    renderComp = null;
    layer = null;
    shader = null;
    hasPhysics = false;
    physicsRef = null;
    captures = 0;
    fresh = false;
  }
}

/// An entity's render items as they were when the draw list was built.
class _ItemsWatch {
  _ItemsWatch(this.component, this.items);
  final RenderItemsComponent component;
  final List<RenderItem> items;
}
