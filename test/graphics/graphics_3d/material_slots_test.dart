// MaterialSlots: where painting a material on, and picking one up, put and
// read it — a shape's own material, else a model's `*` slot; nothing for an
// entity that draws neither.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

const _red = 'assets/materials/red.material.json';

void main() {
  late World world;
  setUp(() => world = World()..initialize());
  tearDown(() => world.dispose());

  test('a shape holds its material itself', () {
    final cube = Cube3DComponent();
    final entity = world.createEntityWithComponents([cube]);
    expect(MaterialSlots.holderOf(entity), same(cube));
    expect(MaterialSlots.materialOf(entity), '');
    expect(MaterialSlots.assign(entity, _red), isTrue);
    expect((cube.material, MaterialSlots.materialOf(entity)), (_red, _red));
    expect(MaterialSlots.assign(entity, ''), isTrue);
    expect(cube.material, '', reason: 'its own look again');
  });

  test('a shape wins over a model on the same entity', () {
    final model = ModelComponent(model: 'assets/models/crate.glb');
    final entity = world.createEntityWithComponents([
      model,
      Sphere3DComponent(),
    ]);
    expect(MaterialSlots.holderOf(entity), isA<Sphere3DComponent>());
    MaterialSlots.assign(entity, _red);
    expect(model.materials, isEmpty);
  });

  test(
    'a model takes it for every one of its materials, and lets go of it',
    () {
      final model = ModelComponent(
        model: 'assets/models/crate.glb',
        materials: {'Wood': 'wood.material.json'},
      );
      final entity = world.createEntityWithComponents([model]);
      expect(MaterialSlots.holderOf(entity), same(model));
      expect(
        MaterialSlots.materialOf(entity),
        '',
        reason: 'only the * slot counts',
      );
      expect(MaterialSlots.assign(entity, _red), isTrue);
      expect(model.materials, {'*': _red}, reason: 'in place of any it had');
      expect(MaterialSlots.materialOf(entity), _red);
      expect(MaterialSlots.assign(entity, ''), isTrue);
      expect(model.materials, isEmpty, reason: 'not a "*" slot left empty');
    },
  );

  test('an entity that draws neither has nowhere to put one', () {
    final entity = world.createEntityWithComponents([TransformComponent()]);
    expect(MaterialSlots.holderOf(entity), isNull);
    expect(MaterialSlots.materialOf(entity), '');
    expect(MaterialSlots.assign(entity, _red), isFalse);
  });
}
