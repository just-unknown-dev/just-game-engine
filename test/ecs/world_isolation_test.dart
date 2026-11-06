// Nothing one world does leaks into another: tag lookups, and the systems
// it holds.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Probe extends System {
  _Probe(this.calls);
  final List<String> calls;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void onRemovedFromWorld() => calls.add('removed');

  @override
  void dispose() => calls.add('disposed');
}

class _Other extends System {
  @override
  List<Type> get requiredComponents => const [];
}

void main() {
  group('tags', () {
    test("two worlds' tag indexes are independent", () {
      final a = World();
      final b = World();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final inA = a.createEntityWithComponents([TagComponent('player')]);
      expect(a.allTagged('player'), [inA]);
      expect(b.allTagged('player'), isEmpty);

      // A change in one world leaves the other's cached answer alone.
      final cachedB = b.allTagged('enemy');
      inA.addTag('enemy');
      expect(a.allTagged('enemy'), [inA]);
      expect(identical(b.allTagged('enemy'), cachedB), isTrue);
      expect(b.tagsInUse, isEmpty);
    });
  });

  group('World', () {
    test('hasSystem finds a system by type', () {
      final world = World();
      addTearDown(world.dispose);
      expect(world.hasSystem<_Other>(), isFalse);
      world.addSystem(_Other());
      expect(world.hasSystem<_Other>(), isTrue);
      expect(world.hasSystem<_Probe>(), isFalse);
    });

    test('dispose tells each system it was removed, then disposes it', () {
      final calls = <String>[];
      final world = World()..addSystem(_Probe(calls));
      world.dispose();
      expect(calls, ['removed', 'disposed']);
      expect(world.systems, isEmpty);
    });
  });
}
