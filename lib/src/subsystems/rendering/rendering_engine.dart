/// Rendering Engine (Graphics)
///
/// Handles visual representation, 2D sprites, shapes, text rendering, and effects.
/// This module manages the rendering pipeline for the game engine using Flutter Canvas.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'impl/renderable.dart';
import 'impl/sprite_batch.dart';
import '../camera/camera_system.dart';
import '../../interfaces/rendering_interfaces.dart';
import '../../math/quadtree.dart';

export 'impl/renderable.dart';
export 'impl/game_widget.dart';
export 'impl/sprite_batch.dart';

/// Main rendering engine class responsible for graphics rendering
///
/// This class manages the rendering pipeline, camera, and all renderable objects.
/// It uses Flutter's Canvas API for 2D rendering.
class RenderingEngine {
  /// List of all renderable objects
  final List<Renderable> _renderables = [];

  /// Set for O(1) membership checks in addRenderable
  final Set<Renderable> _renderableSet = {};

  /// List of rendering layers
  final Map<int, List<Renderable>> _layers = {};

  /// Main camera
  late Camera camera;

  /// Background color
  Color backgroundColor = const Color(0xFF1a1a2e);

  /// Whether the engine is initialized
  bool _initialized = false;

  /// Optional callback invoked in screen space after the background clear but
  /// before the camera transform. Used by [ParallaxSystem] to paint parallax
  /// backgrounds that scroll at their own rates.
  void Function(Canvas canvas, Size size)? onRenderBackground;

  /// Optional callback invoked inside the camera-transformed context after all
  /// subsystem layers have been rendered. Use this to inject ECS world
  /// rendering so both pipelines share a single camera transform.
  ///
  /// Set by [GameWidget] to `engine.world.render`.
  void Function(Canvas canvas, Size size)? onRenderOverlay;

  /// Debug mode flag
  bool debugMode = false;

  /// Optional factory for creating [SpriteBatchRenderer] instances.
  /// Defaults to the built-in [SpriteBatch] implementation.
  SpriteBatchFactory spriteBatchFactory = (ui.Image atlas) =>
      SpriteBatch(atlas);

  /// Cached sprite-batch renderers keyed by atlas identity hash.
  final Map<int, SpriteBatchRenderer> _batchCache = {};

  /// Spatial index for fast viewport culling.
  ///
  /// When [useSpatialIndex] is `true` and there are more than
  /// [_spatialThreshold] renderables, the quadtree is rebuilt each frame and
  /// used to query only those renderables overlapping the camera viewport.
  /// For smaller scenes the O(n) scan is faster due to lower overhead.
  bool useSpatialIndex = true;
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
  int _spatialRebuildCount = 0;
  bool _spatialReusedLastFrame = false;

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
    debugPrint('Rendering Engine initialized');
  }

  /// Add a renderable object to the scene
  ///
  /// [renderable] - The object to render
  void addRenderable(Renderable renderable) {
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
  void removeRenderable(Renderable renderable) {
    if (_renderableSet.remove(renderable)) {
      _renderables.remove(renderable);
      _untrackRenderable(renderable);
      _removeFromLayer(renderable);
      _spatialIndexDirty = true;
    }
  }

  /// Add a renderable to its layer
  void _addToLayer(Renderable renderable) {
    _layers.putIfAbsent(renderable.layer, () => []);
    _layers[renderable.layer]!.add(renderable);
    _layersDirty = true;
  }

  /// Remove a renderable from its layer
  void _removeFromLayer(Renderable renderable) {
    _layers[renderable.layer]?.remove(renderable);
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
  void markLayerOrderDirty() {
    _layersDirty = true;
  }

  /// Mark the spatial index as dirty after direct transform mutation.
  void markSpatialIndexDirty() {
    _spatialIndexDirty = true;
  }

  /// Clear all renderables
  void clear() {
    _renderables.clear();
    _renderableSet.clear();
    _layers.clear();
    _boundsCache.clear();
    _trackedLayers.clear();
    _trackedZOrders.clear();
    _quadtree = null;
    _quadtreeResults.clear();
    _spatialVisibleSet.clear();
    _spatialIndexBounds = null;
    _spatialIndexDirty = true;
    _layersDirty = true;
  }

  void _refreshRenderableTracking() {
    for (final renderable in _renderables) {
      final previousLayer = _trackedLayers[renderable];
      if (previousLayer == null) {
        _trackRenderable(renderable);
        _layersDirty = true;
        _spatialIndexDirty = true;
      } else if (previousLayer != renderable.layer) {
        _layers[previousLayer]?.remove(renderable);
        final nextLayer = _layers.putIfAbsent(renderable.layer, () => []);
        if (!nextLayer.contains(renderable)) {
          nextLayer.add(renderable);
        }
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

  /// Sort renderables by layer and z-order
  void _sortRenderables() {
    for (final layer in _layers.values) {
      layer.sort((a, b) => a.zOrder.compareTo(b.zOrder));
    }
  }

  void _refreshSpatialIndex(Rect visibleRect) {
    var sceneBounds = Rect.fromLTRB(
      visibleRect.left - visibleRect.width,
      visibleRect.top - visibleRect.height,
      visibleRect.right + visibleRect.width,
      visibleRect.bottom + visibleRect.height,
    );
    var boundsChanged = _spatialIndexDirty || _quadtree == null;

    for (final renderable in _renderables) {
      final currentBounds = renderable.getBounds();
      if (_boundsCache[renderable] != currentBounds) {
        _boundsCache[renderable] = currentBounds;
        boundsChanged = true;
      }
      if (currentBounds != null) {
        sceneBounds = sceneBounds.expandToInclude(currentBounds);
      }
    }

    final treeCoversVisibleRect =
        _spatialIndexBounds != null &&
        _spatialIndexBounds!.contains(visibleRect.topLeft) &&
        _spatialIndexBounds!.contains(visibleRect.bottomRight);

    final needsRebuild = boundsChanged || !treeCoversVisibleRect;
    if (!needsRebuild) {
      _spatialReusedLastFrame = true;
      return;
    }

    _quadtree = Quadtree<Renderable>(bounds: sceneBounds);
    for (final entry in _boundsCache.entries) {
      _quadtree!.insert(entry.key, entry.value);
    }
    _spatialIndexBounds = sceneBounds;
    _spatialIndexDirty = false;
    _spatialReusedLastFrame = false;
    _spatialRebuildCount++;
  }

  /// Render a frame
  ///
  /// [canvas] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  void render(Canvas canvas, Size size) {
    if (!_initialized) return;

    final frameStopwatch = Stopwatch()..start();
    var drawCalls = 1; // background clear
    var renderedCount = 0;
    var culledCount = 0;
    var batchedSpriteCount = 0;

    // Update camera viewport
    camera.viewportSize = size;

    // Clear background
    _backgroundPaint.color = backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _backgroundPaint,
    );

    _refreshRenderableTracking();
    if (_layersDirty) {
      _sortRenderables();
    }

    // Render parallax backgrounds in screen space (before camera transform).
    onRenderBackground?.call(canvas, size);

    // Save canvas state
    canvas.save();

    // Apply camera transform
    camera.applyTransform(canvas, size);

    // Build spatial index when the scene is large enough to benefit.
    final visibleRect = camera.getVisibleBounds();
    final useTree = useSpatialIndex && _renderables.length > _spatialThreshold;

    _lastUsedSpatialIndex = useTree;

    Set<Renderable>? spatialVisible;
    if (useTree) {
      _refreshSpatialIndex(visibleRect);
      _quadtreeResults.clear();
      _quadtree?.queryRect(visibleRect, _quadtreeResults);
      _spatialVisibleSet
        ..clear()
        ..addAll(_quadtreeResults);
      spatialVisible = _spatialVisibleSet;
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
    // Track which batches were used per layer for flushing
    final activeBatches = <SpriteBatchRenderer>[];
    final activeBatchSet = <SpriteBatchRenderer>{};

    for (final layerIndex in _sortedLayerKeys) {
      final layer = _layers[layerIndex];
      if (layer == null) continue;
      activeBatches.clear();
      activeBatchSet.clear();

      for (final renderable in layer) {
        if (!renderable.visible) {
          culledCount++;
          continue;
        }

        // Spatial culling: use quadtree result when available, else AABB test.
        if (spatialVisible != null) {
          if (!spatialVisible.contains(renderable)) {
            culledCount++;
            continue;
          }
        } else if (!camera.isRectVisible(renderable.getBounds())) {
          culledCount++;
          continue;
        }

        // Attempt to batch BatchableSprite renderables
        if (renderable is BatchableSprite) {
          final batchable = renderable as BatchableSprite;
          final atlas = batchable.batchImage;
          if (atlas != null) {
            final key = identityHashCode(atlas);
            final batch = _batchCache[key] ??= spriteBatchFactory(atlas);
            if (activeBatchSet.add(batch)) {
              activeBatches.add(batch);
            }

            final src =
                batchable.batchSourceRect ??
                Rect.fromLTWH(
                  0,
                  0,
                  atlas.width.toDouble(),
                  atlas.height.toDouble(),
                );
            batch.add(
              sourceRect: src,
              position: renderable.position,
              rotation: renderable.rotation,
              scale: renderable.scale,
              color: (renderable.tint ?? Colors.white).withValues(
                alpha: renderable.opacity,
              ),
            );

            renderedCount++;
            batchedSpriteCount++;
            if (debugMode) _renderDebug(canvas, renderable);
            continue;
          }
        }

        // Fallback: individual draw call
        renderable.render(canvas, size);
        drawCalls++;
        renderedCount++;
        if (debugMode) _renderDebug(canvas, renderable);
      }

      // Flush all batches used in this layer
      for (final batch in activeBatches) {
        batch.flush(canvas);
      }
      drawCalls += activeBatches.length;
    }

    // Restore canvas state (end of subsystem camera context)
    canvas.restore();

    // Invoke overlay callback (ECS world systems) after restoring the canvas
    // so each pipeline applies its own camera transform independently.
    onRenderOverlay?.call(canvas, size);

    // Render debug info
    if (debugMode) {
      _renderDebugInfo(canvas, size);
    }

    frameStopwatch.stop();
    _lastRenderTimeMs = frameStopwatch.elapsedMicroseconds / 1000.0;
    _lastDrawCallCount = drawCalls;
    _lastRenderedCount = renderedCount;
    _lastCulledCount = culledCount;
    _lastBatchedSpriteCount = batchedSpriteCount;
  }

  /// Render debug information for a renderable
  void _renderDebug(Canvas canvas, Renderable renderable) {
    final bounds = renderable.getBounds();
    if (bounds != null) {
      canvas.drawRect(bounds, _debugBoundsPaint);
    }

    // Draw origin point
    canvas.drawCircle(renderable.position, 3, _debugOriginPaint);
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
    debugPrint('Rendering Engine disposed');
  }

  /// Get the number of renderables
  int get renderableCount => _renderables.length;

  /// Get the number of layers
  int get layerCount => _layers.length;

  /// Lightweight rendering diagnostics from the last frame.
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
  };
}
