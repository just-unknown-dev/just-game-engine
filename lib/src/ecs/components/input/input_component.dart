library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Input component - Tracks input state for an entity
class InputComponent extends Component {
  /// Movement direction (-1 to 1 for each axis)
  Offset moveDirection = Offset.zero;

  /// Action buttons state
  final Map<String, bool> buttons = {};

  /// Check if button is pressed
  bool isButtonPressed(String button) => buttons[button] ?? false;

  /// Set button state
  void setButton(String button, bool pressed) {
    buttons[button] = pressed;
  }

  @override
  String toString() =>
      'Input(move: $moveDirection, buttons: ${buttons.length})';
}
