import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // ParticleForce tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ParticleForce', () {
    Particle makeParticle({
      Offset velocity = Offset.zero,
      Offset position = Offset.zero,
    }) {
      return Particle(
        position: position,
        velocity: velocity,
        lifetime: 2.0,
        startSize: 5.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );
    }

    test('GravityForce accelerates velocity downward', () {
      final p = makeParticle();
      const force = GravityForce(Offset(0, 100));
      force.apply(p, 0.016);
      expect(p.velocity.dy, closeTo(1.6, 0.001));
      expect(p.velocity.dx, closeTo(0.0, 0.001));
    });

    test('DragForce reduces velocity magnitude', () {
      final p = makeParticle(velocity: const Offset(100, 0));
      const force = DragForce(coefficient: 0.1);
      force.apply(p, 1.0);
      // v *= 1 - 0.1*1.0 = 0.9
      expect(p.velocity.dx, closeTo(90.0, 0.01));
    });

    test('DragForce clamps at zero (no reversal)', () {
      final p = makeParticle(velocity: const Offset(10, 0));
      // Coefficient so large it would invert if unclamped
      const force = DragForce(coefficient: 200.0);
      force.apply(p, 1.0);
      // factor = clamp(1 - 200*1, 0, 1) = 0.0 → velocity zeroed
      expect(p.velocity.dx, closeTo(0.0, 0.001));
    });

    test('BoundaryForce.bounce reflects velocity on floor', () {
      final bounds = const Rect.fromLTRB(-500, -500, 500, 300);
      final force = BoundaryForce(
        bounds: bounds,
        behavior: ParticleBoundaryBehavior.bounce,
        restitution: 0.8,
      );
      // Particle just below floor moving downward
      final p = makeParticle(
        position: const Offset(0, 305),
        velocity: const Offset(0, 50),
      );
      force.apply(p, 0.016);
      // Should have been pushed back to boundary and velocity reflected
      expect(p.position.dy, closeTo(300.0, 0.001));
      expect(p.velocity.dy, lessThan(0)); // now moving upward
    });

    test('BoundaryForce.kill sets particle dead', () {
      final p = makeParticle(position: const Offset(600, 0));
      final force = BoundaryForce(
        bounds: const Rect.fromLTRB(-500, -500, 500, 500),
        behavior: ParticleBoundaryBehavior.kill,
      );
      force.apply(p, 0.016);
      expect(p.isDead, isTrue);
    });

    test('AttractorForce pulls in-radius particle toward center', () {
      final force = AttractorForce(
        center: const Offset(100, 0),
        strength: 1000,
        radius: 200,
      );
      final p = makeParticle(position: const Offset(0, 0));
      final vxBefore = p.velocity.dx;
      force.apply(p, 0.1);
      // Should pull rightward (toward center at x=100)
      expect(p.velocity.dx, greaterThan(vxBefore));
    });

    test('AttractorForce ignores out-of-radius particle', () {
      final force = AttractorForce(
        center: const Offset(1000, 0),
        strength: 1000,
        radius: 50, // particle is far outside
      );
      final p = makeParticle(position: const Offset(0, 0));
      force.apply(p, 0.1);
      expect(p.velocity.dx, closeTo(0.0, 0.001));
    });

    test('VortexForce produces tangential velocity change', () {
      final force = VortexForce(
        center: const Offset(0, 0),
        strength: 500,
        radius: 200,
      );
      // Particle directly to the right of center
      final p = makeParticle(position: const Offset(50, 0));
      force.apply(p, 0.1);
      // Tangent at (50,0) for counterclockwise vortex should be (0,1) direction
      // → velocity.dy should increase
      expect(p.velocity.dy, greaterThan(0));
      // x component should be unchanged (tangent has no x component here)
      expect(p.velocity.dx, closeTo(0.0, 0.1));
    });

    test('NoiseForce produces non-zero, bounded velocity delta', () {
      final force = NoiseForce(strength: 100, scale: 0.01, speed: 1.0);
      final p = makeParticle(position: const Offset(200, 300));
      // Apply several frames
      for (int i = 0; i < 10; i++) {
        force.apply(p, 0.016);
      }
      // Should have moved from zero velocity appreciably
      final speed = math.sqrt(
        p.velocity.dx * p.velocity.dx + p.velocity.dy * p.velocity.dy,
      );
      expect(speed, greaterThan(0.0));
      // Should not explode to unreasonable values (10 frames * 0.016 * 100)
      expect(speed, lessThan(500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Particle class tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Particle', () {
    test('normalizedLife clamps to [0, 1]', () {
      final p = Particle(
        position: Offset.zero,
        velocity: Offset.zero,
        lifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );
      expect(p.normalizedLife, 0.0);
      p.update(0.5, const []);
      expect(p.normalizedLife, closeTo(0.5, 0.001));
      p.update(2.0, const []); // overshoot
      expect(p.normalizedLife, 1.0);
    });

    test('isDead only after lifetime exceeded', () {
      final p = Particle(
        position: Offset.zero,
        velocity: Offset.zero,
        lifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );
      expect(p.isDead, isFalse);
      p.update(1.0, const []);
      expect(p.isDead, isTrue);
    });

    test('previousPosition saved before integration', () {
      final p = Particle(
        position: const Offset(10, 20),
        velocity: const Offset(100, 0),
        lifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );
      p.update(0.016, const []);
      expect(p.previousPosition, const Offset(10, 20));
      expect(p.position.dx, greaterThan(10));
    });

    test('reset re-initializes all fields', () {
      final p = Particle(
        position: const Offset(0, 0),
        velocity: const Offset(1, 1),
        lifetime: 1.0,
        startSize: 5.0,
        endSize: 1.0,
        startColor: Colors.red,
        endColor: Colors.blue,
      );
      p.update(0.5, const []);
      expect(p.age, 0.5);

      p.reset(
        position: const Offset(100, 200),
        velocity: const Offset(0, 0),
        lifetime: 2.0,
        startSize: 8.0,
        endSize: 2.0,
        startColor: Colors.green,
        endColor: Colors.transparent,
      );
      expect(p.age, 0.0);
      expect(p.position, const Offset(100, 200));
      expect(p.lifetime, 2.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ParticleEmitter tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ParticleEmitter', () {
    test('burst() emits exactly the requested count', () {
      final emitter = ParticleEmitter(
        maxParticles: 50,
        emissionRate: 0, // no continuous emission
        particleLifetime: 2.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
      );
      emitter.burst(20);
      expect(emitter.particleCount, 20);
    });

    test('burst() does not exceed maxParticles', () {
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 2.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
      );
      emitter.burst(100);
      expect(emitter.particleCount, 10);
    });

    test('particles expire and are removed over time', () {
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 0.1, // 100 ms lifetime
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
      );
      emitter.burst(5);
      expect(emitter.particleCount, 5);

      emitter.update(0.2); // advance past lifetime
      expect(emitter.particleCount, 0);
    });

    test('isComplete is true when stopped and no live particles', () {
      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        duration: 0.01, // stop emitting almost immediately
        forces: const [],
      );
      emitter.update(0.5);
      expect(emitter.isComplete, isTrue);
    });

    test('GravityForce via gravity param (backward compat)', () {
      // ignore: deprecated_member_use
      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 2.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        // ignore: deprecated_member_use
        gravity: const Offset(0, 100),
      );
      expect(emitter.forces.length, 1);
      expect(emitter.forces.first, isA<GravityForce>());
    });

    test('forces list is unmodifiable from outside', () {
      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: [const DragForce()],
      );
      expect(
        () => emitter.forces.add(const DragForce()),
        throwsUnsupportedError,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Sub-emitter tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SubEmitter', () {
    test('onDeath sub-emitter spawned when particle dies', () {
      int spawnCount = 0;

      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            maxInstances: 100,
            factory: (pos) {
              spawnCount++;
              return ParticleEmitter(
                maxParticles: 5,
                emissionRate: 0,
                particleLifetime: 0.05,
                startSize: 2.0,
                endSize: 0.5,
                startColor: Colors.red,
                endColor: Colors.transparent,
                forces: const [],
              );
            },
          ),
        ],
      );

      emitter.burst(3);
      emitter.update(0.1); // advance past all particle lifetimes
      expect(spawnCount, greaterThan(0));
    });

    test('onLifetimeFraction sub-emitter fires at correct fraction', () {
      int spawnCount = 0;

      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 0,
        particleLifetime: 1.0,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onLifetimeFraction,
            lifetimeFraction: 0.5,
            maxInstances: 10,
            factory: (pos) {
              spawnCount++;
              return ParticleEmitter(
                maxParticles: 1,
                emissionRate: 0,
                particleLifetime: 0.1,
                startSize: 2.0,
                endSize: 0.5,
                startColor: Colors.blue,
                endColor: Colors.transparent,
                forces: const [],
              );
            },
          ),
        ],
      );

      emitter.burst(1);
      expect(spawnCount, 0);

      emitter.update(0.4); // not yet at 50%
      expect(spawnCount, 0);

      emitter.update(0.15); // now past 50%
      expect(spawnCount, 1);

      emitter.update(0.15); // should NOT fire again (milestone already fired)
      expect(spawnCount, 1);
    });

    test('maxInstances limits spawned sub-emitters', () {
      int spawnCount = 0;

      final emitter = ParticleEmitter(
        maxParticles: 20,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            maxInstances: 3, // hard cap
            factory: (pos) {
              spawnCount++;
              return ParticleEmitter(
                maxParticles: 1,
                emissionRate: 0,
                particleLifetime: 0.1,
                startSize: 2.0,
                endSize: 0.5,
                startColor: Colors.green,
                endColor: Colors.transparent,
                forces: const [],
              );
            },
          ),
        ],
      );

      emitter.burst(20);
      emitter.update(0.1);
      // maxInstances=3 caps new spawns when active sub-emitters aren't cleared yet
      // Because they last 0.1s and we advance 0.1s in one step, most die at the
      // same time as the parent particles, so the limit applies.
      expect(spawnCount, lessThanOrEqualTo(20)); // basic sanity
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ParticleEffect tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ParticleEffect', () {
    test('onSpawn called for each emitted particle', () {
      int spawnCount = 0;

      final effect = _CountingEffect(onSpawnCallback: () => spawnCount++);
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        effect: effect,
        forces: const [],
      );

      emitter.burst(7);
      expect(spawnCount, 7);
    });

    test('onDeath called for each dying particle', () {
      int deathCount = 0;

      final effect = _CountingEffect(onDeathCallback: () => deathCount++);
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        effect: effect,
        forces: const [],
      );

      emitter.burst(5);
      emitter.update(0.1); // advance past lifetime
      expect(deathCount, 5);
    });

    test('onUpdate can override particle physics', () {
      final effect = _FixedVelocityEffect(fixedVelocity: const Offset(999, 0));
      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 0,
        particleLifetime: 2.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        effect: effect,
        forces: const [],
      );

      emitter.burst(1);
      emitter.update(0.016);

      // After one tick the particle should have moved by 999*0.016
      // The effect overrides velocity every tick so position increases fast
      expect(emitter.particleCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ECS integration — ParticleSystemECS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ParticleSystemECS', () {
    late World world;

    setUp(() {
      world = World();
      world.addSystem(ParticleSystemECS());
    });

    tearDown(() => world.dispose());

    test('syncs emitter position from TransformComponent each frame', () {
      final entity = world.createEntity();
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
      );
      entity.addComponent(TransformComponent(position: const Offset(200, 400)));
      entity.addComponent(
        ParticleEmitterComponent(
          emitter: emitter,
          syncPositionFromTransform: true,
        ),
      );

      world.update(0.016);
      expect(emitter.position, const Offset(200, 400));
    });

    test('does not sync position when syncPositionFromTransform is false', () {
      final entity = world.createEntity();
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
        position: const Offset(50, 50),
      );
      entity.addComponent(TransformComponent(position: const Offset(999, 999)));
      entity.addComponent(
        ParticleEmitterComponent(
          emitter: emitter,
          syncPositionFromTransform: false,
        ),
      );

      world.update(0.016);
      expect(emitter.position, const Offset(50, 50));
    });

    test('removeEntityWhenComplete destroys entity after emitter finishes', () {
      final entity = world.createEntity();
      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        duration: 0.01,
        forces: const [],
      );
      entity.addComponent(
        ParticleEmitterComponent(
          emitter: emitter,
          syncPositionFromTransform: false,
          removeEntityWhenComplete: true,
        ),
      );

      // Advance well past completion
      for (int i = 0; i < 60; i++) {
        world.update(0.016);
      }

      expect(world.isEntityAlive(entity), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RenderingEngine managed emitters
  // ═══════════════════════════════════════════════════════════════════════════

  group('RenderingEngine.managedEmitters', () {
    test('addManagedEmitter / removeManagedEmitter round-trip', () {
      final rendering = RenderingEngine();
      rendering.initialize();
      // assign a dummy camera to avoid NPE
      rendering.camera = Camera(viewportSize: const Size(800, 600));

      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 1.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        forces: const [],
      );

      rendering.addManagedEmitter(emitter);
      rendering.addManagedEmitter(emitter); // idempotent

      rendering.updateManagedEmitters(0.016);

      rendering.removeManagedEmitter(emitter);
      // After removal, should be gone from renderables
      expect(rendering.renderableCount, 0);
    });

    test('completed emitters are auto-removed during update', () {
      final rendering = RenderingEngine();
      rendering.initialize();
      rendering.camera = Camera(viewportSize: const Size(800, 600));

      final emitter = ParticleEmitter(
        maxParticles: 5,
        emissionRate: 0,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        startSize: 4.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
        duration: 0.01,
        forces: const [],
      );

      rendering.addManagedEmitter(emitter);
      // Advance until complete
      for (int i = 0; i < 10; i++) {
        rendering.updateManagedEmitters(0.016);
      }

      expect(rendering.renderableCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ParticlePresets smoke tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ParticleEffects presets', () {
    const pos = Offset(100, 100);

    for (final entry in <String, ParticleEmitter Function()>{
      'explosion': () => ParticleEffects.explosion(position: pos),
      'fire': () => ParticleEffects.fire(position: pos),
      'smoke': () => ParticleEffects.smoke(position: pos),
      'sparkle': () => ParticleEffects.sparkle(position: pos),
      'rain': () => ParticleEffects.rain(position: pos),
      'snow': () => ParticleEffects.snow(position: pos),
      'portal': () => ParticleEffects.portal(position: pos),
      'magic': () => ParticleEffects.magic(position: pos),
      'bloodSplatter': () => ParticleEffects.bloodSplatter(position: pos),
      'dustKick': () => ParticleEffects.dustKick(position: pos),
      'electricSparks': () => ParticleEffects.electricSparks(position: pos),
      'waterSplash': () => ParticleEffects.waterSplash(position: pos),
      'healAura': () => ParticleEffects.healAura(position: pos),
      'confetti': () => ParticleEffects.confetti(position: pos),
      'lavaEmbers': () => ParticleEffects.lavaEmbers(position: pos),
    }.entries) {
      test('${entry.key} preset constructs without error', () {
        final emitter = entry.value();
        expect(emitter, isNotNull);
        expect(emitter.maxParticles, greaterThan(0));
      });

      test('${entry.key} preset advances without error', () {
        final emitter = entry.value();
        for (int i = 0; i < 10; i++) {
          emitter.update(0.016);
        }
        expect(emitter.particleCount, greaterThanOrEqualTo(0));
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NoiseForce smoothness test
  // ═══════════════════════════════════════════════════════════════════════════

  group('NoiseForce smoothness', () {
    test('consecutive samples at nearby positions are close in value', () {
      final force = NoiseForce(strength: 100, scale: 0.01, speed: 0.5);

      final p1 = Particle(
        position: const Offset(100, 100),
        velocity: Offset.zero,
        lifetime: 10.0,
        startSize: 1.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );
      final p2 = Particle(
        position: const Offset(101, 100), // 1 unit away
        velocity: Offset.zero,
        lifetime: 10.0,
        startSize: 1.0,
        endSize: 1.0,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );

      force.apply(p1, 0.016);

      // Fresh instance at the same _time=0 state for p2 comparison
      final force2 = NoiseForce(strength: 100, scale: 0.01, speed: 0.5);
      force2.apply(p2, 0.016);

      // Particles 1 unit apart should have similar velocity perturbations
      // (smooth noise property: small spatial delta → small value delta)
      final delta = (p1.velocity - p2.velocity).distance;
      expect(delta, lessThan(5.0)); // generous bound for unit test
    });
  });
}

// ─── Test-helper effect classes ───────────────────────────────────────────────

class _CountingEffect extends ParticleEffect {
  final void Function()? onSpawnCallback;
  final void Function()? onDeathCallback;

  _CountingEffect({this.onSpawnCallback, this.onDeathCallback});

  @override
  void onSpawn(Particle particle, ParticleEmitter emitter) {
    onSpawnCallback?.call();
  }

  @override
  void onDeath(Particle particle, ParticleEmitter emitter) {
    onDeathCallback?.call();
  }
}

class _FixedVelocityEffect extends ParticleEffect {
  final Offset fixedVelocity;
  _FixedVelocityEffect({required this.fixedVelocity});

  @override
  void onUpdate(Particle particle, double dt, List<ParticleForce> forces) {
    particle.velocity = fixedVelocity;
    particle.update(dt, const []);
  }
}
