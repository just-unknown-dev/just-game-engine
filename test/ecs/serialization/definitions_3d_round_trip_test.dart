// The 3-D half of definitions_round_trip_test.dart: every component
// Graphics3D and Physics3D install saves and loads every field it writes.
// For each of their definitions and each field a codec reads back, a value
// changed within the field's limits is written, read and written again
// unchanged; and each type's default round-trips whole.
@Tags(['graphics3d', 'physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

import 'definitions_round_trip.dart';

/// Fields whose saved value is not what was written, on purpose — each
/// with why. A field listed here is still decoded by the whole-component
/// round trip below.
const Map<String, String> _notRoundTripped = {};

void main() {
  final context = EngineContext(extensions: [BuiltInComponents.extension]);
  final defs = context.definitions;
  final engineTypes = defs.types.toSet();
  Graphics3D.registerDefinitions(context);
  Physics3D.registerDefinitions(context);
  final added = [
    for (final definition in defs.definitions)
      if (!engineTypes.contains(definition.type)) definition,
  ];
  tearDownAll(context.dispose);

  test('Graphics3D and Physics3D installed all their types', () {
    expect(added.map((d) => d.type).toSet(), {
      ...BuiltInComponents.graphics3DTypes,
      ...BuiltInComponents.physics3DTypes,
    });
  });

  var checked = 0;
  group('every field of every 3-D definition round-trips', () {
    for (final definition in added) {
      test(definition.type, () {
        checked += expectFieldsRoundTrip(definition, exempt: _notRoundTripped);
      });
    }

    test('(and that is most of them)', () {
      expect(checked, greaterThan(250), reason: 'the check checked little');
    });
  });

  test('every 3-D type saved at its defaults reads back the same', () {
    expectDefaultsRoundTrip(defs, added);
  });
}
