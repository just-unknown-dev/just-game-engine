/// Game Widget
///
/// Flutter widget that integrates the game engine with Flutter's rendering pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/engine.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Ticker _ticker;

  /// Notifier used to trigger CustomPainter repaints without calling setState.
  final _repaintNotifier = _FrameNotifier();

  /// Notifier for the HUD overlay (FPS / debug), updated at ~1 Hz cadence.
  /// Reads from [GameLoop.currentFPS] so there is a single source of truth.
  final ValueNotifier<int> _fpsNotifier = ValueNotifier<int>(0);
  DateTime _lastFpsUpdate = DateTime.now();

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Create ticker for rendering — only signals the painter, no setState.
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
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focusNode.dispose();
    _repaintNotifier.dispose();
    _fpsNotifier.dispose();
    super.dispose();
  }

  // ── App lifecycle: pause/resume the GameLoop timer when backgrounded ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (widget.engine.isRunning) {
          widget.engine.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (widget.engine.isPaused) {
          widget.engine.resume();
        }
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    // Drive the game loop from the vsync Ticker — single unified loop.
    widget.engine.gameLoop.tick();
    // Signal the CustomPainter to repaint — no widget rebuild needed.
    _repaintNotifier.notify();
    _updateFPS();
  }

  void _updateFPS() {
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _fpsNotifier.value = Engine.instance.gameLoop.currentFPS;
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
                // Main game canvas — repainted via _repaintNotifier, no
                // setState rebuild needed.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GamePainter(
                        widget.engine,
                        repaint: _repaintNotifier,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),

                // FPS counter — isolated in its own RepaintBoundary and
                // driven by a ValueNotifier so it only rebuilds ~1 Hz.
                if (widget.showFPS)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _fpsNotifier,
                        builder: (_, fps, _) => Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'FPS: $fps',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Debug info — isolated RepaintBoundary, driven by same
                // FPS notifier cadence.
                if (widget.showDebug)
                  Positioned(
                    top: 50,
                    right: 10,
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _fpsNotifier,
                        builder: (_, _, _) {
                          final engineStats = widget.engine.performanceStats;
                          final renderStats = widget.engine.rendering.stats;
                          final physicsStats = widget.engine.physics.stats;

                          return Container(
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
                                Text(
                                  'Update: ${((engineStats['lastUpdateMs'] as num?) ?? 0).toStringAsFixed(2)} ms',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  'Render: ${((renderStats['lastRenderMs'] as num?) ?? 0).toStringAsFixed(2)} ms | Draws: ${renderStats['drawCalls']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  'Physics: ${((physicsStats['lastStepMs'] as num?) ?? 0).toStringAsFixed(2)} ms | Awake: ${physicsStats['awakeBodies']} | Pairs: ${physicsStats['potentialPairs']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

/// Lightweight [ChangeNotifier] used solely to signal repaints.
class _FrameNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Custom painter that renders the game.
///
/// Accepts a [Listenable] via the `repaint` parameter so
/// Flutter's rendering pipeline triggers `paint()` without
/// the widget tree needing to rebuild.
class _GamePainter extends CustomPainter {
  final Engine engine;

  _GamePainter(this.engine, {super.repaint}) {
    // Wire ECS world rendering into the subsystem pipeline so both share
    // the same camera transform (unified render pipeline).
    engine.rendering.onRenderOverlay ??= engine.world.render;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Single render call — ECS systems are invoked via onRenderOverlay
    // inside the camera-transformed context.
    engine.rendering.render(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) {
    // Repaints are driven by the repaint Listenable, not by widget rebuilds.
    return false;
  }
}
