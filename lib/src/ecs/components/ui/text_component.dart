/// UI text component.
library;

import 'package:flutter/material.dart';

import 'ui_component.dart';

/// UI text component data.
class TextComponent extends UIComponent {
  /// The displayed text.
  String text;

  /// Styling for the text.
  TextStyle textStyle;

  /// Text alignment.
  TextAlign textAlign;

  /// Create a text UI component.
  TextComponent({
    required this.text,
    this.textStyle = const TextStyle(color: Colors.white, fontSize: 16),
    this.textAlign = TextAlign.center,
    super.size = const Size(0, 0),
    super.visible,
    super.enabled,
    super.layer,
  });

  @override
  String toString() => 'UIText("$text")';
}
