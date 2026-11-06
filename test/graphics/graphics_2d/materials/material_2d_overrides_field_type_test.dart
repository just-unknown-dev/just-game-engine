// The 2-D material overrides field type: the numbers a timeline can key,
// and that the 2-D materials register it with their definitions — the ECS
// core knows nothing of materials.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  const type = Material2DDefinitions.overridesType;

  test('its channels are every number of every effect, a pair as two', () {
    final expected = <String>[
      for (final effect in Material2DEffects.all)
        for (final p in effect.params)
          if (p.type == Material2DValue.number)
            '${effect.id}.${p.name}'
          else if (p.type == Material2DValue.pair) ...[
            '${effect.id}.${p.name}#0',
            '${effect.id}.${p.name}#1',
          ],
    ];
    expect(type.channels, expected);
    expect(type.channels, isNot(contains('flash.color')));
    expect(identical(type.channels, type.channels), isTrue);
    expect(() => type.channels.add('x'), throwsUnsupportedError);
  });

  test('both 2-D material components save their overrides through it', () {
    final kinds = [
      for (final d in Material2DDefinitions.all)
        for (final f in (d as ComponentDefinition).fields)
          if (f.name == 'overrides') f.kind,
    ];
    expect(kinds, [same(type), same(type)]);
  });

  test('a bare world does not know it; the engine registers it', () {
    final bare = World();
    addTearDown(bare.dispose);
    expect(bare.context.fieldTypes.byId(type.id), isNull);
    expect(bare.context.fieldTypes.byId('material3DOverrides'), isNull);

    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.context.fieldTypes.byId(type.id), same(type));
    expect(
      engine.context.fieldTypes.byId('material3DOverrides'),
      isNull,
      reason: '3-D materials come with Graphics3D',
    );
  });
}
