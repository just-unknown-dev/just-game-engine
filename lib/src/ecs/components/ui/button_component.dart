/// A button in the world, on the game's canvas.
library;

import 'package:flutter/painting.dart';

import '../../../subsystems/ui/ui_actions.dart';
import '../../../subsystems/ui/ui_text_style.dart';
import '../../../subsystems/ui/ui_theme.dart';
import 'ui_component.dart';

/// What a button is doing right now.
enum UiInteractionState {
  normal,
  hovered,
  pressed,

  /// Switched off: it is drawn faded and does nothing.
  disabled;

  /// How much the button's colour is lifted or dulled in this state.
  double get tint => switch (this) {
    normal => 0,
    hovered => 0.12,
    pressed => -0.12,
    disabled => 0,
  };
}

/// A button the player can press, drawn at an entity's transform.
///
/// What it *does* is a list of [UiAction]s — a name and an argument that a
/// scene can hold — because a file cannot save a Dart closure. Game code
/// registers what a name means through [UiActions].
class ButtonComponent extends UIComponent {
  ButtonComponent({
    this.label = 'Button',
    this.labelStyle = const UiTextStyle(),
    this.styleRole = 'button',
    this.onPressed = UiActionList.empty,
    this.colorRole = 'primary',
    this.color,
    this.borderColor,
    this.borderRadius = 8,
    super.size = const Size(160, 44),
    super.visible,
    super.enabled,
    super.layer,
  });

  /// What is written on it. Bindings and tags work as they do in a text.
  String label;

  /// What the label says for itself, over [styleRole] in the theme.
  UiTextStyle labelStyle;

  /// The theme's text style underneath [labelStyle].
  String styleRole;

  /// What happens when it is pressed.
  UiActionList onPressed;

  /// The theme colour it is drawn in — `primary`, `danger`, `surface`.
  String colorRole;

  /// A colour of its own, which wins over [colorRole] when set.
  Color? color;

  Color? borderColor;
  double borderRadius;

  // ── Runtime ──────────────────────────────────────────────────────────────

  /// What the pointer is doing to it. Set by `UiPointerSystem`.
  UiInteractionState state = UiInteractionState.normal;

  /// Kept for the frame a press lands on, so a game can react without
  /// listening to anything.
  bool wasPressed = false;

  bool get isPressed => state == UiInteractionState.pressed;

  /// Whether a pointer may do anything with this.
  bool get isInteractive => enabled && visible;

  /// The colour it is drawn in under [theme], with its state's tint.
  Color colorUnder(UiTheme theme) {
    final base =
        color ?? theme.color(colorRole, fallbackColor: theme.palette.primary);
    final lift = state.tint;
    if (lift == 0) return base;
    return lift > 0
        ? Color.lerp(base, const Color(0xFFFFFFFF), lift)!
        : Color.lerp(base, const Color(0xFF000000), -lift)!;
  }

  /// How solid it looks: a disabled button is faded rather than hidden, so
  /// a player can see there is something there to come back to.
  double get opacity => state == UiInteractionState.disabled ? 0.45 : 1;

  UiTextStyle labelStyleUnder(UiTheme theme) =>
      labelStyle.over(theme.textStyle(styleRole));

  /// Runs what this button does. Called by the pointer system on a release
  /// inside the button; a game may call it to press the button itself.
  void press(UiActionContext context) {
    if (!isInteractive) return;
    wasPressed = true;
    onPressed.run(context);
  }

  @override
  String toString() => 'Button("$label")';
}
