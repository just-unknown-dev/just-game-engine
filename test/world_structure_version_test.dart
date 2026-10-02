import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('structureVersion moves on every structural change, not on reads', () {
    final world = World();
    var seen = world.structureVersion;
    int changed() {
      final now = world.structureVersion;
      final moved = now != seen ? 1 : 0;
      seen = now;
      return moved;
    }

    final entity = world.createEntity(name: 'a');
    expect(changed(), 1, reason: 'create');
    entity.addComponent(TransformComponent());
    expect(changed(), 1, reason: 'add component');
    world.query([TransformComponent]);
    expect(changed(), 0, reason: 'a query is not a change');
    entity.removeComponent<TransformComponent>();
    expect(changed(), 1, reason: 'remove component');
    world.destroyEntity(entity);
    expect(changed(), 1, reason: 'destroy');
  });
}
