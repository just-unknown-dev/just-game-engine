/// Game Widget
///
/// Flutter widget that integrates the game engine with Flutter's rendering pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/engine.dart';

/// Main game widget that renders the game
///
/// This widget integrates the game engine with Flutter's widget tree
/// and handles the rendering pipeline.
class GameWidget extends StatefulWidget {
  /// The game engine instance
  final Engine engine;

  /// Whether to show FPS counter
  final bool showFPS;

  /// Whether to show debug info
  final bool showDebug;

  /// Create a game widget
  const GameWidget({
    super.key,
    required this.engine,
    this.showFPS = true,
    this.showDebug = false,
  });

  @override
  State<GameWidget> createState() => _GameWidgetState();
}

class _GameWidgetState extends State<GameWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  int _frameCount = 0;
  int _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Create ticker for rendering
    _ticker = createTicker(_onTick);
    _ticker.start();

    // Enable debug mode if requested
    widget.engine.rendering.debugMode = widget.showDebug;

    // Request focus for keyboard input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    // Add focus listener to clear input when focus is lost
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.engine.input.keyboard.clear();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // This will trigger a rebuild, which will render the frame
    if (mounted) {
      setState(() {
        _updateFPS();
      });
    }
  }

  void _updateFPS() {
    _frameCount++;
    final now = DateTime.now();
    final diff = now.difference(_lastFpsUpdate);

    if (diff.inMilliseconds >= 1000) {
      _fps = (_frameCount * 1000 / diff.inMilliseconds).round();
      _frameCount = 0;
      _lastFpsUpdate = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Request focus when tapping on the game area
        _focusNode.requestFocus();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        canRequestFocus: true,
        skipTraversal: false,
        onKeyEvent: (node, event) {
          // Handle key events
          debugPrint(
            'onKeyEvent called: ${event.runtimeType} - ${event.logicalKey.keyLabel}',
          );
          widget.engine.input.handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            // Request focus on pointer down as well
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
            widget.engine.input.handlePointerEvent(event);
          },
          onPointerUp: (event) => widget.engine.input.handlePointerEvent(event),
          onPointerMove: (event) =>
              widget.engine.input.handlePointerEvent(event),
          onPointerHover: (event) =>
              widget.engine.input.handlePointerEvent(event),
          onPointerSignal: (event) =>
              widget.engine.input.handlePointerEvent(event),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Stack(
              children: [
                // Main game canvas - fill entire available space
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GamePainter(widget.engine),
                    size: Size.infinite,
                  ),
                ),

                // FPS counter
                if (widget.showFPS)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FPS: $_fps',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),

                // Debug info
                if (widget.showDebug)
                  Positioned(
                    top: 50,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Renderables: ${widget.engine.rendering.renderableCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'Layers: ${widget.engine.rendering.layerCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'Camera: (${widget.engine.rendering.camera.position.dx.toStringAsFixed(0)}, '
                            '${widget.engine.rendering.camera.position.dy.toStringAsFixed(0)})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'Zoom: ${widget.engine.rendering.camera.zoom.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that renders the game
class _GamePainter extends CustomPainter {
  final Engine engine;

  _GamePainter(this.engine);

  @override
  void paint(Canvas canvas, Size size) {
    // Render through the engine
    engine.rendering.render(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // Always repaint for game rendering
    return true;
  }
}
