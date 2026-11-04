// Scene format 11 with 3-D graphics and physics installed: every type the
// v10 → v11 step renames to is a definition the engine has — a renamed
// definition, or a typo in the table, would load as an unknown component.
@Tags(['graphics3d', 'physics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show V10ToV11;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every rename target resolves', () {
    final engine = Engine(
      config: EngineConfig(services: [Graphics3D(), Physics3D()]),
    );
    addTearDown(engine.dispose);
    final defs = engine.context.definitions;
    expect([
      for (final MapEntry(key: old, value: renamed) in V10ToV11.renames.entries)
        if (defs.byName(renamed) == null) '$old → $renamed',
    ], isEmpty);
  });

  test('a v10 scene with 3-D types loads them renamed', () {
    final engine = Engine(
      config: EngineConfig(services: [Graphics3D(), Physics3D()]),
    );
    addTearDown(engine.dispose);
    final world = World(context: engine.context);
    addTearDown(world.dispose);
    final made = SceneLoader.load(world, {
      'version': 10,
      'entities': [
        {
          'name': 'Lamp',
          'components': [
            {'type': 'TransformComponent', 'fields': <String, dynamic>{}},
            {'type': 'LightComponent', 'fields': <String, dynamic>{}},
            {'type': 'Cube3D', 'fields': <String, dynamic>{}},
            {'type': 'RigidBody3D', 'fields': <String, dynamic>{}},
          ],
        },
      ],
    });
    final lamp = made.single;
    expect(lamp.hasComponent<Light3DComponent>(), isTrue);
    // 3-D shapes are filed as the entity's Primitive3DComponent.
    expect(lamp.getComponent<Primitive3DComponent>(), isA<Cube3DComponent>());
    expect(lamp.hasComponent<RigidBody3DComponent>(), isTrue);
  });
}
