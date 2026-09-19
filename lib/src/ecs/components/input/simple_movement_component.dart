import 'package:flutter/painting.dart';
import '../../ecs.dart';

/// Keyboard/joystick movement component.
/// Editor registration and inspector fields live in SimpleMovementEditorComponent.
class SimpleMovementComponent extends Component {
  SimpleMovementComponent({
    this.speed = 220.0,
    this.useKeyboard = true,
    this.useJoystick = true,
    this.normalizeDiagonal = true,
    this.deadZone = 0.05,
  });

  double speed;
  bool useKeyboard;
  bool useJoystick;
  bool normalizeDiagonal;
  double deadZone;

  /// Runtime-only resolved direction, not serialised.
  Offset lastDirection = Offset.zero;
}
