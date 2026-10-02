/// Game Widget
///
/// Flutter widget that integrates the game engine with Flutter's rendering pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:just_signals/just_signals.dart';
import '../ecs/systems/debug/collider_debugger_system.dart';
import 'engine.dart';
import '../ecs/ecs.dart' show World;
import '../ecs/systems/rendering/render_system.dart';
import '../subsystems/localization/localization_widget.dart';
import 'game_layers.dart';
import '../subsystems/rendering/impl/game_terminal.dart';

/// Main game widget that renders the game
///
/// This widget integrates the game engine with Flutter's widget tree
/// and handles the rendering pipeline.
class GameWidget extends StatefulWidget {
  /// The game engine instance. It may be given before
  /// [Engine.initialize] has finished: the widget starts drawing and
  /// ticking it once it is ready ([Engine.stateListenable]), with no
  /// rebuild needed.
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

  /// Whether the layers packages registered on [Engine.layers] are drawn
  /// — the in-game interface among them. See [GameLayer].
  ///
  /// Unlike [overlay], layers sit *outside* the internal `Focus` node, so a
  /// text field in one can be typed into and a menu walked with the arrow
  /// keys. While a layer holds focus the game does not see key presses,
  /// which is what typing into a field should do.
  final bool showLayers;

  /// Create a game widget
  const GameWidget({
    super.key,
    required this.engine,
    this.showFPS = true,
    this.showDebug = false,
    this.showTerminal = false,
    this.passthroughKeys,
    this.overlay,
    this.showLayers = true,
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

  /// The ticker time of the last FPS update.
  Duration _lastFpsUpdate = Duration.zero;

  final FocusNode _focusNode = FocusNode();
  ColliderDebuggerSystem? _colliderDebugger;

  /// This view's half of each registered layer — with the layer it was made
  /// for — by layer id.
  final Map<String, _LayerView> _controllers = {};

  /// Whether the app going to the background paused the engine — and so
  /// its coming back may resume it. A game the player paused stays paused.
  bool _pausedByLifecycle = false;

  /// The world's render system, found once rather than every frame; see
  /// [_renderSystemOf].
  RenderSystem? _renderSystem;
  World? _renderSystemWorld;
  int _systemCountAtScan = -1;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Create ticker for rendering — only signals the painter, no setState.
    _ticker = createTicker(_onTick);
    _ticker.start();

    // Draw the world (and the debug overlay, if asked) now if the engine is
    // ready, else as soon as it is.
    widget.engine.stateListenable.addListener(_onEngineState);
    _wire();

    // Request focus for keyboard input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    // Layers can be registered after this widget is on screen.
    widget.engine.layers.addListener(_onLayersChanged);
    _syncControllers();

    // Keys held when the game loses the keyboard would never see their
    // key-ups: let them go.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && !_layerHasFocus) _releaseKeyboard();
    });
  }

  /// The engine's input lets go of every key — while it has one.
  void _releaseKeyboard() {
    final engine = widget.engine;
    if (engine.isInitialized) engine.input.releaseKeyboard();
  }

  /// Hands a pointer event to the engine's input, while it has one.
  void _pointer(PointerEvent event) {
    final engine = widget.engine;
    if (engine.isInitialized) engine.input.handlePointerEvent(event);
  }

  /// Whether this view has wired its engine — the world's drawing hooked
  /// into rendering, the debug overlay applied. Done once the engine is
  /// initialized, which may be after this widget is built.
  bool _wired = false;

  void _onEngineState() {
    if (mounted) _wire();
  }

  /// Wires the engine, once, when it is ready.
  void _wire() {
    final engine = widget.engine;
    if (_wired || !engine.isInitialized) return;
    _wired = true;
    // ECS world rendering runs inside the subsystem pipeline, so both share
    // the same camera transform (unified render pipeline).
    engine.rendering.overlayHooks.addIfAbsent(engine.world.render);
    _applyDebug();
  }

  /// Shows the debug overlay on the engine when [GameWidget.showDebug].
  void _applyDebug() {
    if (!widget.engine.isInitialized) return;
    widget.engine.rendering.debugMode = widget.showDebug;
    if (widget.showDebug) {
      _colliderDebugger = ColliderDebuggerSystem(
        camera: widget.engine.cameraSystem.mainCamera,
      );
      widget.engine.world.addSystem(_colliderDebugger!);
    }
  }

  /// Takes the debug overlay off [engine] — unless its world is gone with
  /// it.
  void _removeDebug(Engine engine) {
    final debugger = _colliderDebugger;
    if (debugger == null) return;
    _colliderDebugger = null;
    if (engine.isInitialized) engine.world.removeSystem(debugger);
  }

  void _disposeControllers() {
    for (final view in _controllers.values) {
      view.controller.dispose();
    }
    _controllers.clear();
  }

  @override
  void didUpdateWidget(GameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final engineChanged = !identical(oldWidget.engine, widget.engine);
    if (engineChanged) {
      // The listener belongs to the old engine's layers: left there, it
      // would rebuild this view for layers it no longer shows. A disposed
      // engine's layers are gone, and the listener with them.
      if (!oldWidget.engine.isDisposed) {
        oldWidget.engine.layers.removeListener(_onLayersChanged);
      }
      widget.engine.layers.addListener(_onLayersChanged);
      oldWidget.engine.stateListenable.removeListener(_onEngineState);
      widget.engine.stateListenable.addListener(_onEngineState);
      _disposeControllers();
      _syncControllers();
      _renderSystem = null;
      _renderSystemWorld = null;
      _pausedByLifecycle = false;
    }
    if (engineChanged || oldWidget.showDebug != widget.showDebug) {
      _removeDebug(oldWidget.engine);
      if (engineChanged &&
          oldWidget.showDebug &&
          oldWidget.engine.isInitialized) {
        oldWidget.engine.rendering.debugMode = false;
      }
      if (engineChanged) {
        _wired = false;
        _wire();
      } else if (_wired) {
        _applyDebug();
      }
    }
  }

  @override
  void dispose() {
    // The engine may have been disposed first — a game closing — and taken
    // its world and layers with it.
    _removeDebug(widget.engine);
    widget.engine.stateListenable.removeListener(_onEngineState);
    if (!widget.engine.isDisposed) {
      widget.engine.layers.removeListener(_onLayersChanged);
    }
    _disposeControllers();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focusNode.dispose();
    _outerFocus.dispose();
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
          _pausedByLifecycle = true;
        }
        break;
      case AppLifecycleState.resumed:
        // Only what going to the background paused: resuming whatever was
        // paused un-paused a game the player had paused from its menu.
        if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
          if (widget.engine.isPaused) widget.engine.resume();
        }
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final engine = widget.engine;
    // Not ready yet, or disposed under this widget: nothing to run or draw.
    if (!engine.isInitialized) return;
    // Drive the game loop from the vsync Ticker — single unified loop —
    // timed by the ticker's own frame timestamps.
    engine.gameLoop.tick(elapsed);
    // Push the sub-frame interpolation factor to the ECS RenderSystem so
    // physics-driven entities lerp smoothly between fixed-timestep positions.
    _renderSystemOf(engine.world)?.interpolation =
        engine.gameLoop.interpolation;
    // Signal the CustomPainter to repaint — no widget rebuild needed.
    _repaintNotifier.notify();
    if (widget.showLayers) {
      final layers = engine.layers;
      for (final entry in _controllers.entries) {
        if (layers.isEnabled(entry.key)) entry.value.controller.onFrame();
      }
    }
    _updateFPS(elapsed);
  }

  /// [world]'s render system, kept between frames: finding it walks the
  /// world's systems. The kept one is trusted while it is still in
  /// [world] ([RenderSystem.isAttached]); with none found, the world is
  /// searched again only once its systems change in number.
  RenderSystem? _renderSystemOf(World world) {
    final kept = _renderSystem;
    if (kept != null && kept.isAttached && identical(kept.world, world)) {
      return kept;
    }
    final count = world.systems.length;
    if (kept == null &&
        identical(_renderSystemWorld, world) &&
        count == _systemCountAtScan) {
      return null;
    }
    _renderSystemWorld = world;
    _systemCountAtScan = count;
    return _renderSystem = world.getSystem<RenderSystem>();
  }

  /// Makes a controller for each layer that has none, and drops the ones
  /// whose layer is gone — or was replaced by another under the same id,
  /// whose controller would otherwise go on ticking the old one's screens.
  void _syncControllers() {
    final layers = widget.engine.layers.all;
    final live = {for (final layer in layers) layer.id: layer};
    _controllers.removeWhere((id, view) {
      if (identical(live[id], view.layer)) return false;
      view.controller.dispose();
      return true;
    });
    for (final layer in layers) {
      _controllers.putIfAbsent(
        layer.id,
        () => _LayerView(layer, layer.createController(widget.engine)),
      );
    }
  }

  void _onLayersChanged() {
    if (!mounted) return;
    void apply() {
      if (!mounted) return;
      setState(_syncControllers);
    }

    // Registering mid-build (a layer added from a build method) waits for
    // the frame to finish rather than dirtying the tree being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  /// Updates the FPS badge about once a second of ticker time.
  void _updateFPS(Duration elapsed) {
    if (elapsed < _lastFpsUpdate) _lastFpsUpdate = elapsed;
    if (elapsed - _lastFpsUpdate >= const Duration(seconds: 1)) {
      _fpsSignal.value = widget.engine.gameLoop.currentFPS;
      _lastFpsUpdate = elapsed;
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
    if (widget.engine.isInitialized) widget.engine.input.handleKeyEvent(event);

    // Let the host app declare specific keys "not mine" — see
    // passthroughKeys' doc comment for the caveat on when an ancestor
    // actually receives this. Default (null) keeps the pre-existing
    // always-handled behavior exactly.
    if (widget.passthroughKeys?.contains(event.logicalKey) ?? false) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Whether keyboard focus is somewhere in a layer — a menu button, a text
  /// field.
  bool get _layerHasFocus {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null &&
        !identical(focus, _focusNode) &&
        _outerFocus.hasFocus;
  }

  final FocusNode _outerFocus = FocusNode(
    debugLabel: 'GameWidget.outer',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Keys that reach here came up from a layer, which did not want them:
  /// the game still hears them, so a player can move while a HUD button has
  /// focus. Keys the game's own node handled never get here. In
  /// a text field only key-ups go through — typing is not playing — so
  /// nothing stays held.
  KeyEventResult _handleBubbledKey(FocusNode node, KeyEvent event) {
    if (_focusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    final typing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    if ((!typing || event is KeyUpEvent) && widget.engine.isInitialized) {
      widget.engine.input.handleKeyEvent(event);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Layers are siblings of the game, not descendants: everything inside
    // the Focus node below is deliberately unfocusable, and a text field
    // that cannot be focused is not a text field. The engine's own dev tools
    // sit above them, so a HUD can never hide them. Keys a layer lets go of
    // bubble to the outer Focus, and on to the game's input.
    // The engine's strings, for the layers and anything else over the game.
    final l10n = widget.engine.context.localization;
    final stack = _stack();
    return Focus(
      focusNode: _outerFocus,
      onKeyEvent: _handleBubbledKey,
      onFocusChange: (focused) {
        if (!focused) _releaseKeyboard();
      },
      child: l10n == null
          ? stack
          : LocalizationScope(manager: l10n, child: stack),
    );
  }

  Widget _stack() {
    return Stack(
      children: [
        Positioned.fill(child: _game()),
        if (widget.showLayers)
          for (final layer in widget.engine.layers.all)
            if (widget.engine.layers.isEnabled(layer.id))
              if (_controllers[layer.id] case final view?)
                Positioned.fill(
                  key: ValueKey('layer:${layer.id}'),
                  child: Builder(builder: view.controller.build),
                ),
        if (widget.showFPS) _fpsCounter(),
        if (widget.showTerminal) _terminalOverlay(),
      ],
    );
  }

  /// The FPS badge — its own RepaintBoundary, driven by a Signal, so it
  /// rebuilds about once a second and nothing else does.
  Widget _fpsCounter() => Positioned(
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
  );

  /// The developer terminal. `ListenableBuilder` keeps each keystroke to
  /// this subtree rather than the whole widget.
  Widget _terminalOverlay() => Positioned.fill(
    child: ListenableBuilder(
      listenable: widget.engine.terminal,
      builder: (context, _) {
        if (!widget.engine.terminal.isVisible) return const SizedBox.shrink();
        return _TerminalOverlay(terminal: widget.engine.terminal);
      },
    ),
  );

  Widget _game() {
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
                  _pointer(event);
                },
                onPointerUp: _pointer,
                onPointerMove: _pointer,
                onPointerHover: _pointer,
                onPointerSignal: _pointer,
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
        ],
      ),
    );
  }
}

/// A layer's controller in one view, with the layer it was made for.
class _LayerView {
  _LayerView(this.layer, this.controller);
  final GameLayer layer;
  final GameLayerController controller;
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

  /// Paints [engine]; the view wires the world's drawing into it.
  _GamePainter(this.engine, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    // Nothing to draw with before the engine is ready, or once it is gone.
    if (!engine.isInitialized) return;
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
