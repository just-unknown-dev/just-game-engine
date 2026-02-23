/// Rendering Engine (Graphics)
///
/// Handles visual representation, 2D sprites, shapes, text rendering, and effects.
/// This module manages the rendering pipeline for the game engine using Flutter Canvas.
library;

import 'package:flutter/material.dart';
import 'renderable.dart';
import 'camera.dart';

export 'renderable.dart';
export 'camera.dart';
export 'game_widget.dart';

/// Main rendering engine class responsible for graphics rendering
///
/// This class manages the rendering pipeline, camera, and all renderable objects.
/// It uses Flutter's Canvas API for 2D rendering.
class RenderingEngine {
  /// List of all renderable objects
  final List<Renderable> _renderables = [];

  /// List of rendering layers
  final Map<int, List<Renderable>> _layers = {};

  /// Main camera
  late Camera camera;

  /// Background color
  Color backgroundColor = const Color(0xFF1a1a2e);

  /// Whether the engine is initialized
  bool _initialized = false;

  /// Debug mode flag
  bool debugMode = false;

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

    // Initialize default camera
    camera = Camera(position: const Offset(0, 0), zoom: 1.0);

    _initialized = true;
    debugPrint('Rendering Engine initialized');
  }

  /// Add a renderable object to the scene
  ///
  /// [renderable] - The object to render
  void addRenderable(Renderable renderable) {
    if (!_renderables.contains(renderable)) {
      _renderables.add(renderable);
      _addToLayer(renderable);
    }
  }

  /// Remove a renderable object from the scene
  ///
  /// [renderable] - The object to remove
  void removeRenderable(Renderable renderable) {
    _renderables.remove(renderable);
    _removeFromLayer(renderable);
  }

  /// Add a renderable to its layer
  void _addToLayer(Renderable renderable) {
    _layers.putIfAbsent(renderable.layer, () => []);
    if (!_layers[renderable.layer]!.contains(renderable)) {
      _layers[renderable.layer]!.add(renderable);
    }
  }

  /// Remove a renderable from its layer
  void _removeFromLayer(Renderable renderable) {
    _layers[renderable.layer]?.remove(renderable);
  }

  /// Clear all renderables
  void clear() {
    _renderables.clear();
    _layers.clear();
  }

  /// Sort renderables by layer and z-order
  void _sortRenderables() {
    for (final layer in _layers.values) {
      layer.sort((a, b) => a.zOrder.compareTo(b.zOrder));
    }
  }

  /// Render a frame
  ///
  /// [canvas] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  void render(Canvas canvas, Size size) {
    if (!_initialized) return;

    // Update camera viewport
    camera.viewportSize = size;

    // Clear background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // Sort renderables
    _sortRenderables();

    // Save canvas state
    canvas.save();

    // Apply camera transform
    camera.applyTransform(canvas, size);

    // Render by layer (sorted)
    final sortedLayers = _layers.keys.toList()..sort();
    for (final layerIndex in sortedLayers) {
      final layer = _layers[layerIndex]!;
      for (final renderable in layer) {
        if (renderable.visible) {
          renderable.render(canvas, size);

          // Debug rendering
          if (debugMode) {
            _renderDebug(canvas, renderable);
          }
        }
      }
    }

    // Restore canvas state
    canvas.restore();

    // Render debug info
    if (debugMode) {
      _renderDebugInfo(canvas, size);
    }
  }

  /// Render debug information for a renderable
  void _renderDebug(Canvas canvas, Renderable renderable) {
    final bounds = renderable.getBounds();
    if (bounds != null) {
      final paint = Paint()
        ..color = Colors.green.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(bounds, paint);
    }

    // Draw origin point
    canvas.drawCircle(renderable.position, 3, Paint()..color = Colors.red);
  }

  /// Render debug information
  void _renderDebugInfo(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            'Renderables: ${_renderables.length}\n'
            'Camera: (${camera.position.dx.toStringAsFixed(1)}, '
            '${camera.position.dy.toStringAsFixed(1)})\n'
            'Zoom: ${camera.zoom.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 10));
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
}
