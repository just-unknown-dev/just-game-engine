/// Game Widget
///
/// Flutter widget that integrates the game engine with Flutter's rendering pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import '../../../core/collider_debugger_system.dart';
import '../../../core/engine.dart';
import '../../../ecs/systems/rendering/render_system.dart';
import 'game_terminal.dart';

/// Main game widget that renders the game
///
/// This widget integrates the game engine with Flutter's widget tree
/// and handles the rendering pipeline.
class GameWidget extends StatefulWidget {
  /// The game engine instance
  final Engine engine;

  /// Whether to show FPS counter
  final bool showFPS;

  /// Whether to show the main ECS debugger overlay.
  final bool showDebug;

  /// Whether to show the in-game developer terminal.
  ///
  /// When `true`, pressing the backquote/tilde key (`` ` ``) toggles a text
  /// command console over the game canvas.  While the terminal is open all
  /// keyboard input is routed to it and not forwarded to the game.
  ///
  /// Register commands via [Engine.terminal] before calling [GameWidget].
  final bool showTerminal;

  /// Create a game widget
  const GameWidget({
    super.key,
    required this.engine,
    this.showFPS = true,
    this.showDebug = false,
    this.showTerminal = false,
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
  ColliderDebuggerSystem? _colliderDebugger;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Create ticker for rendering — only signals the painter, no setState.
    _ticker = createTicker(_onTick);
    _ticker.start();

    // Enable debug mode if requested
    widget.engine.rendering.debugMode = widget.showDebug;

    if (widget.showDebug) {
      _colliderDebugger = ColliderDebuggerSystem(
        camera: widget.engine.cameraSystem.mainCamera,
      );
      widget.engine.world.addSystem(_colliderDebugger!);
    }

    // Subscribe to terminal state changes so the overlay rebuilds
    // when the user types or toggles visibility.
    if (widget.showTerminal) {
      widget.engine.terminal.addListener(_onTerminalChange);
    }

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

  void _onTerminalChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.engine.terminal.removeListener(_onTerminalChange);
    if (_colliderDebugger != null) {
      widget.engine.world.removeSystem(_colliderDebugger!);
      _colliderDebugger = null;
    }
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
    // Push the sub-frame interpolation factor to the ECS RenderSystem so
    // physics-driven entities lerp smoothly between fixed-timestep positions.
    widget.engine.world.getSystem<RenderSystem>()?.interpolation =
        widget.engine.gameLoop.interpolation;
    // Signal the CustomPainter to repaint — no widget rebuild needed.
    _repaintNotifier.notify();
    _updateFPS();
  }

  void _updateFPS() {
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _fpsNotifier.value = widget.engine.gameLoop.currentFPS;
      _lastFpsUpdate = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = GestureDetector(
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
          if (widget.showTerminal) {
            final terminal = widget.engine.terminal;

            // Backquote (`) / tilde (~) toggles the terminal — key-down only
            // to avoid double-fire from repeat events.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.backquote) {
              terminal.toggle();
              return KeyEventResult.handled;
            }

            // When the terminal is visible, all key events are consumed by it.
            if (terminal.isVisible) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                // Try special-key handling first (Enter → submit, Backspace →
                // delete).  Only if the key is not a recognised special key do
                // we fall through to character appending so that Shift/CapsLock
                // are resolved correctly by Flutter's key system.
                final handled = terminal.handleKeyDown(event.logicalKey);
                if (!handled) {
                  final char = event.character;
                  if (char != null) {
                    terminal.appendCharacter(char);
                  }
                }
              }
              return KeyEventResult.handled;
            }
          }
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

                // In-game developer terminal overlay.
                if (widget.showTerminal && widget.engine.terminal.isVisible)
                  Positioned.fill(
                    child: _TerminalOverlay(terminal: widget.engine.terminal),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return content;
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
    // Clip to the widget's own pixel bounds so that world-space geometry
    // (e.g. large background rectangles) cannot bleed onto sibling Flutter
    // widgets (headers, panels, overlays) that share the screen canvas.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // Single render call — ECS systems are invoked via onRenderOverlay
    // inside the camera-transformed context.
    engine.rendering.render(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) {
    // Repaints are driven by the repaint Listenable, not by widget rebuilds.
    return false;
  }
}

// ── Terminal overlay ──────────────────────────────────────────────────────────

/// Renders the in-game developer terminal as a Flutter widget overlay.
///
/// Placed inside the [GameWidget] Stack so it sits above the game canvas
/// and below any Flutter HUD widgets that the host app stacks on top of
/// [GameWidget].
class _TerminalOverlay extends StatelessWidget {
  const _TerminalOverlay({required this.terminal});

  final GameTerminal terminal;

  static const _bg = Color(0xCC000000); // 80 % black
  static const _borderColor = Color(0xFF00FF88); // green tint
  static const _textColor = Color(0xFFCCFFCC);
  static const _promptColor = Color(0xFF00FF88);
  static const _hintColor = Color(0xFF888888);
  static const _textStyle = TextStyle(
    color: _textColor,
    fontSize: 12,
    fontFamily: 'monospace',
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final history = terminal.history;
    final input = terminal.inputBuffer;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: _bg,
          border: const Border(top: BorderSide(color: _borderColor, width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hint bar ───────────────────────────────────────────
            Container(
              color: const Color(0xFF111111),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: const Text(
                "DEV TERMINAL  |  Press ` to close  |  'help' lists commands",
                style: TextStyle(
                  color: _hintColor,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // ── Scrollback history ─────────────────────────────────
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                shrinkWrap: true,
                reverse: true,
                itemCount: history.length,
                itemBuilder: (_, i) {
                  // Display in reverse so newest line is at the bottom.
                  final line = history[history.length - 1 - i];
                  return Text(line, style: _textStyle);
                },
              ),
            ),
            // ── Input prompt ───────────────────────────────────────
            Container(
              color: const Color(0xFF0A0A0A),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Text(
                    '> ',
                    style: TextStyle(
                      color: _promptColor,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '$input█', // block cursor
                      style: _textStyle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
