/// The input components: input, and simple movement.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition.dart';
import '../ecs/serialization/field_definitions.dart';
import '../ecs/serialization/field_type.dart';
import '../foundation/dimensions.dart';
import 'input_component.dart';
import 'input_field_types.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'simple_movement_component.dart';

/// The input components: input, and simple movement; and the input field
/// types, an input action's name ([actionType]) and several
/// ([actionListType]).
abstract final class InputDefinitions {
  /// The name of an input action, saved as text; the editor offers the
  /// project's actions. [SimpleMovementComponent.action] is one; a kit's or
  /// a game's own action fields use it too.
  static const InputActionFieldType actionType = InputActionFieldType();

  /// Several input actions' names, saved as a list of text.
  static const InputActionListFieldType actionListType =
      InputActionListFieldType();

  /// The input field types, registered into a context with the engine's
  /// definitions (`BuiltInComponents.extension`).
  static const List<FieldType> fieldTypes = [actionType, actionListType];

  /// Whether a field of [kind] holds input actions' names: one
  /// ([actionType]) or several ([actionListType]). Read by id, as the
  /// editor finds a field's control, so a type a project registers in
  /// place of one of them counts too.
  static bool isActionKind(FieldType kind) =>
      kind.id == actionType.id || kind.id == actionListType.id;

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
          FieldDefinition(
            name: 'action',
            kind: actionType,
            read: (c) => (c as SimpleMovementComponent).action,
            write: (c, v) =>
                (c as SimpleMovementComponent).action = v as String,
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
