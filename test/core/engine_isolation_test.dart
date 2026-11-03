// Nothing one world, engine, player or camera brain does leaks into another.

import 'package:flutter/painting.dart';
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

  group('camera impulses', () {
    Offset shakeOf(CameraBrain brain) {
      brain.emitImpulse(
        CameraImpulse(position: Offset.zero, amplitude: 20, duration: 1),
      );
      brain.impulses.update(0.1);
      return brain.impulses.feltAt(Offset.zero);
    }

    test('after brain.reset() impulses replay identically', () {
      final brain = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      final first = shakeOf(brain);
      final second = shakeOf(brain); // A second impulse on top: different.
      expect(second, isNot(first));

      brain.reset();
      expect(shakeOf(brain), first);
    });

    test('two brains shake the same way for the same impulses', () {
      final a = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      final b = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      shakeOf(a);
      shakeOf(a);
      // b has seen nothing yet; its first impulse is a's first, not its third.
      final fresh = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      expect(shakeOf(b), shakeOf(fresh));
    });
  });

  group('effects', () {
    test('handle ids count per player, from 1', () {
      final a = EffectPlayer();
      final b = EffectPlayer();
      final a1 = a.add(DelayEffect(durationTicks: 5), 0);
      final a2 = a.add(DelayEffect(durationTicks: 5), 0);
      final b1 = b.add(DelayEffect(durationTicks: 5), 0);
      expect([a1.id, a2.id, b1.id], [1, 2, 1]);
    });

    test("cancelling another player's handle with the same id is harmless", () {
      final a = EffectPlayer();
      final b = EffectPlayer();
      a.add(DelayEffect(durationTicks: 5), 0);
      final fromB = b.add(DelayEffect(durationTicks: 5), 0);
      a.cancel(fromB);
      expect(a.activeCount, 1);
    });
  });

  group('SystemManager', () {
    test('unregisterSystem by name removes the typed entry', () {
      final manager = SystemManager();
      final parallax = ParallaxSystem();
      manager.registerSystem('parallax', parallax);
      expect(manager.getSystem<ParallaxSystem>(), same(parallax));

      expect(manager.unregisterSystem('parallax'), isTrue);
      expect(manager.getSystem<ParallaxSystem>(), isNull);
      expect(manager.hasSystemOfType<ParallaxSystem>(), isFalse);
    });

    test('a system is keyed by its declared type', () {
      final manager = SystemManager();
      final custom = _CustomParallax();
      manager.registerSystem<ParallaxSystem>('parallax', custom);
      expect(manager.getSystem<ParallaxSystem>(), same(custom));
      expect(manager.getSystem<_CustomParallax>(), isNull);

      manager.unregisterSystem('parallax');
      expect(manager.getSystem<ParallaxSystem>(), isNull);
    });

    test('unregistering a name leaves a newer typed entry alone', () {
      final manager = SystemManager();
      final first = ParallaxSystem();
      final second = ParallaxSystem();
      manager
        ..registerSystem('a', first)
        ..registerSystem('b', second); // Takes over the typed entry.
      manager.unregisterSystem('a');
      expect(manager.getSystem<ParallaxSystem>(), same(second));
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

class _CustomParallax extends ParallaxSystem {}
