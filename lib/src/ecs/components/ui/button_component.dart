/// UI button component.
library;

import 'package:flutter/material.dart';

import 'ui_component.dart';

/// UI button component data.
class ButtonComponent extends UIComponent {
  /// Button label.
  String text;

  /// Label style.
  TextStyle textStyle;

  /// Base fill color.
  Color backgroundColor;

  /// Fill color while pressed.
  Color pressedColor;

  /// Optional border color.
  Color? borderColor;

  /// Corner radius.
  double borderRadius;

  /// Callback invoked when the button is pressed.
  VoidCallback? onPressed;

  /// Runtime pressed state.
  bool isPressed;

  /// Create a UI button component.
  ButtonComponent({
    required this.text,
    required super.size,
    this.textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    this.backgroundColor = const Color(0xFF3A5070),
    this.pressedColor = const Color(0xFF4E6A96),
    this.borderColor,
    this.borderRadius = 8,
    this.onPressed,
    this.isPressed = false,
    super.visible,
    super.enabled,
    super.layer,
  });

  /// Effective fill color based on pressed state.
  Color get currentColor => isPressed ? pressedColor : backgroundColor;

  /// Attempt to trigger button action.
  void trigger() {
    if (!enabled || !visible) return;
    onPressed?.call();
  }

  @override
  String toString() => 'UIButton("$text")';
}
