import 'package:flutter/painting.dart';
import '../../ecs.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../components/components.dart';
import '../system_priorities.dart';

/// Applies directional input directly to [TransformComponent].
class SimpleMovementSystem extends System {
  SimpleMovementSystem(this.inputManager);

  final InputManager inputManager;

  @override
  int get priority => SystemPriorities.movement + 1;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    SimpleMovementComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final movement = entity.getComponent<SimpleMovementComponent>()!;

      var direction = Offset.zero;

      if (movement.useKeyboard) {
        direction = Offset(
          inputManager.keyboard.horizontal,
          inputManager.keyboard.vertical,
        );
      }

      if (movement.useJoystick) {
        final joystick = entity.getComponent<JoystickInputComponent>();
        final joystickDirection = joystick?.direction ?? Offset.zero;
        if (joystickDirection.distance > movement.deadZone) {
          // Prefer active joystick direction when one is attached.
          direction = joystickDirection;
        }
      }

      if (direction.distance <= movement.deadZone) {
        movement.lastDirection = Offset.zero;
        return;
      }

      if (movement.normalizeDiagonal && direction.distance > 1.0) {
        direction = direction / direction.distance;
      }

      movement.lastDirection = direction;
      transform.translateXY(
        direction.dx * movement.speed * deltaTime,
        direction.dy * movement.speed * deltaTime,
      );
    });
  }
}
