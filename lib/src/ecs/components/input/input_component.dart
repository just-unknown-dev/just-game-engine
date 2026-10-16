library;

import 'package:flutter/painting.dart';

import '../../ecs.dart';

/// One player's input, copied onto the entity they control each step by
/// the input system, by action name — so gameplay reads `input.isDown('jump')`
/// and never asks which device or which player.
class InputComponent extends Component {
  /// Input for player [playerIndex]: 0 for player 1, -1 for every device at
  /// once. Empty until the input system first fills it.
  InputComponent({this.playerIndex = 0});

  /// Whose input: 0 for player 1. -1 reads the shared actions — every
  /// device at once, whoever is playing.
  int playerIndex;

  /// Vector actions' values, y down.
  final Map<String, Offset> vectors = {};

  /// Axis and button actions' values (a button's is how far it is pushed).
  final Map<String, double> axes = {};

  /// Buttons held.
  final Map<String, bool> down = {};

  /// Buttons pressed, released, and actions performed this step.
  final Set<String> pressed = {};

  /// Buttons let go this step.
  final Set<String> released = {};

  /// Actions performed this step — for a plain button, when it went down;
  /// for one with an interaction (hold, tap), when that completed.
  final Set<String> performed = {};

  /// The vector action [action]'s value, y down; zero when it has none.
  Offset vector(String action) => vectors[action] ?? Offset.zero;

  /// How far the axis or button action [action] is pushed; 0 when it has
  /// no value.
  double axis(String action) => axes[action] ?? 0;

  /// Whether the button [action] is held; false when it has no value.
  bool isDown(String action) => down[action] ?? false;

  /// Whether [action] went down this step.
  bool wasPressed(String action) => pressed.contains(action);

  /// Whether [action] was let go this step.
  bool wasReleased(String action) => released.contains(action);

  /// Whether [action] was performed this step (see [performed]).
  bool wasPerformed(String action) => performed.contains(action);

  /// Sets a vector by hand — for tests, and for input from elsewhere.
  void setVector(String action, Offset value) => vectors[action] = value;

  /// Holds or lets go of a button by hand, with the edges that go with it.
  void setDown(String action, bool value) {
    final was = isDown(action);
    down[action] = value;
    axes[action] = value ? 1 : 0;
    if (value && !was) pressed.add(action);
    if (!value && was) released.add(action);
  }

  /// Nothing held, nothing moving.
  void clear() {
    vectors.clear();
    axes.clear();
    down.clear();
    pressed.clear();
    released.clear();
    performed.clear();
  }

  @override
  String toString() =>
      'Input(player: $playerIndex, held: ${down.entries.where((e) => e.value).map((e) => e.key).join(', ')})';
}
