// What Physics3D registers into a context: its components, and the layer
// field types they share with 2-D physics — present even where the engine's
// own definitions are not; and that the engine's list of 3-D physics
// types — the hint a scene gets without Physics3D — names exactly those
// components.
@Tags(['physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

void main() {
  test(
    'BuiltInComponents.physics3DTypes is every type Physics3D registers',
    () {
      final context = EngineContext();
      addTearDown(context.dispose);
      final before = context.definitions.types.toSet();
      Physics3D.registerDefinitions(context);
      final added = context.definitions.types.toSet().difference(before);

      const types = BuiltInComponents.physics3DTypes;
      expect(types.toSet(), hasLength(types.length), reason: 'no repeats');
      expect(types.toSet(), added);
    },
  );

  test('the engine tells a scene how to turn each of them on', () {
    final context = EngineContext(extensions: [BuiltInComponents.extension]);
    addTearDown(context.dispose);
    for (final type in BuiltInComponents.physics3DTypes) {
      expect(
        context.definitions.unknownTypeHint(type),
        contains('EngineConfig(services: [Physics3D()])'),
        reason: type,
      );
    }
  });

  test('it registers the layer field types, without the engine too', () {
    final tool = EngineContext();
    addTearDown(tool.dispose);
    expect(tool.fieldTypes.byId(PhysicsDefinitions.layerType.id), isNull);
    Physics3D.registerDefinitions(tool);
    for (final type in Physics3DDefinitions.fieldTypes) {
      expect(tool.fieldTypes.byId(type.id), same(type));
    }
    expect(
      tool.fieldTypes.byId(PhysicsDefinitions.shapeType.id),
      isNull,
      reason: 'a 2-D shape: the engine brings it',
    );
    // Every layer field of a 3-D component is of a registered type.
    for (final definition in Physics3DDefinitions.all) {
      for (final field in definition.fields) {
        if (!field.kind.id.startsWith('physicsLayer')) continue;
        expect(tool.fieldTypes.byId(field.kind.id), same(field.kind));
      }
    }
  });

  test('with the engine as well, it registers nothing twice', () {
    final engine = Engine(config: EngineConfig(services: [Physics3D()]));
    addTearDown(engine.dispose);
    expect(
      engine.context.fieldTypes.byId(PhysicsDefinitions.layerMaskType.id),
      same(PhysicsDefinitions.layerMaskType),
    );
    engine.context.refreshDefinitions();
    expect(
      engine.context.fieldTypes.byId(PhysicsDefinitions.layerType.id),
      same(PhysicsDefinitions.layerType),
    );
  });
}
