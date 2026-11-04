# Input

_Gameplay_ · Read named actions from keyboard, mouse, gamepads and touch through engine.input, with local multiplayer, rebinding and on-screen controls.

`engine.input` is an `InputService` from `just_inputs`. Your game reads named actions such as `jump` and `move`, and an input asset binds them to keyboard keys, mouse buttons, gamepads and touch controls. Gameplay code never asks which device was used.

## How input works

| Piece | What it is |
|---|---|
| Asset | a `.input.json` file (`InputActionAsset`) holding everything below |
| Map | actions switched on and off together, such as `player` while playing and `ui` in menus |
| Action | something the player does: a `button`, an `axis` or a `vector2` |
| Binding | a control path such as `<Keyboard>/space` or `<Gamepad>/leftStick`, or a composite such as `2DVector` for WASD |
| Interaction, processor | how a press becomes the action (press, hold, tap) and changes on the way (dead zones, invert, scale) |
| Scheme | a way of playing (keyboard and mouse, gamepad, touch) and its bindings |

Keys are bound by position, so WASD stays under the left hand on an AZERTY keyboard. `GameWidget` sends keys and pointers to `engine.input`, and the engine updates it once per fixed step, and every frame while paused so menus and rebinding keep working.

## The input asset

Actions live in an asset, not in code. The Input Actions editor (the `just_input_editor` plugin, from the editor's Asset Store) writes these files; you can also write them by hand. List the folder under `flutter: assets:` in `pubspec.yaml`.

```json assets/input/game.input.json
{
  "format": "just_inputs",
  "version": 3,
  "nextId": 11,
  "name": "game",
  "maps": [
    {
      "id": "m1",
      "name": "player",
      "actions": [
        {
          "id": "a1", "name": "move", "type": "vector2",
          "bindings": [
            {
              "id": "b1", "composite": "2DVector",
              "parts": [
                { "id": "b2", "part": "up", "path": "<Keyboard>/w" },
                { "id": "b3", "part": "down", "path": "<Keyboard>/s" },
                { "id": "b4", "part": "left", "path": "<Keyboard>/a" },
                { "id": "b5", "part": "right", "path": "<Keyboard>/d" }
              ]
            },
            { "id": "b6", "path": "<Gamepad>/leftStick" }
          ]
        },
        {
          "id": "a2", "name": "jump", "type": "button",
          "bindings": [
            { "id": "b7", "path": "<Keyboard>/space" },
            { "id": "b8", "path": "<Gamepad>/buttonSouth" }
          ]
        }
      ]
    },
    {
      "id": "m2",
      "name": "ui",
      "actions": [
        {
          "id": "a3", "name": "pause", "type": "button",
          "bindings": [
            { "id": "b9", "path": "<Keyboard>/escape" },
            { "id": "b10", "path": "<Gamepad>/start" }
          ]
        }
      ]
    }
  ]
}
```

To build an asset in code, import `package:just_inputs/just_inputs.dart` for the asset model (`InputActionDef`, `ControlBindingDef` and the rest) and validation; the engine re-exports only what a game uses at run time.

## Load and read actions

Load the asset after `engine.initialize()`; until then no action is bound. `InputSystem`, a default system, then copies each player's `player`-map actions onto every entity with an `InputComponent`, by action name.

```dart lib/input.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_game_engine/just_game_engine.dart';

Future<void> loadInput(Engine engine) async {
  final text = await rootBundle.loadString('assets/input/game.input.json');
  engine.input.loadAsset(InputActionAsset.parse(text));
  // Players' saved bindings, so they apply from the start.
  await engine.input.players.preloadOverrides();
  // Gamepads are opt-in: attaching them opens platform channels.
  await engine.input.attachGamepads();

  // Actions outside the player map are read from the service. Input keeps
  // updating while the engine is paused, so this can also resume it.
  engine.input.actions.action('ui/pause').onPerformed((_) {
    engine.isPaused ? engine.resume() : engine.pause();
  });
}

/// Moves every entity that has an InputComponent, top-down style.
class WalkSystem extends System {
  static const double speed = 240;

  // After InputSystem (100) has copied the actions in.
  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [InputComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final input = entity.getComponent<InputComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>()!.velocity;
      final move = input.vector('move'); // y is down, like the world
      velocity.x = move.dx * speed;
      velocity.y = move.dy * speed;
    });
  }
}
```

`InputComponent` reads player 1 by default; `InputComponent(playerIndex: 1)` reads player 2 and `playerIndex: -1` reads every device at once.

| Method | Returns |
|---|---|
| `vector('move')` | a vector action's value as an `Offset`, y down |
| `axis('throttle')` | how far an axis or button action is pushed |
| `isDown('jump')` | whether a button is held |
| `wasPressed('jump')` | whether it went down this step (true for one step only) |
| `wasReleased('jump')` | whether it was let go this step |
| `wasPerformed('jump')` | whether the action completed this step, for example a hold |

Outside the ECS, read an action by its `map/name` path: `engine.input.actions.action('player/jump')` has `isPressed()`, `wasPressedThisFrame()`, `readVector2()`, `readAxis()` and the callbacks `onStarted`, `onPerformed` and `onCanceled`. Switch a whole map off for a menu with `engine.input.actions.map('player')!.disable()` and back on with `enable()`.

## Gamepads

Gamepads are opt-in: call `await engine.input.attachGamepads()` once. Bind them with paths such as `<Gamepad>/leftStick` and `<Gamepad>/buttonSouth`, and list the connected pads with `engine.input.gamepads`. On the web, gamepads work in JavaScript and WebAssembly builds once a button is pressed, because browsers hide pads until then.

## Local multiplayer

`engine.input.players` is a `PlayerInputManager`. A single-player game can leave it off and read the shared actions. Call `start()` and players come and go as the asset's `players` block says, for example `"players": {"max": 2, "joining": "onJoinAction", "joinActions": ["player/join"]}`:

- player 1 is whoever plays first, with whatever they touch;
- a device nobody uses joins as the next player when a join action is performed on it (give the join action a hold, so a quick press can mean something else);
- a player whose pad is pulled out is lost until it, or another pad, comes back (`deviceLost`, `deviceRegained`, `dropLost`).

```dart lib/coop.dart
void startCoop(Engine engine) {
  final players = engine.input.players;
  players.joined.listen((player) {
    engine.world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(),
      InputComponent(playerIndex: player.index),
      Rectangle2DComponent(width: 32, height: 48),
    ], name: 'Player ${player.index + 1}');
  });
  players.start();
}
```

`players[1]` is player 2's `PlayerInput`, or null while nobody is playing as them, and `engine.input.actionsFor(1)` is their live actions. Set `players.joiningEnabled = false` to stop new players joining, for example while paused.

## Rebinding

`rebindPlayer(player, bindingId)` listens for the next control the player touches, keeps it and saves it, swapping with any binding it clashes with. It works while the game is paused, takes keys before any focused widget, and Escape alone cancels. `player.resetOverrides()` goes back to the asset's bindings.

The engine saves each player's bindings in its own settings store (`CacheInputOverrideStore`), apart from the cache's entries, so `engine.cache.clearAll()` leaves them alone. Call `engine.input.players.preloadOverrides()` after `loadAsset`, as above, to apply them at the next start. A `PlayerInput` exists once its player has joined, so start the player manager when your game offers rebinding.

## On-screen controls

The asset's `onScreen` list places touch buttons and sticks relative to the screen, for example `{"id": "jump", "kind": "button", "anchor": [0.8, 0.6], "label": "A"}`. `anchor` runs from -1 to 1 on each axis like Flutter's `Alignment`, and `size` is a share of the screen's shorter side. A stick's `mode` is `fixed` or `floating` (under the thumb, inside its `region`). Bind them like any other control: `<OnScreen>/jump`.

```dart lib/game_screen.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

Widget gameScreen(Engine engine) => GameWidget(
  engine: engine,
  overlay: Positioned.fill(
    // Shown on phones and tablets; OnScreenVisibility.always shows them
    // everywhere.
    child: OnScreenControls(input: engine.input),
  ),
);

/// A controls page: each action with a button to rebind it.
Widget controlsPage(Engine engine) {
  final player = engine.input.players[0];
  if (player == null) return const Text('Press any key to join.');
  return RebindList(player: player, maps: const ['player']);
}
```

`widgets.dart` also has `RebindButton`, `RebindRow` and `BindingLabel` for building your own rebinding screen.

## Mouse look and pointer lock

For mouse look, set `engine.input.lockPointerOnClick = true`. `GameWidget` then takes hold of the pointer on a press on the game: the cursor hides, stays in the window, and raw mouse movement feeds the mouse device. Escape lets go, as does the window going behind another, and the next click takes hold again. You can also call `engine.input.pointerLock.lock()` and `unlock()` yourself. Pointer lock works on Windows today; elsewhere `pointerLock.isSupported` is false and nothing happens.

A camera should read look input once per rendered frame rather than once per fixed step. `LookActions.addTo(asset)` adds a `look` action for the mouse and `lookStick` for the right stick, and `LookInput(engine.input.actionsFor(0)!).read(dt)` returns the turn in radians.
