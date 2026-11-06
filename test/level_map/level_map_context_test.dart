// What level maps keep per engine: the collision kinds, with or without
// the engine's own.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('a context without the built-ins knows no collision kind, and still '
      'resolves one to solid', () {
    final bare = EngineContext(withBuiltIns: false);
    addTearDown(bare.dispose);
    expect(bare.collisionKinds.byId('solid'), isNull);
    expect(bare.collisionKinds.byId('oneWay'), isNull);
    expect(bare.collisionKinds.resolve('oneWay'), MapCollisionKinds.solid);

    final full = EngineContext();
    addTearDown(full.dispose);
    expect(full.collisionKinds.byId('solid'), MapCollisionKinds.solid);
    expect(full.collisionKinds.byId('oneWay'), MapCollisionKinds.oneWay);
  });

  test('each context has kinds of its own', () {
    final a = EngineContext(), b = EngineContext();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.collisionKinds.register(
      const MapCollisionKind(id: 'test.ice', label: 'Ice'),
    );
    expect(a.collisionKinds.byId('test.ice'), isNotNull);
    expect(b.collisionKinds.byId('test.ice'), isNull);
    expect(a.tiles.collisionKinds, same(a.collisionKinds));
  });
}
