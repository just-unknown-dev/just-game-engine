# UI over the game

_Flutter & shipping_ · Host the game in a GameWidget, draw a HUD with its overlay, put menus and text fields on engine.layers, and use the ready-made widgets.

UI is ordinary Flutter. `GameWidget` shows the game, and you draw widgets over it in one of two ways: its `overlay`, for a HUD, or `engine.layers`, for menus and anything that needs the keyboard.

## GameWidget

`GameWidget(engine: engine)` ticks the game loop from Flutter's frame ticker, draws the world, and passes keys and pointers to `engine.input`. You can build it before `initialize()` has finished: it starts ticking and drawing the engine once it is ready, with no rebuild.

| Parameter | Default | What it does |
|---|---|---|
| `engine` | required | The engine to show. |
| `showFPS` | `true` | An `FPS: n` badge in the top right corner. |
| `showDebug` | `false` | The debug overlay; see [Debugging & stats](/docs/debugging). |
| `showTerminal` | `false` | The developer terminal, toggled with the backquote key. |
| `overlay` | none | A widget stacked over the game canvas. |
| `showLayers` | `true` | Whether the layers on `engine.layers` are drawn. |
| `passthroughKeys` | none | Keys reported to Flutter as not handled, so a focus ancestor may also act on them. The game still sees them. |

From bottom to top, a `GameWidget` stacks the game canvas with its `overlay`, then the layers, then the FPS badge and the terminal. It also pauses a running engine when the app goes to the background and resumes it on return, but only if it paused it itself: a game the player paused stays paused.

Two `GameWidget`s can show one engine; each frame is counted once. When `engine.context.localization` is set, everything the widget draws sits under a `LocalizationScope` for it (see [Localization](/docs/localization)). Set `engine.cursor.value` to `SystemMouseCursors.none` to hide the mouse over the game.

## A HUD with the overlay

`GameWidget(overlay: ...)` stacks your widgets over the game. Taps on them do not reach the game. They can never take keyboard focus, which keeps the game's key state reliable, so use the overlay for a HUD and buttons, not for text fields.

```dart lib/game_screen.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

/// The game with a score and touch controls over it.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.engine, required this.score});

  final Engine engine;
  final ValueNotifier<int> score;

  @override
  Widget build(BuildContext context) {
    return GameWidget(
      engine: engine,
      showFPS: false,
      overlay: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: ValueListenableBuilder<int>(
              valueListenable: score,
              builder: (context, value, _) => Text(
                'Score $value',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          ),
          // The on-screen sticks and buttons the input asset defines,
          // shown on touch platforms.
          Positioned.fill(child: OnScreenControls(input: engine.input)),
        ],
      ),
    );
  }
}
```

## Menus and text fields with layers

A `GameLayer` registered on `engine.layers` (a `GameLayers`) is drawn in every `GameWidget` that shows the engine. A layer has an `id`, an `order` (lower draws first) and `createController(engine)`. Each `GameWidget` asks it for its own `GameLayerController`, whose `build` draws the widgets, `onFrame` runs once a frame after the game has stepped, and `dispose` releases its state.

Layers sit outside the game's focus node, so a text field in a layer can be typed into and a menu walked with the arrow keys. Keys a layer does not use still reach the game; while a text field has focus, only key-ups go through.

```dart lib/pause_menu.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A pause menu. Register once: `engine.layers.register(const PauseMenu())`.
class PauseMenu extends GameLayer {
  const PauseMenu();

  @override
  String get id => 'pause_menu';

  @override
  GameLayerController createController(Engine engine) => _PauseMenuView(engine);
}

class _PauseMenuView extends GameLayerController {
  _PauseMenuView(this.engine);

  final Engine engine;
  final ValueNotifier<bool> _paused = ValueNotifier(false);

  // Called every frame, even while the engine is paused.
  @override
  void onFrame() => _paused.value = engine.isPaused;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _paused,
    builder: (context, paused, _) => paused
        ? Center(
            child: FilledButton(
              autofocus: true,
              onPressed: engine.resume,
              child: const Text('Resume'),
            ),
          )
        : const SizedBox.shrink(),
  );

  @override
  void dispose() => _paused.dispose();
}
```

`engine.layers` also has `unregister(id)`, `byId(id)`, `all` and `clear()`. `setEnabled(id, false)` hides a layer and keeps its controllers' state; `isEnabled(id)` reads it back. `GameWidget(showLayers: false)` hides them all in one view.

## Ready-made widgets

`package:just_game_engine/widgets.dart` holds optional screen widgets. The main library leaves them out, so import it only when you use them.

| Widget | What it does |
|---|---|
| `OnScreenControls` | Touch sticks and buttons from the input asset, with `OnScreenVisibility`, `OnScreenButtonFace` and `OnScreenStickPainter` to style them. See [Input](/docs/input). |
| `RebindList`, `RebindButton`, `RebindRow`, `BindingLabel` | A player's controls, each with a button to rebind it. |
| `DialogueBoxWidget`, `DialogueChoicesWidget` | Lines and choices of a `DialogueRunner`. See [Dialogue](/docs/dialogue). |
| `SubtitleOverlay` | The cues of a `SubtitleController`. |
| `LocalizedText`, `LocalizationBuilder`, `LocaleSelector` | Text and widgets that follow the locale, with `context.t()` from `L10nContext`. |
| `GameCameraControls` | Zoom by mouse wheel, pinch or buttons, and drag to pan. |

For HUDs and menus designed in an editor and saved as `.ui.json` screens, there is the `just_ui_editor` package, which draws its screens through `engine.layers`. It is not published on pub.dev.

## Engine · Signal · Presentation

For state that several widgets share, or that the game updates continuously, the engine suggests three layers, built from pieces it already has:

1. **Engine layer**: systems and components, the only code that touches ECS types. It pushes continuous values into signals, and one-off moments through `world.events`.
2. **State layer**: plain Dart classes holding `Signal` and `Computed` fields, with no Flutter or ECS imports, so you can unit-test them without a widget tree.
3. **Presentation layer**: widgets that read the state layer through `SignalBuilder` and call back through methods, never reaching into the `World`.

`Signal` and `Computed` come with the engine; `SignalBuilder` needs `just_signals` in your pubspec.

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

// State layer.
class PlayerSignals {
  final Signal<double> health = Signal(1.0);
}

// Engine layer: writes the signal once a step, after the gameplay systems.
class PlayerHudSync extends System {
  PlayerHudSync(this.signals);

  final PlayerSignals signals;
  Entity? _player;

  @override
  int get priority => SystemPriorities.gameplay - 5;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    var player = _player;
    if (player == null || !player.isAlive) {
      player = _player = world.findTagged('player'); // looked up once
    }
    final health = player?.getComponent<HealthComponent>();
    if (health != null) signals.health.value = health.healthPercent;
  }
}

// Presentation layer.
class HealthBar extends StatelessWidget {
  const HealthBar({super.key, required this.signals});

  final PlayerSignals signals;

  @override
  Widget build(BuildContext context) => SignalBuilder<double>(
    signal: signals.health,
    builder: (context, value, _) => LinearProgressIndicator(value: value),
  );
}
```

Give the writing system a priority after everything it reads, so a signal is written once per step with settled data. Setting a `Signal` to the value it already holds does nothing, so you need no equality check of your own. For a one-off toggle used by a single widget, a plain `setState` is simpler.
