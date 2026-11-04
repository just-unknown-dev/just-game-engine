/// The input components: input, and simple movement.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition.dart';
import '../ecs/serialization/field_definitions.dart';
import '../foundation/dimensions.dart';
import 'input_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'simple_movement_component.dart';

/// The input components: input, and simple movement.
abstract final class InputDefinitions {
  /// Definition of [InputComponent], saved as `InputComponent`: its
  /// `playerIndex` (-1 reads every device).
  static ComponentDefinition<InputComponent> get input =>
      ComponentDefinition<InputComponent>(
        type: 'InputComponent',
        hints: const ComponentHints(
          name: 'Input',
          group: 'Input',
          description: "A player's actions, by name, for this entity.",
          icon: Icons.keyboard,
          accentColor: Color(0xFFEF5350),
          fields: {
            'playerIndex': FieldHint(
              label: 'Player',
              description:
                  '0 is player 1. -1 reads every device, whoever is playing.',
            ),
          },
        ),
        create: InputComponent.new,
        fields: [
          FieldDefinitions.integer(
            'playerIndex',
            (c) => (c as InputComponent).playerIndex,
            (c, v) => (c as InputComponent).playerIndex = v,
          ),
        ],
      );

  /// Definition of [SimpleMovementComponent], saved as
  /// `SimpleMovementComponent`. 2-D only.
  static ComponentDefinition<SimpleMovementComponent> get simpleMovement =>
      ComponentDefinition<SimpleMovementComponent>(
        type: 'SimpleMovementComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Simple Movement',
          group: 'Input',
          description: 'Moves straight from a vector action, no physics.',
          icon: Icons.directions_run,
          accentColor: Color(0xFFEF5350),
          fieldGroups: {
            'Movement': ['speed', 'deadZone', 'normalizeDiagonal'],
            'Input': ['action', 'playerIndex'],
          },
          fields: {
            'speed': FieldHint(
              label: 'Speed',
              scrub: ScrubHint(step: 5, fractionDigits: 1),
            ),
            'deadZone': FieldHint(
              label: 'Dead Zone',
              scrub: ScrubHint(step: 0.01, fractionDigits: 2),
            ),
            'normalizeDiagonal': FieldHint(label: 'Normalize Diagonal'),
            'action': FieldHint(label: 'Action'),
            'playerIndex': FieldHint(
              label: 'Player',
              description: '0 is player 1. -1 reads every device.',
            ),
          },
        ),
        create: SimpleMovementComponent.new,
        fields: [
          FieldDefinitions.decimal(
            'speed',
            (c) => (c as SimpleMovementComponent).speed,
            (c, v) => (c as SimpleMovementComponent).speed = v,
            min: 0,
          ),
          FieldDefinitions.text(
            'action',
            (c) => (c as SimpleMovementComponent).action,
            (c, v) => (c as SimpleMovementComponent).action = v,
          ),
          FieldDefinitions.integer(
            'playerIndex',
            (c) => (c as SimpleMovementComponent).playerIndex,
            (c, v) => (c as SimpleMovementComponent).playerIndex = v,
          ),
          FieldDefinitions.boolean(
            'normalizeDiagonal',
            (c) => (c as SimpleMovementComponent).normalizeDiagonal,
            (c, v) => (c as SimpleMovementComponent).normalizeDiagonal = v,
          ),
          FieldDefinitions.decimal(
            'deadZone',
            (c) => (c as SimpleMovementComponent).deadZone,
            (c, v) => (c as SimpleMovementComponent).deadZone = v,
            min: 0,
            max: 1,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [input, simpleMovement];
}
