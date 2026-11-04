// Effects fixes from the 2.0.0 final pass: a shake ends where it started
// (F37). (The particle-force clock and ray fixes are in
// particles/particle_force_clock_test.dart and rendering/ray_renderable_test.dart.)

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('ShakeEffect', () {
    late World world;

    setUp(() => world = World()..initialize());
    tearDown(() => world.dispose());

    Vector3 shake(ShakeEffect effect, {int ticks = 0}) {
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 20, 0)),
      ]);
      final run = ticks == 0 ? effect.durationTicks : ticks;
      for (var t = 0; t < run; t++) {
        final tick = t % effect.durationTicks;
        effect.applyTick(
          EffectContext(entity: entity, currentTick: t + 1),
          tick,
          tick + 1,
        );
      }
      return entity.getComponent<TransformComponent>()!.position;
    }

    test('ends exactly where it started', () {
      final end = shake(
        ShakeEffect(amplitude: 8, frequency: 3, durationTicks: 20),
      );
      expect(end.x, closeTo(10, 1e-9));
      expect(end.y, closeTo(20, 1e-9), reason: 'used to end 8 units up');
    });

    test('moves while it runs', () {
      final mid = shake(
        ShakeEffect(amplitude: 8, frequency: 3, durationTicks: 20),
        ticks: 3,
      );
      expect((mid.x - 10).abs() + (mid.y - 20).abs(), greaterThan(0.1));
    });

    test('a looping shake does not drift', () {
      final end = shake(
        ShakeEffect(amplitude: 5, frequency: 2, durationTicks: 10, loop: true),
        ticks: 50,
      );
      expect(end.x, closeTo(10, 1e-9));
      expect(end.y, closeTo(20, 1e-9));
    });
  });
}
