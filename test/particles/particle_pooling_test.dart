// A particle emitter returns its expired particles to the shared pool.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('ParticleEmitter pooling', () {
    test('returns expired particles to the shared pool', () {
      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 100,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        sizeVariation: 0.0,
        speedVariation: 0.0,
        startSize: 1,
        endSize: 1,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );

      emitter.update(0.02);
      expect(emitter.particleCount, 1);

      emitter.isEmitting = false;
      emitter.update(0.1);

      expect(emitter.particleCount, 0);
      expect(emitter.pooledParticleCount, 1);
    });
  });
}
