// Nothing one engine's effects do leaks into another's.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
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
}
