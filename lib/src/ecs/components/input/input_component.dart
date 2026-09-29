library;

import 'package:flutter/painting.dart';

import '../../ecs.dart';

/// One player's input, copied onto the entity they control each step by
/// the input system, by action name — so gameplay reads `input.isDown('jump')`
/// and never asks which device or which player.
class InputComponent extends Component {
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
  final Set<String> released = {};
  final Set<String> performed = {};

  Offset vector(String action) => vectors[action] ?? Offset.zero;
  double axis(String action) => axes[action] ?? 0;
  bool isDown(String action) => down[action] ?? false;
  bool wasPressed(String action) => pressed.contains(action);
  bool wasReleased(String action) => released.contains(action);
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
