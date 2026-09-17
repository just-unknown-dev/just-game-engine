/// Input ECS System
///
/// Bridges the named-action [InputActionResolver] into ECS [InputComponent]
/// and [JoystickInputComponent] entities each frame.
library;

import '../../ecs.dart';
import '../../components/components.dart';
import 'package:just_inputs/just_inputs.dart';
import '../system_priorities.dart';

/// System that reads [InputActionResolver] state and writes it into ECS
/// components.
///
/// Processes two component types:
/// - [InputComponent]: Copies the resolver's movement axes and every
///   currently-bound action's down-state.
/// - [JoystickInputComponent]: Optionally updates virtual-joystick direction
///   from touch / pointer state reported by [InputManager.touch].
///
/// Requires an external [InputActionResolver] reference passed at
/// construction:
/// ```dart
/// world.addSystem(InputSystem(engine.actions));
/// ```
class InputSystem extends System {
  /// Reference to the named-action resolver.
  final InputActionResolver actions;

  /// Create the input system with an [InputActionResolver].
  InputSystem(this.actions);

  @override
  int get priority => SystemPriorities.input;

  @override
  List<Type> get requiredComponents => [InputComponent];

  @override
  void update(double deltaTime) {
    _updateInputComponents();
    _updateJoystickComponents();
  }

  // ── InputComponent ────────────────────────────────────────────────────

  void _updateInputComponents() {
    final dir = actions.getVector2('move');

    for (final entity in entities) {
      final input = entity.getComponent<InputComponent>()!;
      input.moveDirection = dir;

      // Write every currently-bound button action's down-state (vector2
      // actions like 'move' have no single down/up state to report here).
      for (final entry in actions.actionSet.defs.entries) {
        if (entry.value.type != ActionType.button) continue;
        input.buttons[entry.key] = actions.isActionDown(entry.key);
      }
    }
  }

  // ── JoystickInputComponent ────────────────────────────────────────────

  void _updateJoystickComponents() {
    final joystickEntities = world.query([JoystickInputComponent]);
    if (joystickEntities.isEmpty) return;

    final touches = actions.inputManager.touch;
    for (final entity in joystickEntities) {
      final joy = entity.getComponent<JoystickInputComponent>()!;

      // If the joystick is actively tracking a pointer, update from touch.
      if (joy.isActive && joy.pointerId != null) {
        final touchPoint = touches.getTouch(joy.pointerId!);
        if (touchPoint != null) {
          joy.thumbPosition = touchPoint.position;
          joy.setDirectionFromDelta(touchPoint.position - joy.basePosition);
        } else {
          // Pointer lifted — reset.
          joy.reset();
        }
      }
    }
  }
}
