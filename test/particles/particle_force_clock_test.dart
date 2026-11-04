// Particle forces keep one clock per frame: wind and noise advance once a
// frame, not once per particle.

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
  group('forces keep one clock per frame', () {
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
}
