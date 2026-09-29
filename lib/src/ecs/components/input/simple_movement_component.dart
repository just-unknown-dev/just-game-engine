import 'package:flutter/painting.dart';
import '../../ecs.dart';

/// Moves an entity straight from a vector action — no physics. For
/// top-down games, cursors and quick tests.
class SimpleMovementComponent extends Component {
  SimpleMovementComponent({
    this.speed = 220.0,
    this.action = 'move',
    this.playerIndex = 0,
    this.normalizeDiagonal = true,
    this.deadZone = 0.05,
  });

  double speed;

  /// The vector action that steers it.
  String action;

  /// Whose: 0 for player 1, -1 for anyone.
  int playerIndex;

  bool normalizeDiagonal;
  double deadZone;

  /// Runtime-only resolved direction, not serialised.
  Offset lastDirection = Offset.zero;
}
