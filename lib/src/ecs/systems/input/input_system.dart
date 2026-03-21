/// Input ECS System
///
/// Bridges the subsystem [InputManager] into ECS [InputComponent] and
/// [JoystickInputComponent] entities each frame.
library;

import 'package:flutter/services.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../subsystems/input/input_management.dart';
import '../system_priorities.dart';

/// Maps for translating [InputComponent.buttons] string keys to keyboard keys.
///
/// Games register their own mappings. The defaults cover common WASD / arrows
/// plus common action keys.
typedef ButtonMapping = Map<String, LogicalKeyboardKey>;

/// System that reads [InputManager] state and writes it into ECS components.
///
/// Processes two component types:
/// - [InputComponent]: Copies keyboard axes and mapped button states.
/// - [JoystickInputComponent]: Optionally updates virtual-joystick direction
///   from touch / pointer state reported by [InputManager.touch].
///
/// Requires an external [InputManager] reference passed at construction:
/// ```dart
/// world.addSystem(InputSystem(engine.input));
/// ```
class InputSystem extends System {
  /// Reference to the subsystem input manager.
  final InputManager inputManager;

  /// Optional button name → keyboard key mapping.
  ///
  /// Entries are checked each frame and written into
  /// [InputComponent.buttons]. Example:
  /// ```dart
  /// inputSystem.buttonMappings = {
  ///   'jump': LogicalKeyboardKey.space,
  ///   'fire': LogicalKeyboardKey.keyF,
  /// };
  /// ```
  ButtonMapping buttonMappings = {};

  /// Create the input system with a subsystem [InputManager].
  InputSystem(this.inputManager);

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
    final kb = inputManager.keyboard;
    final h = kb.horizontal;
    final v = kb.vertical;
    final dir = Offset(h, v);

    for (final entity in entities) {
      final input = entity.getComponent<InputComponent>()!;
      input.moveDirection = dir;

      // Write mapped button states.
      for (final entry in buttonMappings.entries) {
        input.buttons[entry.key] = kb.isKeyDown(entry.value);
      }
    }
  }

  // ── JoystickInputComponent ────────────────────────────────────────────

  void _updateJoystickComponents() {
    final joystickEntities = world.query([JoystickInputComponent]);
    if (joystickEntities.isEmpty) return;

    final touches = inputManager.touch;
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
