import 'package:flutter/painting.dart';
import '../../ecs.dart';

/// Moves an entity straight from a vector action — no physics. For
/// top-down games, cursors and quick tests.
class SimpleMovementComponent extends Component {
  /// Movement steered by player 1's `move` action at 220 world units per
  /// second, diagonals capped to full speed, with a 0.05 dead zone.
  SimpleMovementComponent({
    this.speed = 220.0,
    this.action = 'move',
    this.playerIndex = 0,
    this.normalizeDiagonal = true,
    this.deadZone = 0.05,
  });

  /// Speed at a full push (vector length 1), in world units per second.
  double speed;

  /// The vector action that steers it.
  String action;

  /// Whose: 0 for player 1, -1 for anyone.
  int playerIndex;

  /// Whether a direction longer than 1 (two keys held at once) is scaled
  /// back to length 1, so moving diagonally is no faster.
  bool normalizeDiagonal;

  /// Directions this long or shorter count as no push: the entity does
  /// not move and [lastDirection] is zero.
  double deadZone;

  /// Runtime-only resolved direction, not serialised.
  Offset lastDirection = Offset.zero;
}
