/// Input ECS System
///
/// Copies each player's actions onto the entities they control.
library;

import 'package:just_inputs/just_inputs.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Reads each [InputComponent]'s player from the [InputService] and writes
/// every action of [maps] into it by its short name — `jump`, `move` — so
/// gameplay code reads names, not devices.
///
/// A component whose player is not playing is cleared: nothing held.
class InputSystem extends System {
  InputSystem(this.input, {this.maps = const ['player']});

  final InputService input;

  /// The maps whose actions are copied. Names must not repeat across them.
  final List<String> maps;

  @override
  int get priority => SystemPriorities.input;

  @override
  List<Type> get requiredComponents => [InputComponent];

  @override
  void update(double deltaTime) {
    for (final entity in entities) {
      final component = entity.getComponent<InputComponent>()!;
      final actions = component.playerIndex < 0
          ? input.actions
          : input.actionsFor(component.playerIndex);
      if (actions == null) {
        component.clear();
        continue;
      }
      _copy(actions, component);
    }
  }

  void _copy(InputActions actions, InputComponent into) {
    into
      ..pressed.clear()
      ..released.clear()
      ..performed.clear();
    for (final name in maps) {
      final map = actions.map(name);
      if (map == null) continue;
      for (final action in map.actions) {
        final key = action.name;
        switch (action.type) {
          case ActionValueType.vector2:
            into.vectors[key] = action.readVector2();
          case ActionValueType.axis || ActionValueType.button:
            into.axes[key] = action.readAxis();
        }
        into.down[key] = action.isPressed();
        if (action.wasPressedThisFrame()) into.pressed.add(key);
        if (action.wasReleasedThisFrame()) into.released.add(key);
        if (action.wasPerformedThisFrame()) into.performed.add(key);
      }
    }
  }
}
