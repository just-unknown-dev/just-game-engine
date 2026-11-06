// The input action field kinds: an input action's name and a list of them.
// Metadata only: a field of either kind saves exactly what a text field (or
// a list of text) would, and only the kind tells the editor what it names.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The engine's own definitions, fresh for this file.
final _definitions = BuiltInComponents.registry();

void main() {
  group('InputActionFieldType', () {
    const type = InputDefinitions.actionType;

    test('saves the name as text, and reads it back as it is', () {
      expect(type.id, 'inputAction');
      expect(type.encodeAny('jump'), 'jump');
      expect(
        type.decodeAny('player/jump', FieldConstraints.none),
        'player/jump',
      );
      expect(type.decodeAny(null, FieldConstraints.none), isNull);
      expect(
        type.decodeAny(3, FieldConstraints.none),
        3,
        reason: 'a wrong shape surfaces as it is',
      );
    });
  });

  group('InputActionListFieldType', () {
    const type = InputDefinitions.actionListType;

    test('saves the names as a list of text, and reads a list back', () {
      expect(type.id, 'inputActionList');
      final encoded = type.encodeAny(['jump', 'player/move']);
      expect(encoded, ['jump', 'player/move']);
      final decoded = type.decodeAny(['jump', 'move'], FieldConstraints.none);
      expect(decoded, isA<List<String>>());
      expect(decoded, ['jump', 'move']);
    });

    test('a list with anything but text in it is returned as it is', () {
      final odd = ['jump', 3];
      expect(type.decodeAny(odd, FieldConstraints.none), same(odd));
      expect(type.decodeAny('jump', FieldConstraints.none), 'jump');
    });
  });

  test('isActionKind: the two input action kinds, by id, and nothing else', () {
    expect(InputDefinitions.isActionKind(InputDefinitions.actionType), isTrue);
    expect(
      InputDefinitions.isActionKind(InputDefinitions.actionListType),
      isTrue,
    );
    expect(InputDefinitions.isActionKind(const _ReplacedActionType()), isTrue);
    expect(InputDefinitions.isActionKind(FieldTypes.text), isFalse);
    expect(InputDefinitions.isActionKind(FieldTypes.tagList), isFalse);
  });

  test('BuiltInComponents registers them; a bare context has neither', () {
    final context = EngineContext(extensions: [BuiltInComponents.extension]);
    addTearDown(context.dispose);
    for (final type in InputDefinitions.fieldTypes) {
      expect(context.fieldTypes.byId(type.id), same(type));
    }
    final bare = EngineContext();
    addTearDown(bare.dispose);
    expect(bare.fieldTypes.byId(InputDefinitions.actionType.id), isNull);
  });

  group('the engine marks its input action fields', () {
    test("SimpleMovementComponent's action is an input action", () {
      final field = _definitions
          .definitionByType('SimpleMovementComponent')!
          .fields
          .singleWhere((f) => f.name == 'action');
      expect(field.kind, same(InputDefinitions.actionType));
    });

    test(
      "a timeline trigger's enterAction and exitAction are not input actions",
      () {
        final fields = _definitions
            .definitionByType('TimelineTriggerComponent')!
            .fields;
        for (final name in ['enterAction', 'exitAction']) {
          final field = fields.singleWhere((f) => f.name == name);
          expect(
            InputDefinitions.isActionKind(field.kind),
            isFalse,
            reason: '$name says what the timeline does',
          );
        }
      },
    );

    test('no built-in text field is named like an action', () {
      // A field named `action`, `actions` or `…Action` holds an input
      // action's name unless its kind says otherwise (an enum, as the
      // timeline trigger's): one left as text is one the editor can neither
      // offer the actions for nor find on a rename.
      final unmarked = [
        for (final definition in _definitions.definitions)
          for (final field in definition.fields)
            if (_namedLikeAnAction(field.name) &&
                (field.kind.id == FieldTypes.text.id ||
                    field.kind.id == FieldTypes.list.id))
              '${definition.type}.${field.name}',
      ];
      expect(unmarked, isEmpty);
    });
  });

  test('a scene saves the same JSON as before: the kind is not saved', () {
    // What dev.4 saved for simple movement, before the field had a kind.
    final saved = {
      'type': 'SimpleMovementComponent',
      'fields': {
        'speed': 180.0,
        'action': 'walk',
        'playerIndex': 1,
        'normalizeDiagonal': false,
        'deadZone': 0.2,
      },
    };
    final component =
        _definitions.decode(
              jsonDecode(jsonEncode(saved)) as Map<String, dynamic>,
            )!
            as SimpleMovementComponent;
    expect(component.action, 'walk');
    expect(jsonEncode(_definitions.encode(component)), jsonEncode(saved));
  });
}

bool _namedLikeAnAction(String name) =>
    name == 'action' || name == 'actions' || name.endsWith('Action');

/// A project's own type registered in place of the built-in one, under the
/// same id.
class _ReplacedActionType extends FieldType<String> {
  const _ReplacedActionType();

  @override
  String get id => InputDefinitions.actionType.id;

  @override
  Object? encode(String value) => value;

  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}
