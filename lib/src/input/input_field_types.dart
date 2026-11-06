/// The input field types: the name of an input action, and several.
/// Registered with the input definitions ([InputDefinitions.fieldTypes]),
/// not by the ECS core.
library;

import '../ecs/serialization/field_type.dart';
import 'input_definitions.dart';

/// The name of an input action — `jump`, or `player/jump` — as a component
/// that reads the player's input saves it. Stored as text, exactly as a
/// [FieldTypes.text] field is: only the kind says what the text names.
///
/// What the kind is for: the editor offers the project's actions for such a
/// field, and the Input Actions editor finds it when an action is renamed,
/// moved or deleted. A field holding text that merely looks like an action
/// (a timeline trigger's `enterAction`) is not of this kind, and is left
/// alone.
class InputActionFieldType extends FieldType<String> {
  /// Const constructor; the shared instance is [InputDefinitions.actionType].
  const InputActionFieldType();

  @override
  String get id => 'inputAction';

  @override
  Object? encode(String value) => value;

  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// Several input actions' names, saved as a list of text. Read back as a
/// `List<String>`; a list holding anything but text is returned as it is,
/// so a hand-edited mistake surfaces rather than losing entries.
class InputActionListFieldType extends FieldType<List<String>> {
  /// Const constructor; the shared instance is
  /// [InputDefinitions.actionListType].
  const InputActionListFieldType();

  @override
  String get id => 'inputActionList';

  @override
  Object? encode(List<String> value) => [...value];

  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is List && json.every((v) => v is String)
      ? List<String>.of(json.cast<String>())
      : json;
}
