// Effects and particles fixes from the 2.0.0 final pass: a shake ends where
// it started (F37); wind and noise keep one clock per frame, not per
// particle (F39); a permanent ray never expires (F40).

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts how often it is advanced and applied.
class _CountingForce extends ParticleForce {
  int advances = 0;
  int applies = 0;

  @override
  void advance(double dt) => advances++;

  @override
  void apply(Particle particle, double dt) => applies++;
}

/// Notes each particle's vertical speed as the forces before it left it.
class _SpeedRecorder extends ParticleForce {
  final List<double> vys = [];

  @override
  void apply(Particle particle, double dt) => vys.add(particle.vy);
}

void main() {
  group('F37 ShakeEffect', () {
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

  group('F39 forces keep one clock per frame', () {
    test('an emitter advances each force once per update', () {
      final force = _CountingForce();
      final emitter = ParticleEmitter(
        maxParticles: 50,
        emissionRate: 0,
        particleLifetime: 10,
        forces: [force],
      )..burst(20);
      emitter.update(1 / 60);
      emitter.update(1 / 60);
      expect(force.advances, 2);
      expect(force.applies, 40);
    });

    test('every particle feels the same wind in a frame', () {
      List<double> lastFrame(int count) {
        final recorder = _SpeedRecorder();
        final emitter = ParticleEmitter(
          maxParticles: count,
          emissionRate: 0,
          particleLifetime: 10,
          speed: 0,
          speedVariation: 0,
          forces: [
            WindForce(strength: 0, turbulence: 40, frequency: 3.7),
            recorder,
          ],
        )..burst(count);
        for (var i = 0; i < 5; i++) {
          emitter.update(0.25);
        }
        return recorder.vys.sublist(recorder.vys.length - count);
      }

      final crowd = lastFrame(10).toSet();
      expect(crowd, hasLength(1), reason: 'one clock for all');
      expect(crowd.single, closeTo(lastFrame(1).single, 1e-12));
      expect(crowd.single, isNot(0.0));
    });
  });

  group('F40 RayRenderable', () {
    test('a permanent beam never expires', () {
      final ray = RayRenderable(
        start: Offset.zero,
        end: const Offset(10, 0),
        lifetime: 0,
      );
      expect(ray.isExpired, isFalse, reason: 'it expired at once');
      ray.update(100);
      expect(ray.isExpired, isFalse);
      expect(ray.opacity, 1.0);
    });

    test('a fading one expires after its lifetime', () {
      final ray = RayRenderable(start: Offset.zero, end: const Offset(1, 0));
      expect(ray.isExpired, isFalse);
      ray.update(0.3);
      expect(ray.isExpired, isTrue);
    });
  });
}
