/// Rendering Engine (Graphics)
///
/// Handles visual representation, 2D sprites, shapes, text rendering, and effects.
/// This module manages the rendering pipeline for the game engine using Flutter Canvas.
library;

import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'render_hook_chain.dart';
import 'render_stats.dart';
import 'frame_view.dart';
import 'scene_renderer.dart';
import 'impl/renderable.dart';
import 'impl/sprite_batch.dart';
import 'impl/sprite_batching.dart';
import 'shader_filter_support.dart';
import 'screen_pass.dart';
import '../post_processing/post_process_pass.dart';
import '../particles/particles.dart';
import '../camera/camera_system.dart';
import '../../interfaces/rendering_interfaces.dart';
import 'package:just_dart/just_dart.dart';

export 'impl/renderable.dart';
export 'impl/sprite_batch.dart';
export 'frame_view.dart';
export 'scene_renderer.dart';
export 'render_stats.dart';

/// Main rendering engine class responsible for graphics rendering
///
/// This class manages the rendering pipeline, camera, and all renderable objects.
/// It uses Flutter's Canvas API for 2D rendering.
///
/// It is also a [RenderStatsSink]: the ECS world's `RenderSystem` reports
/// what it draws here, so [stats] count the whole frame.
class RenderingEngine implements RenderStatsSink {
  /// List of all renderable objects
  final List<Renderable> _renderables = [];

  /// Set for O(1) membership checks in addRenderable
  final Set<Renderable> _renderableSet = {};

  /// Standalone managed particle emitters updated automatically each frame.
  ///
  /// Use [addManagedEmitter] / [removeManagedEmitter] instead of accessing
  /// this list directly.
  final List<ParticleEmitter> _managedEmitters = [];

  /// Rendering layers — LinkedHashSet per layer for O(1) add/remove.
  final Map<int, LinkedHashSet<Renderable>> _layers = {};

  /// Sorted-by-zOrder snapshot of each layer, rebuilt when [_layersDirty].
  /// The render loop iterates this instead of [_layers] to maintain zOrder.
  final Map<int, List<Renderable>> _sortedLayerLists = {};

  /// Main camera
  late Camera camera;

  /// Background color
  Color backgroundColor = const Color(0xFF1a1a2e);

  /// Whether the engine is initialized
  bool _initialized = false;

  /// Called in screen space after the background clear but before the
  /// camera transform. [ParallaxSystem] paints its backgrounds here.
  final RenderHookChain backgroundHooks = RenderHookChain();

  /// Called inside the camera-transformed context after every subsystem
  /// layer, so ECS world rendering (and anything drawn over it) shares the
  /// one camera transform. [GameWidget] adds `engine.world.render`.
  ///
  /// A chain, not a single field: several things — the world, an editor, a
  /// debug overlay — draw here, and with a single field the first writer won
  /// and the rest were silently dropped.
  final RenderHookChain overlayHooks = RenderHookChain();

  RenderHook? _legacyBackground;
  RenderHook? _legacyOverlay;

  /// The hook last assigned through the setter, for callers that still read
  /// it back.
  @Deprecated('Use backgroundHooks.add / remove')
  RenderHook? get onRenderBackground => _legacyBackground;

  /// Assigning replaces only the hook this setter previously added; hooks
  /// added through [backgroundHooks] directly are untouched.
  @Deprecated('Use backgroundHooks.add / remove')
  set onRenderBackground(RenderHook? hook) {
    if (_legacyBackground != null) backgroundHooks.remove(_legacyBackground!);
    _legacyBackground = hook;
    if (hook != null) backgroundHooks.add(hook);
  }

  /// The hook last assigned through the setter, for callers that still read
  /// it back.
  @Deprecated('Use overlayHooks.add / remove')
  RenderHook? get onRenderOverlay => _legacyOverlay;

  /// Assigning replaces only the hook this setter previously added; hooks
  /// added through [overlayHooks] directly are untouched.
  @Deprecated('Use overlayHooks.add / remove')
  set onRenderOverlay(RenderHook? hook) {
    if (_legacyOverlay != null) overlayHooks.remove(_legacyOverlay!);
    _legacyOverlay = hook;
    if (hook != null) overlayHooks.add(hook);
  }

  /// Debug mode flag
  bool debugMode = false;

  // ── Scene renderers and the frame's view ─────────────────────────────

  final List<SceneRenderer> _sceneRenderers = [];

  /// The registered [SceneRenderer]s, in draw order.
  List<SceneRenderer> get sceneRenderers => List.unmodifiable(_sceneRenderers);

  /// Adds [renderer] to the frame (see [SceneRenderer] for where it draws).
  void addSceneRenderer(SceneRenderer renderer) {
    if (_sceneRenderers.contains(renderer)) return;
    _sceneRenderers
      ..add(renderer)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Removes [renderer]; true when it was there.
  bool removeSceneRenderer(SceneRenderer renderer) =>
      _sceneRenderers.remove(renderer);

  final FrameView _view = FrameView();
  bool _viewStale = true;

  /// How far between two fixed steps the coming frame is drawn (0..1), set
  /// each frame by the engine from the game loop. [view] passes it on.
  double interpolation = 1.0;

  /// The camera of the frame being drawn, as matrices — filled at most once
  /// a frame, and only when read, so a 2-D game pays nothing for it.
  FrameView get view {
    if (_viewStale) {
      _view.update(camera, camera.viewportSize, interpolation: interpolation);
      _viewStale = false;
    }
    return _view;
  }

  /// Optional factory for creating [SpriteBatchRenderer] instances.
  /// Defaults to the built-in [SpriteBatch] implementation. A [SpriteBatch]
  /// it returns is set to the filter quality of the sprites it batches.
  SpriteBatchFactory spriteBatchFactory = (ui.Image atlas) =>
      SpriteBatch(atlas);

  /// Sprite batches by atlas image (the object, not a hash of it) and filter
  /// quality; one a frame does not use is dropped at its end.
  final SpriteBatchCache _batchCache = SpriteBatchCache();

  /// Batches holding sprites not drawn yet, in the order first used.
  final List<SpriteBatchRenderer> _pendingBatches = [];

  /// Reused to work out how each sprite is batched.
  final SpriteBatchPlan _plan = SpriteBatchPlan();

  /// How many sprite batches are kept — one per image and filter quality
  /// drawn in the last frame. For tests.
  @visibleForTesting
  int get debugSpriteBatchCount => _batchCache.length;

  /// Spatial index for fast viewport culling.
  ///
  /// When [useSpatialIndex] is `true` and there are more than
  /// [_spatialThreshold] renderables, the quadtree is rebuilt each frame and
  /// used to query only those renderables overlapping the camera viewport.
  /// For smaller scenes the O(n) scan is faster due to lower overhead.
  @Deprecated(
    'Only renderables added with addRenderable are culled by it. Use '
    'RenderSystem(cullOffscreen: true) for entities. Removed in 3.0.',
  )
  bool get useSpatialIndex => _useSpatialIndex;
  @Deprecated(
    'Only renderables added with addRenderable are culled by it. Use '
    'RenderSystem(cullOffscreen: true) for entities. Removed in 3.0.',
  )
  set useSpatialIndex(bool value) => _useSpatialIndex = value;
  bool _useSpatialIndex = true;
  static const int _spatialThreshold = 200;
  Quadtree<Renderable>? _quadtree;
  final List<Renderable> _quadtreeResults = [];
  final Set<Renderable> _spatialVisibleSet = <Renderable>{};
  final Map<Renderable, Rect?> _boundsCache = <Renderable, Rect?>{};
  final Map<Renderable, int> _trackedLayers = <Renderable, int>{};
  final Map<Renderable, int> _trackedZOrders = <Renderable, int>{};
  Rect? _spatialIndexBounds;
  bool _spatialIndexDirty = true;

  double _lastRenderTimeMs = 0.0;
  int _lastDrawCallCount = 0;
  int _lastRenderedCount = 0;
  int _lastCulledCount = 0;
  int _lastBatchedSpriteCount = 0;
  bool _lastUsedSpatialIndex = false;

  // What other drawers reported this frame ([addFrameStats]).
  int _reportedDrawCalls = 0;
  int _reportedRendered = 0;
  int _reportedCulled = 0;
  int _reportedBatchedSprites = 0;

  @override
  void addFrameStats({
    int drawCalls = 0,
    int renderedObjects = 0,
    int culledObjects = 0,
    int batchedSprites = 0,
  }) {
    _reportedDrawCalls += drawCalls;
    _reportedRendered += renderedObjects;
    _reportedCulled += culledObjects;
    _reportedBatchedSprites += batchedSprites;
  }

  int _spatialRebuildCount = 0;
  bool _spatialReusedLastFrame = false;

  // Persistent Stopwatch instance — reused every frame to avoid heap allocation.
  final Stopwatch _renderStopwatch = Stopwatch();

  // ── Post-process pass pipeline ─────────────────────────────────────────

  /// Registered fullscreen post-process passes (ordered for sort).
  ///
  /// Managed via [addPostProcessPass] / [removePostProcessPass].
  /// [PostProcessSystem] populates this list each frame from ECS entities.
  final List<PostProcessPass> _postProcessPasses = [];

  /// O(1) membership set that mirrors [_postProcessPasses].
  /// Prevents duplicate insertions without O(n) list scan.
  final Set<PostProcessPass> _postProcessPassSet = {};

  /// Cached sorted pass list rebuilt when the pass set changes.
  final List<PostProcessPass> _sortedPasses = [];
  bool _passListDirty = false;

  /// Elapsed engine time in seconds, written each frame by [PostProcessSystem]
  /// (or set manually when using the pass pipeline without ECS).
  ///
  /// Forwarded to every [PostProcessPass.setUniforms] callback.
  double elapsedSeconds = 0.0;

  /// Cached fullscreen rect reused every render to avoid per-frame allocation.
  Rect _fullscreenRect = Rect.zero;

  /// Drawn over the whole frame from an image of it — 2-D lighting, a
  /// screen material — those [ScreenPass.active], in order, each from what
  /// the one before drew; see [render].
  final List<ScreenPass> screenPasses = [];

  /// Overlay hooks below this order are drawn under a [screenPass], and
  /// those at it or above (an editor's) over it.
  static const int screenPassOrder = 100;

  /// How many device pixels a logical pixel is, for the image a
  /// [screenPass] is drawn from; the view's own when null.
  double? pixelRatio;

  double get _pixelRatio =>
      pixelRatio ??
      ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
      1.0;

  // The frame images a screen pass drew from, let go a frame later.
  final List<ui.Image> _screenFrames = [];
  final List<ui.Image> _oldScreenFrames = [];

  /// Cached [Paint] for post-process `saveLayer` calls.
  final Paint _postProcessPaint = Paint();

  /// Register a [PostProcessPass] with the render pipeline.
  ///
  /// The pass will be included in the scene-wrapping shader chain starting
  /// from the next rendered frame. Duplicate insertions are silently ignored.
  void addPostProcessPass(PostProcessPass pass) {
    if (_postProcessPassSet.add(pass)) {
      _postProcessPasses.add(pass);
      _passListDirty = true;
    }
  }

  /// Remove a [PostProcessPass] from the render pipeline.
  ///
  /// Has no effect if the pass is not currently registered.
  void removePostProcessPass(PostProcessPass pass) {
    if (_postProcessPassSet.remove(pass)) {
      _postProcessPasses.remove(pass);
      _passListDirty = true;
    }
  }

  /// The registered post-process passes, innermost ([PostProcessPass.passOrder]
  /// lowest) first — the order they are applied in.
  List<PostProcessPass> get postProcessPasses {
    _sortPasses();
    return List.unmodifiable(_sortedPasses);
  }

  /// Sorts the passes by order when one was added or removed, or a pass's
  /// order changed since.
  void _sortPasses() {
    if (!_passListDirty && _passesInOrder()) return;
    _sortedPasses
      ..clear()
      ..addAll(_postProcessPasses)
      ..sort((a, b) => a.passOrder.compareTo(b.passOrder));
    _passListDirty = false;
  }

  // ── Cached Paint objects (avoid per-frame allocation) ──────────────────
  final Paint _backgroundPaint = Paint();
  final Paint _debugBoundsPaint = Paint()
    ..color =
        const Color(0x8000FF00) // green at 50% alpha
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _debugOriginPaint = Paint()..color = const Color(0xFFFF0000);

  /// Cached TextPainter for debug info overlay.
  final TextPainter _debugTextPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  // ── Cached layer key list (avoids per-frame allocation) ────────────────
  final List<int> _sortedLayerKeys = [];
  bool _layersDirty = true;

  /// Get initialization status
  bool get isInitialized => _initialized;

  /// Get all renderables (sorted by layer then zOrder)
  @Deprecated(
    'Lists only renderables added with addRenderable. Query the world for '
    'RenderableComponent instead. Removed in 3.0.',
  )
  List<Renderable> get renderables {
    final sorted = List<Renderable>.from(_renderables);
    sorted.sort((a, b) {
      final layerCompare = a.layer.compareTo(b.layer);
      if (layerCompare != 0) return layerCompare;
      return a.zOrder.compareTo(b.zOrder);
    });
    return List.unmodifiable(sorted);
  }

  /// Initialize the rendering engine
  void initialize() {
    if (_initialized) return;

    _initialized = true;
    if (kDebugMode) debugPrint('Rendering Engine initialized');
  }

  // ── Managed particle emitters ──────────────────────────────────────────────

  /// Register a [ParticleEmitter] so it is updated and rendered automatically
  /// each frame without requiring an ECS entity.
  ///
  /// Useful for fire-and-forget effects (e.g. impact bursts) that don't need
  /// game-object identity.  The emitter is also added as a [Renderable] so it
  /// participates in layer-based rendering normally.
  ///
  /// Completed emitters (no more emissions + no live particles) are removed
  /// automatically during [updateManagedEmitters].
  @Deprecated(
    'Add a ParticleEmitterComponent (removeEntityWhenComplete: true) to '
    'an entity; ParticleSystemECS updates it and RenderSystem draws it. '
    'Removed in 3.0.',
  )
  void addManagedEmitter(ParticleEmitter emitter) {
    if (!_managedEmitters.contains(emitter)) {
      _managedEmitters.add(emitter);
      _addRenderable(emitter);
    }
  }

  /// Unregister a [ParticleEmitter] that was previously added via
  /// [addManagedEmitter], stopping its automatic update and removing it from
  /// rendering.
  @Deprecated(
    'Destroy the entity holding the ParticleEmitterComponent, or remove the '
    'component. Removed in 3.0.',
  )
  void removeManagedEmitter(ParticleEmitter emitter) {
    if (_managedEmitters.remove(emitter)) {
      _removeRenderable(emitter);
    }
  }

  /// Advance all managed particle emitters by [deltaTime] seconds.
  ///
  /// Called automatically by the engine's update loop.  Completed emitters
  /// are removed from the list and unregistered from rendering.
  @Deprecated(
    'Emitters on entities (ParticleEmitterComponent) are updated by '
    'ParticleSystemECS. Removed in 3.0.',
  )
  void updateManagedEmitters(double deltaTime) {
    // Iterate backwards so index removal is safe
    for (int i = _managedEmitters.length - 1; i >= 0; i--) {
      final emitter = _managedEmitters[i];
      emitter.update(deltaTime);
      if (emitter.isComplete) {
        _managedEmitters.removeAt(i);
        _removeRenderable(emitter);
      }
    }
  }

  /// Add a renderable object to the scene
  ///
  /// [renderable] - The object to render
  @Deprecated(
    'Add a RenderableComponent holding the renderable to an entity; '
    'RenderSystem draws it. Removed in 3.0.',
  )
  void addRenderable(Renderable renderable) => _addRenderable(renderable);

  void _addRenderable(Renderable renderable) {
    if (_renderableSet.add(renderable)) {
      _renderables.add(renderable);
      _trackRenderable(renderable);
      _addToLayer(renderable);
      _spatialIndexDirty = true;
    }
  }

  /// Remove a renderable object from the scene
  ///
  /// [renderable] - The object to remove
  @Deprecated(
    'Destroy the entity holding the RenderableComponent, or remove the '
    'component. Removed in 3.0.',
  )
  void removeRenderable(Renderable renderable) => _removeRenderable(renderable);

  void _removeRenderable(Renderable renderable) {
    if (_renderableSet.remove(renderable)) {
      _renderables.remove(renderable);
      // Out of the layer it was filed under before the tracking goes: a
      // renderable moved to another layer since the last frame is still in
      // its old one, and used to stay there — drawn — after removal.
      _removeFromLayer(renderable);
      _untrackRenderable(renderable);
      _spatialIndexDirty = true;
    }
  }

  /// Add a renderable to its layer
  void _addToLayer(Renderable renderable) {
    _layers
        .putIfAbsent(renderable.layer, () => LinkedHashSet<Renderable>())
        .add(renderable);
    _layersDirty = true;
  }

  /// Remove a renderable from the layer it is filed under
  void _removeFromLayer(Renderable renderable) {
    final filed = _trackedLayers[renderable] ?? renderable.layer;
    _layers[filed]?.remove(renderable);
    if (filed != renderable.layer) {
      _layers[renderable.layer]?.remove(renderable);
    }
    _layersDirty = true;
  }

  void _trackRenderable(Renderable renderable) {
    _trackedLayers[renderable] = renderable.layer;
    _trackedZOrders[renderable] = renderable.zOrder;
    _boundsCache[renderable] = renderable.getBounds();
  }

  void _untrackRenderable(Renderable renderable) {
    _trackedLayers.remove(renderable);
    _trackedZOrders.remove(renderable);
    _boundsCache.remove(renderable);
  }

  /// Mark layer sorting as dirty after direct renderable mutation.
  @Deprecated(
    'Only for renderables added with addRenderable; RenderSystem sorts '
    'and culls entities itself. Removed in 3.0.',
  )
  void markLayerOrderDirty() {
    _layersDirty = true;
  }

  /// Mark the spatial index as dirty after direct transform mutation.
  @Deprecated(
    'Only for renderables added with addRenderable; RenderSystem sorts '
    'and culls entities itself. Removed in 3.0.',
  )
  void markSpatialIndexDirty() {
    _spatialIndexDirty = true;
  }

  /// Clear all renderables
  void clear() {
    _renderables.clear();
    _renderableSet.clear();
    _layers.clear();
    _sortedLayerLists.clear();
    _boundsCache.clear();
    _trackedLayers.clear();
    _trackedZOrders.clear();
    _quadtree = null;
    _quadtreeResults.clear();
    _spatialVisibleSet.clear();
    _spatialIndexBounds = null;
    _spatialIndexDirty = true;
    _layersDirty = true;
    _postProcessPasses.clear();
    _postProcessPassSet.clear();
    _sortedPasses.clear();
    _passListDirty = false;
    _batchCache.clear();
    _pendingBatches.clear();
  }

  void _refreshRenderableTracking() {
    for (final renderable in _renderables) {
      final previousLayer = _trackedLayers[renderable];
      if (previousLayer == null) {
        _trackRenderable(renderable);
        _layersDirty = true;
        _spatialIndexDirty = true;
      } else if (previousLayer != renderable.layer) {
        _layers[previousLayer]?.remove(renderable); // O(1) — LinkedHashSet
        _layers
            .putIfAbsent(renderable.layer, () => LinkedHashSet<Renderable>())
            .add(renderable); // O(1) — Set.add is idempotent
        _trackedLayers[renderable] = renderable.layer;
        _layersDirty = true;
      }

      final previousZ = _trackedZOrders[renderable];
      if (previousZ != renderable.zOrder) {
        _trackedZOrders[renderable] = renderable.zOrder;
        _layersDirty = true;
      }
    }
  }

  /// Rebuild the sorted-by-zOrder render lists from the layer sets.
  void _sortRenderables() {
    for (final entry in _layers.entries) {
      (_sortedLayerLists[entry.key] ??= [])
        ..clear()
        ..addAll(entry.value)
        ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
    }
    // Prune entries for layers that have been removed.
    _sortedLayerLists.removeWhere((k, _) => !_layers.containsKey(k));
  }

  /// Brings every renderable's bounds up to date, and the quadtree with
  /// them; true when the tree can answer this frame.
  ///
  /// While anything moves the tree is not rebuilt — that cost a rebuild
  /// every frame of any game with something moving — and the frame tests
  /// each renderable's bounds against the view instead, which is no dearer
  /// than the bounds pass itself. Once everything is still the tree is
  /// built again and reused until something moves or leaves it.
  bool _refreshSpatialIndex(Rect visibleRect) {
    var moved = false;
    var left = visibleRect.left - visibleRect.width;
    var top = visibleRect.top - visibleRect.height;
    var right = visibleRect.right + visibleRect.width;
    var bottom = visibleRect.bottom + visibleRect.height;
    for (final renderable in _renderables) {
      final bounds = renderable.getBounds();
      if (_boundsCache[renderable] != bounds) {
        _boundsCache[renderable] = bounds;
        moved = true;
      }
      if (bounds != null) {
        if (bounds.left < left) left = bounds.left;
        if (bounds.top < top) top = bounds.top;
        if (bounds.right > right) right = bounds.right;
        if (bounds.bottom > bottom) bottom = bounds.bottom;
      }
    }

    if (moved) {
      _spatialIndexDirty = true;
      _spatialReusedLastFrame = false;
      return false;
    }

    final treeCoversVisibleRect =
        _spatialIndexBounds != null &&
        _spatialIndexBounds!.contains(visibleRect.topLeft) &&
        _spatialIndexBounds!.contains(visibleRect.bottomRight);

    if (!_spatialIndexDirty && _quadtree != null && treeCoversVisibleRect) {
      _spatialReusedLastFrame = true;
      return true;
    }

    final sceneBounds = Rect.fromLTRB(left, top, right, bottom);
    _quadtree = Quadtree<Renderable>(bounds: sceneBounds);
    for (final entry in _boundsCache.entries) {
      _quadtree!.insert(entry.key, entry.value);
    }
    _spatialIndexBounds = sceneBounds;
    _spatialIndexDirty = false;
    _spatialReusedLastFrame = false;
    _spatialRebuildCount++;
    return true;
  }

  /// Draws every sprite batched so far; returns how many draw calls that
  /// was.
  int _flushPending(Canvas canvas) {
    final n = _pendingBatches.length;
    if (n == 0) return 0;
    for (final batch in _pendingBatches) {
      batch.flush(canvas);
    }
    _pendingBatches.clear();
    return n;
  }

  /// Whether the post-process pass order still holds — a pass's
  /// [PostProcessPass.passOrder] can change after it was sorted.
  bool _passesInOrder() {
    for (var i = 1; i < _sortedPasses.length; i++) {
      if (_sortedPasses[i - 1].passOrder > _sortedPasses[i].passOrder) {
        return false;
      }
    }
    return true;
  }

  /// Render a frame
  ///
  /// [canvas] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  ///
  /// The frame, in order:
  ///
  /// 1. post-process layers are opened, and the camera's pre-effects run
  ///    (motion blur), so they take in everything below;
  /// 2. clear to [backgroundColor];
  /// 3. [backgroundHooks], in screen space (parallax);
  /// 4. the [sceneRenderers], in screen space, from [view] — where a 3-D
  ///    backend draws its image;
  /// 5. the renderables, through the camera transform, layer by layer;
  /// 6. [overlayHooks] — the ECS world, then anything drawn over it (an
  ///    editor, at order 100);
  /// 7. the camera's post-effects, the post-process layers closing, and the
  ///    screen-space camera effects (fade, letterbox).
  void render(Canvas output, Size size) {
    if (!_initialized) return;
    _viewStale = true;
    for (final f in _oldScreenFrames) {
      f.dispose();
    }
    _oldScreenFrames
      ..clear()
      ..addAll(_screenFrames);
    _screenFrames.clear();

    _renderStopwatch
      ..reset()
      ..start();
    var drawCalls = 1; // background clear
    var renderedCount = 0;
    var culledCount = 0;
    var batchedSpriteCount = 0;
    // Counts reported outside a frame belong to none.
    _reportedDrawCalls = 0;
    _reportedRendered = 0;
    _reportedCulled = 0;
    _reportedBatchedSprites = 0;

    // Update camera viewport
    camera.viewportSize = size;

    _refreshRenderableTracking();
    if (_layersDirty) {
      _sortRenderables();
    }

    // ── Post-process: push offscreen layers (outermost first) ─────────────
    // Each active pass wraps the whole frame — background and parallax
    // included, which it used to leave out — in a saveLayer so Flutter's
    // compositor applies the FragmentShader when restoring the layer.
    int activePasses = 0;
    // Where shaders cannot filter layers (the web, Skia) the passes are
    // skipped rather than thrown on; see ShaderFilterSupport.
    if (_postProcessPasses.isNotEmpty &&
        _postProcessPasses.any((p) => p.enabled) &&
        ShaderFilterSupport.check('Post-process passes')) {
      _sortPasses();
      _fullscreenRect = Rect.fromLTWH(0, 0, size.width, size.height);
      // Push from outermost (highest passOrder) to innermost (lowest)
      // so the LIFO restore order applies shaders innermost-first.
      for (int i = _sortedPasses.length - 1; i >= 0; i--) {
        final pass = _sortedPasses[i];
        if (!pass.enabled) continue;
        pass.setUniforms?.call(
          pass.shader,
          size.width,
          size.height,
          elapsedSeconds,
        );
        _postProcessPaint.imageFilter = ui.ImageFilter.shader(pass.shader);
        output.saveLayer(_fullscreenRect, _postProcessPaint);
        activePasses++;
      }
    }

    // ── Screen pass: the frame drawn into an image, then painted back ─────
    // through it, before what an editor draws over the world — or, where
    // layers can be filtered, drawn into layers the passes filter.
    final passes = [
      for (final p in screenPasses)
        if (p.active) p,
    ];
    final plan = passes.isEmpty
        ? null
        : ScreenPassPlan.of(passes, size, _pixelRatio);
    plan?.begin(output, size);
    final recorder = (plan?.needsImage ?? false) ? ui.PictureRecorder() : null;
    final ratio = recorder == null ? 1.0 : _pixelRatio;
    final canvas = recorder == null ? output : (Canvas(recorder)..scale(ratio));

    // ── Camera effect pre-render (inside post-process context) ───────────
    // Called AFTER post-process layers are pushed so the motion-blur
    // saveLayer is innermost — wrapping the background, subsystem
    // renderables and ECS entities, while post-process shaders see the
    // already-blurred output.
    camera.effectManager.preRender(canvas, size);

    // Clear background
    _backgroundPaint.color = backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _backgroundPaint,
    );

    // Render parallax backgrounds in screen space (before camera transform).
    backgroundHooks(canvas, size);

    // ── Scene renderers (a 3-D backend's image), screen space ─────────────
    if (_sceneRenderers.isNotEmpty) {
      final frameView = view;
      for (final renderer in _sceneRenderers) {
        if (renderer.enabled) renderer.render(canvas, frameView);
      }
    }

    // Save canvas state
    canvas.save();

    // Apply camera transform
    camera.applyTransform(canvas, size);

    // Build spatial index when the scene is large enough to benefit.
    final visibleRect = camera.getVisibleBounds();
    final useTree = _useSpatialIndex && _renderables.length > _spatialThreshold;

    _lastUsedSpatialIndex = useTree;
    _batchCache
      ..factory = spriteBatchFactory
      ..beginFrame();

    Set<Renderable>? spatialVisible;
    var linearFromCache = false;
    if (useTree) {
      if (_refreshSpatialIndex(visibleRect)) {
        _quadtreeResults.clear();
        _quadtree?.queryRect(visibleRect, _quadtreeResults);
        _spatialVisibleSet
          ..clear()
          ..addAll(_quadtreeResults);
        spatialVisible = _spatialVisibleSet;
      } else {
        // Something moved: test the bounds just gathered, tree untouched.
        linearFromCache = true;
        _lastUsedSpatialIndex = false;
      }
    } else {
      _spatialReusedLastFrame = false;
    }

    // Render by layer (sorted, cached key list)
    if (_layersDirty) {
      _sortedLayerKeys
        ..clear()
        ..addAll(_layers.keys)
        ..sort();
      _layersDirty = false;
    }
    // Sprites batch in draw order: a batch is drawn before anything that
    // is not batched, before a sprite from another image, when the zOrder
    // changes, and at the end of the layer, so a plain renderable — or
    // another atlas's sprite — between two sprites stays between them. (Batches
    // used to be drawn only after the whole layer, over everything in it.)
    for (final layerIndex in _sortedLayerKeys) {
      final layer = _sortedLayerLists[layerIndex];
      if (layer == null) continue;
      var batchZ = 0;

      for (final renderable in layer) {
        if (!renderable.visible) {
          culledCount++;
          continue;
        }

        // Spatial culling: use quadtree result when available, else AABB
        // test. The tree holds only renderables with bounds; one without is
        // always drawn.
        if (spatialVisible != null) {
          if (!spatialVisible.contains(renderable) &&
              _boundsCache[renderable] != null) {
            culledCount++;
            continue;
          }
        } else if (!camera.isRectVisible(
          linearFromCache ? _boundsCache[renderable] : renderable.getBounds(),
        )) {
          culledCount++;
          continue;
        }

        // Attempt to batch BatchableSprite renderables
        if (renderable is BatchableSprite && _plan.plan(renderable)) {
          if (_pendingBatches.isNotEmpty && renderable.zOrder != batchZ) {
            drawCalls += _flushPending(canvas);
          }
          batchZ = renderable.zOrder;
          final batch = _batchCache.batchFor(_plan.image!, _plan.quality);
          // Only the newest batch takes more: joining an older one would
          // draw this sprite under what another image's batch queued since.
          if (_pendingBatches.isEmpty ||
              !identical(_pendingBatches.last, batch)) {
            drawCalls += _flushPending(canvas);
            _pendingBatches.add(batch);
          }
          _plan.addTo(batch);

          renderedCount++;
          batchedSpriteCount++;
          if (debugMode) _renderDebug(canvas, renderable);
          continue;
        }

        // Fallback: individual draw call, over what was batched before it.
        drawCalls += _flushPending(canvas);
        renderable.render(canvas, size);
        drawCalls++;
        renderedCount++;
        if (debugMode) _renderDebug(canvas, renderable);
      }

      // Flush what is still batched in this layer.
      drawCalls += _flushPending(canvas);
    }
    _batchCache.endFrame();

    // Restore canvas state (end of subsystem camera context)
    canvas.restore();

    // Invoke overlay callback (ECS world systems) — inside the motion-blur
    // layer so ECS entities are blurred along with subsystem renderables.
    if (plan == null) {
      overlayHooks(canvas, size);
    } else {
      overlayHooks.callRange(canvas, size, below: screenPassOrder);
    }

    // ── Camera effect post-render (pops motion-blur saveLayer) ───────────
    // Called BEFORE the post-process pop so the blurred world is what the
    // post-process shaders receive as input.
    camera.effectManager.postRender(canvas, size);

    if (recorder != null) {
      final width = (size.width * ratio).ceil().clamp(1, 16384);
      final height = (size.height * ratio).ceil().clamp(1, 16384);
      final picture = recorder.endRecording();
      final frame = picture.toImageSync(width, height);
      picture.dispose();
      _screenFrames.add(frame);
      plan!.paintImages(output, frame, size, ratio, keep: _screenFrames.add);
    }
    if (plan != null) {
      drawCalls += passes.length;
      plan.end(output);
      overlayHooks.callRange(output, size, from: screenPassOrder);
    }

    // ── Post-process: pop offscreen layers (innermost first via LIFO) ─────
    for (int i = 0; i < activePasses; i++) {
      output.restore();
    }

    // ── Camera effect screen-space overlays (fade, letterbox) ────────────
    camera.effectManager.render(output, size);

    // Render debug info
    if (debugMode) {
      _renderDebugInfo(output, size);
    }

    _renderStopwatch.stop();
    _lastRenderTimeMs = _renderStopwatch.elapsedMicroseconds / 1000.0;
    // The ECS world's drawing, reported by its RenderSystem, counts too.
    _lastDrawCallCount = drawCalls + _reportedDrawCalls;
    _lastRenderedCount = renderedCount + _reportedRendered;
    _lastCulledCount = culledCount + _reportedCulled;
    _lastBatchedSpriteCount = batchedSpriteCount + _reportedBatchedSprites;
  }

  /// Render debug information for a renderable
  void _renderDebug(Canvas canvas, Renderable renderable) {
    final bounds = renderable.getBounds();
    if (bounds != null) {
      canvas.drawRect(bounds, _debugBoundsPaint);
    }

    // Draw origin point
    canvas.drawCircle(renderable.position.toOffset(), 3, _debugOriginPaint);
  }

  /// Render debug information
  void _renderDebugInfo(Canvas canvas, Size size) {
    _debugTextPainter
      ..text = TextSpan(
        text:
            'Renderables: ${_renderables.length}\n'
            'Camera: (${camera.position.dx.toStringAsFixed(1)}, '
            '${camera.position.dy.toStringAsFixed(1)})\n'
            'Zoom: ${camera.zoom.toStringAsFixed(2)}\n'
            'Render: ${_lastRenderTimeMs.toStringAsFixed(2)} ms\n'
            'Draws: $_lastDrawCallCount | Culled: $_lastCulledCount\n'
            'Spatial Index: ${_lastUsedSpatialIndex ? 'on' : 'off'}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      )
      ..layout();
    _debugTextPainter.paint(canvas, const Offset(10, 10));
  }

  /// Clean up rendering resources
  void dispose() {
    clear();
    _initialized = false;
    if (kDebugMode) debugPrint('Rendering Engine disposed');
  }

  /// Get the number of renderables
  @Deprecated(
    'Counts only renderables added with addRenderable; query the world '
    'for RenderableComponent instead. Removed in 3.0.',
  )
  int get renderableCount => _renderables.length;

  /// Get the number of layers
  @Deprecated(
    'Counts only renderables added with addRenderable; query the world '
    'for RenderableComponent instead. Removed in 3.0.',
  )
  int get layerCount => _layers.length;

  /// Lightweight rendering diagnostics from the last frame.
  ///
  /// The counts are the whole frame's — the renderables added here and
  /// whatever reported into [addFrameStats] while the frame was drawn, the
  /// ECS world's `RenderSystem` among them (when made with this engine as
  /// its `statsSink`, as the default systems are):
  ///
  /// * `drawCalls` — canvas draws: the background clear, each thing drawn
  ///   by itself, and each batch (of sprites, or of shapes) as one;
  /// * `renderedObjects` — things drawn, a batched sprite or shape as one;
  /// * `culledObjects` — things skipped as hidden or off screen;
  /// * `batchedSprites` — sprites drawn in batches.
  ///
  /// `renderables` and `layers` count only renderables added with
  /// [addRenderable]; `lastRenderMs` times the whole of [render].
  Map<String, dynamic> get stats => {
    'renderables': _renderables.length,
    'layers': _layers.length,
    'lastRenderMs': _lastRenderTimeMs,
    'drawCalls': _lastDrawCallCount,
    'renderedObjects': _lastRenderedCount,
    'culledObjects': _lastCulledCount,
    'batchedSprites': _lastBatchedSpriteCount,
    'usedSpatialIndex': _lastUsedSpatialIndex,
    'spatialRebuilds': _spatialRebuildCount,
    'spatialReusedLastFrame': _spatialReusedLastFrame,
    'postProcessPasses': _postProcessPasses.where((p) => p.enabled).length,
  };
}
