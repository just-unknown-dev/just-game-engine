// What Graphics3D registers into a context: its components, and the field
// type the 3-D material overrides are saved through; and that the engine's
// list of 3-D graphics types — the hint a scene gets without Graphics3D —
// names exactly those components.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

/// The types [register] adds to a context that has only the ECS core's.
Set<String> _typesAdded(void Function(EngineContext) register) {
  final context = EngineContext();
  addTearDown(context.dispose);
  final before = context.definitions.types.toSet();
  register(context);
  return context.definitions.types.toSet().difference(before);
}

void main() {
  test(
    "BuiltInComponents.graphics3DTypes is every type Graphics3D registers",
    () {
      const types = BuiltInComponents.graphics3DTypes;
      expect(types.toSet(), hasLength(types.length), reason: 'no repeats');
      expect(types.toSet(), _typesAdded(Graphics3D.registerDefinitions));
      expect(types, contains('MaterialOverrides3DComponent'));
    },
  );

  test('the engine tells a scene how to turn each of them on', () {
    final context = EngineContext(extensions: [BuiltInComponents.extension]);
    addTearDown(context.dispose);
    for (final type in BuiltInComponents.graphics3DTypes) {
      expect(
        context.definitions.unknownTypeHint(type),
        contains('EngineConfig(services: [Graphics3D()])'),
        reason: type,
      );
    }
  });

  test('it registers the 3-D material overrides field type', () {
    final bare = EngineContext(extensions: [BuiltInComponents.extension]);
    addTearDown(bare.dispose);
    const type = Material3DDefinitions.overridesType;
    expect(bare.fieldTypes.byId(type.id), isNull);

    final engine = Engine(config: EngineConfig(services: [Graphics3D()]));
    addTearDown(engine.dispose);
    expect(engine.context.fieldTypes.byId(type.id), same(type));
    final field = Material3DDefinitions.materialOverrides3D.fields.single;
    expect(field.kind, same(type));
    expect(type.channels, contains('tiling#1'));

    // Alone, for a tool that reads 3-D scenes without the engine's own.
    final tool = EngineContext();
    addTearDown(tool.dispose);
    Graphics3D.registerDefinitions(tool);
    expect(tool.fieldTypes.byId(type.id), same(type));
  });
}
