/// Game Widget
///
/// Flutter widget that integrates the game engine with Flutter's rendering pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:just_signals/just_signals.dart';
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

  /// Logical keys that [GameWidget] should treat as "not mine" for the
  /// purposes of Flutter key propagation.
  ///
  /// [GameWidget] still unconditionally forwards every key event to
  /// [Engine.input] (so polling-based ECS systems, e.g.
  /// `keyboard.isKeyDown`, keep seeing the key) — forwarding for gameplay
  /// and the value returned to Flutter's key system are independent
  /// concerns. For any key in this set, the internal `Focus.onKeyEvent`
  /// returns [KeyEventResult.ignored] instead of [KeyEventResult.handled],
  /// which is the correct signal per Flutter's `Focus` API for "an
  /// ancestor may want this."
  ///
  /// In practice, whether an ancestor `Shortcuts`/`CallbackShortcuts`
  /// widget actually *receives* that bubbled event depends on the
  /// `FocusScope` structure above [GameWidget] — in testing, a
  /// `MaterialApp` → `Navigator` → route → `Scaffold` chain (i.e. the
  /// typical top-level app shape) did not reliably deliver an ignored key
  /// event to an ancestor outside that chain. For a binding that must
  /// fire reliably regardless of the surrounding widget tree (e.g. an
  /// app-level Escape-to-pause shortcut), register a
  /// `HardwareKeyboard.instance.addHandler` callback instead — it runs
  /// independently of the `Focus` tree entirely. This parameter is still
  /// useful for composing with narrower/simpler `Focus` ancestors, and for
  /// correctly not swallowing keys the app has claimed elsewhere.
  ///
  /// While [showTerminal] is `true` and the developer terminal is visible,
  /// terminal capture always takes priority over passthrough, matching the
  /// existing terminal-open key semantics.
  ///
  /// Defaults to `null` (treated as empty) — every key is `handled` as
  /// before, so this is fully backward compatible.
  final Set<LogicalKeyboardKey>? passthroughKeys;

  /// Optional app-level content composed on top of the game canvas.
  ///
  /// Stacked above the canvas and below the FPS counter / developer
  /// terminal, so the engine's own dev tools always stay visible and
  /// interactive regardless of what the host app renders here. Intended
  /// for HUD/menu/pause UI that would otherwise require the host app to
  /// wrap [GameWidget] in its own external `Stack`.
  ///
  /// Pointer handling (tap/drag forwarding to [Engine.input]) is scoped to
  /// the game canvas only, so taps on [overlay] content are not also
  /// forwarded to the game world as pointer events.
  ///
  /// [overlay] content can never hold *keyboard* focus, by design (see
  /// `descendantsAreFocusable` on the internal `Focus` node) — this keeps
  /// [Engine.input]'s polled key state reliable no matter what the host app
  /// taps in `overlay`. A consequence: any focus-driven widget placed here
  /// (a `TextField`, a `Slider` meant to be keyboard-adjustable via Tab +
  /// arrow keys, etc.) will render and remain mouse/touch-interactive, but
  /// will never become focused. Widgets that only need pointer interaction
  /// (buttons, sliders driven by drag) are unaffected.
  ///
  /// Defaults to `null` — nothing is added to the internal `Stack`, no
  /// behavior change.
  final Widget? overlay;

  /// Create a game widget
  const GameWidget({
    super.key,
    required this.engine,
    this.showFPS = true,
    this.showDebug = false,
    this.showTerminal = false,
    this.passthroughKeys,
    this.overlay,
  });

  @override
  State<GameWidget> createState() => _GameWidgetState();
}

class _GameWidgetState extends State<GameWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Ticker _ticker;

  /// Notifier used to trigger CustomPainter repaints without calling setState.
  final _repaintNotifier = _FrameNotifier();

  /// Signal for the HUD overlay (FPS / debug), updated at ~1 Hz cadence.
  /// Reads from [GameLoop.currentFPS] so there is a single source of truth.
  final Signal<int> _fpsSignal = Signal<int>(0);
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
    if (_colliderDebugger != null) {
      widget.engine.world.removeSystem(_colliderDebugger!);
      _colliderDebugger = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focusNode.dispose();
    _repaintNotifier.dispose();
    _fpsSignal.dispose();
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
      _fpsSignal.value = widget.engine.gameLoop.currentFPS;
      _lastFpsUpdate = now;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.showTerminal) {
      final terminal = widget.engine.terminal;

      // The toggle key is never GameWidget's (or the terminal's own input
      // buffer's) to give away — swallow every event for it (down, repeat,
      // and up) unconditionally, regardless of whether the terminal is
      // currently open or closed. Matching on KeyDownEvent alone would let
      // KeyRepeatEvents from holding the key down spam backticks into the
      // terminal's input right after it opens, and a KeyUpEvent that
      // happens to land while `terminal.isVisible` has just flipped to
      // false (i.e. the press that *closed* it) would otherwise leak
      // through to gameplay's polled key state below.
      if (event.logicalKey == LogicalKeyboardKey.backquote) {
        if (event is KeyDownEvent) {
          terminal.toggle();
        }
        return KeyEventResult.handled;
      }

      // When the terminal is visible, all other key events are consumed
      // by it — terminal capture always takes priority over
      // passthroughKeys.
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

    // Normal gameplay path: forward to the engine unconditionally so
    // polling-based systems (KeyboardInput.isKeyDown) keep seeing every
    // key regardless of what we return to Flutter below.
    widget.engine.input.handleKeyEvent(event);

    // Let the host app declare specific keys "not mine" — see
    // passthroughKeys' doc comment for the caveat on when an ancestor
    // actually receives this. Default (null) keeps the pre-existing
    // always-handled behavior exactly.
    if (widget.passthroughKeys?.contains(event.logicalKey) ?? false) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      canRequestFocus: true,
      skipTraversal: false,
      // Buttons/interactive widgets placed in `overlay` sit inside this
      // Focus node's subtree (see the overlay slot below). Without this,
      // tapping one would steal keyboard focus from `_focusNode` via
      // Flutter's default tap-to-focus behavior, and nothing hands it
      // back afterwards, leaving `_focusNode` as no longer the primary
      // focus. Descendants stay fully clickable via normal pointer/gesture
      // handling; this only opts them out of taking keyboard focus, so
      // `_focusNode` reliably stays the primary focus for the lifetime of
      // this widget.
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          // Main game canvas — pointer/gesture handling is scoped tightly
          // to just this region instead of the whole Stack, so overlay
          // content (below) isn't double-hit by world pointer forwarding.
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // Request focus when tapping on the game area
                _focusNode.requestFocus();
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
                onPointerUp: (event) =>
                    widget.engine.input.handlePointerEvent(event),
                onPointerMove: (event) =>
                    widget.engine.input.handlePointerEvent(event),
                onPointerHover: (event) =>
                    widget.engine.input.handlePointerEvent(event),
                onPointerSignal: (event) =>
                    widget.engine.input.handlePointerEvent(event),
                child: MouseRegion(
                  cursor: SystemMouseCursors.basic,
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
              ),
            ),
          ),

          // App-level overlay slot — sits above the canvas and below the
          // engine's own dev tools (FPS/terminal) so those stay usable
          // regardless of app content.
          if (widget.overlay != null) Positioned.fill(child: widget.overlay!),

          // FPS counter — isolated in its own RepaintBoundary and driven
          // by a Signal so it only rebuilds ~1 Hz.
          if (widget.showFPS)
            Positioned(
              top: 10,
              right: 10,
              child: RepaintBoundary(
                child: SignalBuilder<int>(
                  signal: _fpsSignal,
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

          // In-game developer terminal overlay — ListenableBuilder manages
          // its own subscription, so only this subtree rebuilds per
          // keystroke/toggle instead of the whole GameWidget tree.
          if (widget.showTerminal)
            Positioned.fill(
              child: ListenableBuilder(
                listenable: widget.engine.terminal,
                builder: (context, _) {
                  if (!widget.engine.terminal.isVisible) {
                    return const SizedBox.shrink();
                  }
                  return _TerminalOverlay(terminal: widget.engine.terminal);
                },
              ),
            ),
        ],
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
