/// Rendering Engine (Graphics)
///
/// The frame: background, scene renderers, the world (through the overlay
/// hooks), post-process and screen passes, camera effects.
library;

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'render_hook_chain.dart';
import 'render_stats_sink.dart';
import '../interfaces/frame_view.dart';
import 'scene_renderer.dart';
import 'shader_filter_support.dart';
import 'screen_pass.dart';
import 'post_processing/post_process_pass.dart';
import '../camera/output_camera.dart';

/// Main rendering engine class responsible for graphics rendering
///
/// This class runs the frame — what the camera sees, through the post-process
/// and screen passes — using Flutter's Canvas API. What the world holds is
/// drawn by its `RenderSystem`, which [GameWidget] runs from [overlayHooks].
///
/// It is also a [RenderStatsSink]: the ECS world's `RenderSystem` reports
/// what it draws here, so [stats] count the whole frame.
class RenderingEngine implements RenderStatsSink {
  /// Main camera
  late OutputCamera camera;

  /// Background color
  Color backgroundColor = const Color(0xFF1a1a2e);

  /// Whether the engine is initialized
  bool _initialized = false;

  /// Called in screen space after the background clear but before the
  /// scene renderers. `ParallaxRenderSystem` paints its backgrounds here.
  final RenderHookChain backgroundHooks = RenderHookChain();

  /// Called in screen space after the scene renderers: the ECS world —
  /// [GameWidget] adds `engine.world.render`, whose `RenderSystem` applies
  /// the camera itself — then anything drawn over it (an editor, at order
  /// [screenPassOrder]).
  ///
  /// A chain, not a single field: several things — the world, an editor, a
  /// debug overlay — draw here, and with a single field the first writer won
  /// and the rest were silently dropped.
  final RenderHookChain overlayHooks = RenderHookChain();

  /// Debug mode flag: draws the frame's numbers in the top-left corner.
  bool debugMode = false;

  /// The least time between two frames a [GameWidget] of the engine draws;
  /// null (the default) draws every frame. The game goes on running every
  /// frame — only drawing is spared, and in between the view shows the
  /// frame it drew last: for a view hidden behind something, a full-screen
  /// menu or an editor's window, which drawing every frame would only slow.
  Duration? drawInterval;

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

  int _frames = 0;
  bool _drawing = false;

  /// The frame [render] is drawing (counted from 1) while it draws; null
  /// between frames. Every view drawn within one frame sees the world as
  /// it is then — an editor's panes, its preview of the game's camera — so
  /// a scene renderer can look the world over once for all of them.
  int? get drawingFrame => _drawing ? _frames : null;

  /// The camera of the frame being drawn, as matrices — filled at most once
  /// a frame, and only when read, so a 2-D game pays nothing for it.
  FrameView get view {
    if (_viewStale) {
      _view.update(camera, camera.viewportSize, interpolation: interpolation);
      _viewStale = false;
    }
    return _view;
  }

  double _lastRenderTimeMs = 0.0;
  int _lastDrawCallCount = 0;
  int _lastRenderedCount = 0;
  int _lastCulledCount = 0;
  int _lastBatchedSpriteCount = 0;

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

  /// Overlay hooks below this order are drawn under the [screenPasses], and
  /// those at it or above (an editor's) over them.
  static const int screenPassOrder = 100;

  /// How many device pixels a logical pixel is, for the image the
  /// [screenPasses] are drawn from; the view's own when null.
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

  /// Lays out the debug overlay ([debugMode]); made when first drawn, let
  /// go by [dispose].
  TextPainter? _debugTextPainter;

  /// Get initialization status
  bool get isInitialized => _initialized;

  /// Initialize the rendering engine
  void initialize() {
    if (_initialized) return;

    _initialized = true;
    if (kDebugMode) debugPrint('Rendering Engine initialized');
  }

  /// Drops every post-process pass.
  void clear() {
    _postProcessPasses.clear();
    _postProcessPassSet.clear();
    _sortedPasses.clear();
    _passListDirty = false;
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
  /// [output] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  ///
  /// The frame, in order:
  ///
  /// 1. post-process layers are opened, and — when [screenPasses] are
  ///    active — the frame is drawn into their layers or an image of it;
  /// 2. the camera's pre-effects run (motion blur), so they take in
  ///    everything below;
  /// 3. clear to [backgroundColor];
  /// 4. [backgroundHooks], in screen space (parallax);
  /// 5. the [sceneRenderers], in screen space, from [view] — where a 3-D
  ///    backend draws its image;
  /// 6. [overlayHooks] below [screenPassOrder] — the ECS world;
  /// 7. the camera's post-effects; the screen passes are drawn, then the
  ///    overlay hooks from [screenPassOrder] on (an editor's);
  /// 8. the post-process layers close, and the screen-space camera effects
  ///    (fade, letterbox) are drawn.
  ///
  /// While it runs, [drawingFrame] is the frame's number.
  void render(Canvas output, Size size) {
    if (!_initialized) return;
    _frames++;
    _drawing = true;
    try {
      _renderFrame(output, size);
    } finally {
      _drawing = false;
    }
  }

  void _renderFrame(Canvas output, Size size) {
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
    // Counts reported outside a frame belong to none.
    _reportedDrawCalls = 0;
    _reportedRendered = 0;
    _reportedCulled = 0;
    _reportedBatchedSprites = 0;

    // Update camera viewport
    camera.viewportSize = size;

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
    // saveLayer is innermost — wrapping the background and the ECS world,
    // while post-process shaders see the already-blurred output.
    camera.effectManager.preRender(canvas, size);

    // Clear background
    _backgroundPaint.color = backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _backgroundPaint,
    );

    // Render parallax backgrounds in screen space.
    backgroundHooks(canvas, size);

    // ── Scene renderers (a 3-D backend's image), screen space ─────────────
    if (_sceneRenderers.isNotEmpty) {
      final frameView = view;
      for (final renderer in _sceneRenderers) {
        if (renderer.enabled) renderer.render(canvas, frameView);
      }
    }

    // Invoke overlay callback (ECS world systems) — inside the motion-blur
    // layer so ECS entities are blurred.
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
    _lastRenderedCount = _reportedRendered;
    _lastCulledCount = _reportedCulled;
    _lastBatchedSpriteCount = _reportedBatchedSprites;
  }

  /// Render debug information
  void _renderDebugInfo(Canvas canvas, Size size) {
    final painter = _debugTextPainter ??= TextPainter(
      textDirection: TextDirection.ltr,
    );
    painter
      ..text = TextSpan(
        text:
            'Camera: (${camera.position.dx.toStringAsFixed(1)}, '
            '${camera.position.dy.toStringAsFixed(1)})\n'
            'Zoom: ${camera.zoom.toStringAsFixed(2)}\n'
            'Render: ${_lastRenderTimeMs.toStringAsFixed(2)} ms\n'
            'Draws: $_lastDrawCallCount | Culled: $_lastCulledCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      )
      ..layout();
    painter.paint(canvas, const Offset(10, 10));
  }

  /// Clean up rendering resources: the post-process passes, the frame
  /// images the screen passes drew from, and the debug overlay's text.
  void dispose() {
    clear();
    // A recorded picture keeps what it drew with; these handles are the
    // engine's own.
    for (final f in [..._oldScreenFrames, ..._screenFrames]) {
      f.dispose();
    }
    _oldScreenFrames.clear();
    _screenFrames.clear();
    _debugTextPainter?.dispose();
    _debugTextPainter = null;
    _initialized = false;
    if (kDebugMode) debugPrint('Rendering Engine disposed');
  }

  /// Lightweight rendering diagnostics from the last frame.
  ///
  /// The counts are the whole frame's — the background clear, the screen
  /// passes, and whatever reported into [addFrameStats] while the frame was
  /// drawn, the ECS world's `RenderSystem` among them (when made with this
  /// engine as its `statsSink`, as the default systems are):
  ///
  /// * `drawCalls` — canvas draws: the background clear, each thing drawn
  ///   by itself, and each batch (of sprites, or of shapes) as one;
  /// * `renderedObjects` — things drawn, a batched sprite or shape as one;
  /// * `culledObjects` — things skipped as hidden or off screen;
  /// * `batchedSprites` — sprites drawn in batches.
  ///
  /// `lastRenderMs` times the whole of [render]; `postProcessPasses` counts
  /// the enabled post-process passes.
  Map<String, dynamic> get stats => {
    'lastRenderMs': _lastRenderTimeMs,
    'drawCalls': _lastDrawCallCount,
    'renderedObjects': _lastRenderedCount,
    'culledObjects': _lastCulledCount,
    'batchedSprites': _lastBatchedSpriteCount,
    'postProcessPasses': _postProcessPasses.where((p) => p.enabled).length,
  };
}
