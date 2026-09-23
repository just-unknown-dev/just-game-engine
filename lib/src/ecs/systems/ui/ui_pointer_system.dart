/// Pressing the UI that lives in the world.
///
/// World-space buttons were drawn but never pressed: nothing hit-tested
/// them, and what they did was a closure no scene could hold. This turns a
/// pointer into hover, press and release, and a release inside a button
/// into its [UiActionList].
library;

import 'package:flutter/painting.dart';

import '../../../subsystems/ui/ui_actions.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

/// Where the pointer is, in world units, and whether it is down.
///
/// The engine's input is screen-space and per-platform; whoever owns the
/// camera converts and hands the result here, which keeps this system
/// testable without a window.
class UiPointer {
  const UiPointer({this.position, this.isDown = false});

  static const UiPointer away = UiPointer();

  /// Null when the pointer is off the game — a touch that has lifted, a
  /// mouse outside the window.
  final Offset? position;
  final bool isDown;
}

class UiPointerSystem extends System {
  UiPointerSystem({this.onSound});

  /// Plays a UI sound by path — hover and press, from the theme.
  final void Function(String path)? onSound;

  /// Where the pointer is now. Set each frame by the game or the editor.
  UiPointer pointer = UiPointer.away;

  /// Sounds to make when a button is first hovered or pressed.
  String hoverSound = '';
  String pressSound = '';

  /// The button being held, so a release only counts on the one it began
  /// on — dragging off a button and letting go must not press it.
  Entity? _pressing;
  Entity? _hovering;
  bool _wasDown = false;

  // After gameplay, before rendering: a press this frame shows this frame.
  @override
  int get priority => SystemPriorities.gameplay - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, ButtonComponent];

  /// The button under [point], topmost first — a button on a higher layer
  /// takes the press.
  Entity? buttonAt(Offset point) {
    Entity? best;
    var bestLayer = -1 << 30;
    forEach((entity) {
      final button = entity.getComponent<ButtonComponent>()!;
      if (!button.isInteractive) return;
      final at = entity.getComponent<TransformComponent>()!.position;
      final centre = Offset(at.x, at.y);
      if (!button.containsPoint(point, centre)) return;
      if (button.layer >= bestLayer) {
        bestLayer = button.layer;
        best = entity;
      }
    });
    return best;
  }

  @override
  void update(double deltaTime) {
    // Every button starts the frame as it will stay unless the pointer says
    // otherwise, so a button left behind by a pointer does not stick.
    forEach((entity) {
      final button = entity.getComponent<ButtonComponent>()!;
      button.wasPressed = false;
      if (!button.isInteractive) {
        button.state = UiInteractionState.disabled;
      } else if (button.state == UiInteractionState.disabled) {
        button.state = UiInteractionState.normal;
      }
    });

    final at = pointer.position;
    final live = entities.toSet();
    if (!live.contains(_pressing)) _pressing = null;
    if (!live.contains(_hovering)) _hovering = null;

    if (at == null) {
      _clear(_hovering);
      _clear(_pressing);
      _hovering = null;
      _pressing = null;
      _wasDown = pointer.isDown;
      return;
    }

    final under = buttonAt(at);
    if (!identical(under, _hovering)) {
      _clear(_hovering);
      _hovering = under;
      if (under != null && !pointer.isDown && hoverSound.isNotEmpty) {
        onSound?.call(hoverSound);
      }
    }

    final pressedThisFrame = pointer.isDown && !_wasDown;
    final releasedThisFrame = !pointer.isDown && _wasDown;
    _wasDown = pointer.isDown;

    if (pressedThisFrame && under != null) {
      _pressing = under;
      if (pressSound.isNotEmpty) onSound?.call(pressSound);
    }

    if (releasedThisFrame) {
      final held = _pressing;
      _pressing = null;
      // Only a release on the button it began on counts.
      if (held != null && identical(held, under)) {
        held.getComponent<ButtonComponent>()?.press(
          UiActionContext(world: world, entity: held),
        );
      }
    }

    // What each button shows: pressed beats hovered.
    final held = _pressing;
    if (held != null) {
      final button = held.getComponent<ButtonComponent>();
      if (button != null && button.isInteractive) {
        button.state = identical(held, under)
            ? UiInteractionState.pressed
            : UiInteractionState.normal;
      }
    }
    if (under != null && !identical(under, held)) {
      final button = under.getComponent<ButtonComponent>();
      if (button != null && button.isInteractive) {
        button.state = pointer.isDown && held != null
            ? UiInteractionState.normal
            : UiInteractionState.hovered;
      }
    }
  }

  void _clear(Entity? entity) {
    final button = entity?.getComponent<ButtonComponent>();
    if (button != null && button.isInteractive) {
      button.state = UiInteractionState.normal;
    }
  }
}
