// The ready-made effects: forces that pull towards the emitter follow it
// when it moves, rain falls across its whole width, and a sparkle is a
// burst that ends.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Particle _probe(double x, double y) => Particle(
  position: Offset(x, y),
  velocity: Offset.zero,
  lifetime: 10,
  startSize: 4,
  endSize: 4,
  startColor: Colors.white,
  endColor: Colors.white,
);

/// [emitter] on an entity at (500, 300), after one frame of the world.
ParticleEmitter _movedTo500x300(World world, ParticleEmitter emitter) {
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(500, 300, 0)),
    ParticleEmitterComponent(emitter: emitter),
  ]);
  world.update(0.016);
  expect(emitter.position, Vector3(500, 300, 0));
  return emitter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('force centres follow the emitter', () {
    late World world;

    setUp(() => world = World()..addSystem(ParticleSystem()));
    tearDown(() => world.dispose());

    test('portal: its vortex and attractor are where the entity is', () {
      final portal = _movedTo500x300(
        world,
        ParticleEffects.portal(position: Vector3.zero()),
      );
      // 50 to the right of the entity: pulled left, swirled along y.
      final pulled = _probe(550, 300);
      for (final f in portal.forces.whereType<AttractorForce>()) {
        f.apply(pulled, 0.1);
      }
      expect(pulled.vx, lessThan(0), reason: 'the attractor stayed at 0,0');

      final swirled = _probe(550, 300);
      for (final f in portal.forces.whereType<VortexForce>()) {
        f.apply(swirled, 0.1);
      }
      expect(swirled.vy, isNot(0), reason: 'the vortex stayed at 0,0');
    });

    test('magic: its attractor is where the entity is', () {
      final magic = _movedTo500x300(
        world,
        ParticleEffects.magic(position: Vector3.zero()),
      );
      final p = _probe(450, 300);
      for (final f in magic.forces.whereType<AttractorForce>()) {
        f.apply(p, 0.1);
      }
      expect(p.vx, greaterThan(0));
    });

    test('healAura: its attractor is 60 above the entity', () {
      final aura = _movedTo500x300(
        world,
        ParticleEffects.healAura(position: Vector3.zero()),
      );
      final right = _probe(540, 240);
      final below = _probe(500, 280);
      for (final f in aura.forces.whereType<AttractorForce>()) {
        f
          ..apply(right, 0.1)
          ..apply(below, 0.1);
      }
      expect(right.vx, lessThan(0));
      expect(right.vy, closeTo(0, 1e-9));
      expect(below.vy, lessThan(0));
    });

    test('a force placed in the world stays where it was put', () {
      final attractor = AttractorForce(center: const Offset(10, 0));
      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 0,
        forces: [attractor],
      );
      emitter.position.setValues(500, 300, 0);
      emitter.update(0.016);
      final p = _probe(20, 0);
      attractor.apply(p, 0.1);
      expect(p.vx, lessThan(0));
    });

    test('a sub-emitter pulls towards where it was made', () {
      final children = <ParticleEmitter>[];
      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0,
        speed: 0,
        speedVariation: 0,
        forces: const [],
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (at) {
              final child = ParticleEffects.magic(
                position: Vector3(at.dx, at.dy, 0),
              );
              children.add(child);
              return child;
            },
          ),
        ],
      );
      emitter.position.setValues(500, 300, 0);
      emitter
        ..burst(1)
        ..update(0.1) // the particle dies: the child is made at 500,300
        ..update(0.016); // and moves on a frame
      expect(children, hasLength(1));
      final p = _probe(450, 300);
      for (final f in children.single.forces.whereType<AttractorForce>()) {
        f.apply(p, 0.1);
      }
      expect(p.vx, greaterThan(0));
    });
  });

  test('rain falls across its whole width', () {
    final rain = ParticleEffects.rain(position: Vector3.zero(), width: 1200);
    rain.update(0.1);
    expect(rain.particleCount, greaterThan(5));
    final bounds = rain.bounds!;
    expect(
      bounds.width,
      greaterThan(400),
      reason: 'every drop started at one point',
    );
    expect(bounds.left, greaterThanOrEqualTo(-602));
    expect(bounds.right, lessThanOrEqualTo(602));
  });

  test('an emitter spawns over its spawn area, centred on it', () {
    final emitter = ParticleEmitter(
      maxParticles: 200,
      emissionRate: 0,
      speed: 0,
      speedVariation: 0,
      forces: const [],
      spawnArea: const Size(100, 40),
    );
    emitter.position.setValues(10, 20, 0);
    emitter.burst(200);
    final bounds = emitter.bounds!;
    // Particles are 5 across: the area grown by 2.5 at most.
    expect(bounds.left, greaterThanOrEqualTo(10 - 50 - 3));
    expect(bounds.right, lessThanOrEqualTo(10 + 50 + 3));
    expect(bounds.top, greaterThanOrEqualTo(20 - 20 - 3));
    expect(bounds.bottom, lessThanOrEqualTo(20 + 20 + 3));
    expect(bounds.width, greaterThan(60));
    expect(bounds.height, greaterThan(20));
  });

  group('sparkle', () {
    test('is a burst that ends', () {
      final sparkle = ParticleEffects.sparkle(position: Vector3.zero());
      for (var i = 0; i < 200; i++) {
        sparkle.update(0.016);
      }
      expect(sparkle.isEmitting, isFalse);
      expect(sparkle.isComplete, isTrue);
    });

    test('keeps twinkling with no duration', () {
      final sparkle = ParticleEffects.sparkle(
        position: Vector3.zero(),
        duration: null,
      );
      for (var i = 0; i < 200; i++) {
        sparkle.update(0.016);
      }
      expect(sparkle.isEmitting, isTrue);
      expect(sparkle.particleCount, greaterThan(0));
    });

    test('a firework of sparkles finishes', () {
      final firework = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 0.5,
        lifetimeVariation: 0,
        forces: const [],
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (at) =>
                ParticleEffects.sparkle(position: Vector3(at.dx, at.dy, 0)),
          ),
        ],
      )..burst(10);
      for (var i = 0; i < 300; i++) {
        firework.update(0.016);
      }
      expect(firework.isComplete, isTrue);
    });
  });
}
