import 'package:flutter/painting.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';

/// Applies a vector action straight to [TransformComponent].
class SimpleMovementSystem extends System {
  /// A system steering by the actions in [input].
  SimpleMovementSystem(this.input);

  /// Where each [SimpleMovementComponent]'s vector action is read from.
  final InputService input;

  @override
  int get priority => SystemPriorities.movement + 1;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    SimpleMovementComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final movement = entity.getComponent<SimpleMovementComponent>()!;

      final actions = movement.playerIndex < 0
          ? input.actions
          : input.actionsFor(movement.playerIndex);
      var direction =
          actions?.tryAction(movement.action)?.readVector2() ?? Offset.zero;

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
