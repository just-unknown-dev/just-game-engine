// HealthComponent and HealthSystem: damage, invulnerability, regeneration
// and death; LifetimeComponent and LifetimeSystem: expiry, and progress
// for a zero lifetime.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('HealthComponent', () {
    test('damage clamps at 0; invulnerable ignores it; heal stops at max', () {
      final health = HealthComponent(maxHealth: 10);
      health.damage(4);
      expect(health.health, 6);
      health.damage(100);
      expect(health.health, 0);
      expect(health.isDead, isTrue);
      health.heal(50);
      expect(health.health, 10);
      health
        ..isInvulnerable = true
        ..damage(5);
      expect(health.health, 10);
      expect(health.healthPercent, 1.0);
    });
  });

  group('HealthSystem', () {
    late World world;
    late HealthSystem system;
    setUp(() {
      world = World()..initialize();
      system = HealthSystem();
      world.addSystem(system);
    });
    tearDown(() => world.dispose());

    test('regenRate heals by the second, never past max', () {
      final health = HealthComponent(maxHealth: 10, health: 5);
      world.createEntityWithComponents([health]);
      system.regenRate = 2;
      world.update(0.5);
      expect(health.health, closeTo(6, 1e-9));
      for (var i = 0; i < 10; i++) {
        world.update(0.5);
      }
      expect(health.health, 10);
    });

    test('a dead entity is destroyed with destroyOnDeath, kept without', () {
      final dead = world.createEntityWithComponents([
        HealthComponent(maxHealth: 10, health: 0),
      ]);
      world.update(1 / 60);
      expect(dead.isAlive, isFalse);

      system.destroyOnDeath = false;
      final kept = world.createEntityWithComponents([
        HealthComponent(maxHealth: 10, health: 0),
      ]);
      world.update(1 / 60);
      expect(kept.isAlive, isTrue);
    });

    test('a dead entity does not regenerate', () {
      system
        ..regenRate = 5
        ..destroyOnDeath = false;
      final health = HealthComponent(maxHealth: 10, health: 0);
      world.createEntityWithComponents([health]);
      world.update(1);
      expect(health.health, 0);
    });
  });

  group('lifetime', () {
    test('LifetimeSystem: alive at 0.9 s, gone at 1.1 s', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(LifetimeSystem());
      final entity = world.createEntityWithComponents([LifetimeComponent(1)]);
      for (var i = 0; i < 9; i++) {
        world.update(0.1);
      }
      expect(entity.isAlive, isTrue);
      world
        ..update(0.1)
        ..update(0.1);
      expect(entity.isAlive, isFalse);
    });

    test('progress runs from 0 to 1, and is 1 for a lifetime of 0', () {
      final lifetime = LifetimeComponent(2);
      expect(lifetime.progress, 0);
      lifetime.update(1);
      expect(lifetime.progress, 0.5);
      lifetime.update(5); // past its end
      expect(lifetime.progress, 1.0);

      final none = LifetimeComponent(0);
      expect(none.progress, 1.0, reason: 'not NaN');
      expect(none.isExpired, isTrue);
    });
  });
}
