import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Core Engine Tests', () {
    test('Engine initialization', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      expect(engine.isInitialized, false);
      expect(engine.isRunning, false);

      await engine.initialize();
      expect(engine.isInitialized, true);
      expect(engine.isRunning, false);
    });

    test('Engine lifecycle', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      engine.start();
      expect(engine.isRunning, true);
      expect(engine.isPaused, false);

      engine.pause();
      expect(engine.isPaused, true);

      engine.resume();
      expect(engine.isPaused, false);

      engine.stop();
      expect(engine.isRunning, false);
    });

    test('Engine subsystems are initialized', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      expect(engine.rendering, isNotNull);
      expect(engine.physics, isNotNull);
      expect(engine.input, isNotNull);
      expect(engine.world, isNotNull);
      expect(engine.assets, isNotNull);
      expect(engine.audio, isNotNull);
    });

    test('Two engines are separate', () async {
      final engine1 = Engine();
      final engine2 = Engine();
      addTearDown(engine1.dispose);
      addTearDown(engine2.dispose);
      await engine1.initialize();
      await engine2.initialize();
      expect(engine1.world, isNot(same(engine2.world)));
      expect(engine1.world.context, same(engine1.context));
      expect(engine2.world.context, same(engine2.context));
    });
  });

  group('Rendering Engine Tests', () {
    test('Add and remove renderables', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final circle = CircleRenderable(
        radius: 50,
        fillColor: Colors.red,
        position: Vector3(0, 0, 0),
      );

      engine.rendering.addRenderable(circle);
      expect(engine.rendering.renderables, contains(circle));

      engine.rendering.removeRenderable(circle);
      expect(engine.rendering.renderables, isNot(contains(circle)));
    });

    test('Layer sorting', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final obj1 = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        layer: 2,
      );
      final obj2 = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        layer: 0,
      );
      final obj3 = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        layer: 1,
      );

      engine.rendering.addRenderable(obj1);
      engine.rendering.addRenderable(obj2);
      engine.rendering.addRenderable(obj3);

      final renderables = engine.rendering.renderables;
      expect(renderables[0].layer, 0);
      expect(renderables[1].layer, 1);
      expect(renderables[2].layer, 2);
    });

    test('Camera transformations', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final camera = engine.rendering.camera;
      final initialPos = camera.position;

      camera.moveBy(const Offset(100, 50));
      expect(camera.position, isNot(equals(initialPos)));

      camera.reset();
      expect(camera.position, equals(initialPos));
    });

    test('Camera zoom', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final camera = engine.rendering.camera;
      final initialZoom = camera.zoom;

      camera.zoomBy(2.0);
      expect(camera.zoom, initialZoom * 2.0);

      camera.reset();
      expect(camera.zoom, initialZoom);
    });

    test('Visibility filtering', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final visible = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        visible: true,
      );
      final invisible = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        visible: false,
      );

      engine.rendering.addRenderable(visible);
      engine.rendering.addRenderable(invisible);

      final visibleRenderables = engine.rendering.renderables
          .where((r) => r.visible)
          .toList();
      expect(visibleRenderables.length, 1);
      expect(visibleRenderables, contains(visible));
    });
  });

  group('Physics Engine Tests', () {
    test('Add and remove physics bodies', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final body = PhysicsBody(position: Vector2(0, 0), shape: CircleShape(30));

      engine.physics.addBody(body);
      expect(engine.physics.bodies, contains(body));

      engine.physics.removeBody(body);
      expect(engine.physics.bodies, isNot(contains(body)));
    });

    test('Physics body velocity integration', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final body = PhysicsBody(
        position: Vector2(0, 0),
        velocity: Vector2(100, 0),
        shape: CircleShape(30),
        drag: 0.0,
      );

      engine.physics.addBody(body);
      final initialPosX = body.position.x;

      // Stepped as 60 frames rather than one 1-second frame. Both backends
      // clamp their accumulator to a handful of fixed sub-steps per call, so a
      // single huge delta simulates only a fraction of the time asked for —
      // that clamp is what stops a stalled frame from triggering a death
      // spiral of catch-up steps.
      for (var i = 0; i < 60; i++) {
        engine.physics.update(1.0 / 60.0);
      }

      expect(body.position.x, closeTo(initialPosX + 100, 2.0));
    });

    test('Collision detection', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final body1 = PhysicsBody(
        position: Vector2(0, 0),
        shape: CircleShape(30),
      );

      final body2 = PhysicsBody(
        position: Vector2(50, 0),
        shape: CircleShape(30),
      );

      engine.physics.addBody(body1);
      engine.physics.addBody(body2);

      final distance =
          (body1.position.toOffset() - body2.position.toOffset()).distance;
      final combinedRadius =
          (body1.shape as CircleShape).radius +
          (body2.shape as CircleShape).radius;
      expect(distance < combinedRadius, true);
    });

    test('Physics body mass and restitution', () async {
      final body = PhysicsBody(
        position: Vector2(0, 0),
        shape: CircleShape(30),
        mass: 2.0,
        restitution: 0.8,
      );

      expect(body.mass, 2.0);
      expect(body.restitution, 0.8);
    });

    test('Gravity simulation', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final body = PhysicsBody(
        position: Vector2(0, 0),
        velocity: Vector2.zero(),
        shape: CircleShape(30),
      );

      engine.physics.gravity.setValues(0, 100);
      engine.physics.addBody(body);

      final initialY = body.position.y;
      engine.physics.update(1.0);

      // Body should have fallen due to gravity
      expect(body.position.y > initialY, true);
    });
  });

  group('Particle System Tests', () {
    test('ParticleEmitter creation', () {
      final emitter = ParticleEmitter(
        position: Vector3(0, 0, 0),
        maxParticles: 100,
        emissionRate: 30,
        particleLifetime: 2.0,
      );

      expect(emitter.position, Vector3(0, 0, 0));
      expect(emitter.emissionRate, 30);
      expect(emitter.particleLifetime, 2.0);
    });

    test('Particle emission', () {
      final emitter = ParticleEmitter(
        position: Vector3(0, 0, 0),
        maxParticles: 100,
        emissionRate: 10,
        particleLifetime: 1.0,
      );

      // Emitter starts automatically (isEmitting = true)
      emitter.update(1.0); // 1 second = ~10 particles

      expect(emitter.particleCount, greaterThan(0));
    });

    test('Particle lifecycle', () {
      final emitter = ParticleEmitter(
        position: Vector3(0, 0, 0),
        maxParticles: 100,
        emissionRate: 10,
        particleLifetime: 0.5,
      );

      // Emitter starts automatically
      emitter.update(0.3);
      final particleCount = emitter.particleCount;

      emitter.isEmitting = false; // Stop emission so we only observe death
      // Update past lifetime
      emitter.update(0.5);

      // Old particles should have died
      expect(emitter.particleCount < particleCount, true);
    });

    test('Particle preset effects', () {
      final explosion = ParticleEffects.explosion(position: Vector3.zero());
      expect(explosion.emissionRate, greaterThan(0));

      final fire = ParticleEffects.fire(position: Vector3.zero());
      expect(fire.emissionRate, greaterThan(0));

      final sparkle = ParticleEffects.sparkle(position: Vector3.zero());
      expect(sparkle.emissionRate, greaterThan(0));
    });
  });

  group('Entity-Component System Tests', () {
    test('Create entity', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final entity = engine.world.createEntity(name: 'TestEntity');
      expect(entity, isNotNull);
      expect(entity.name, 'TestEntity');
    });

    test('Add components to entity', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final entity = engine.world.createEntity();
      final transform = TransformComponent(position: Vector3(0, 0, 0));

      entity.addComponent(transform);
      expect(entity.hasComponent<TransformComponent>(), true);
      expect(entity.getComponent<TransformComponent>(), same(transform));
    });

    test('Remove component from entity', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final entity = engine.world.createEntity();
      final transform = TransformComponent(position: Vector3(0, 0, 0));

      entity.addComponent(transform);
      entity.removeComponent<TransformComponent>();
      expect(entity.hasComponent<TransformComponent>(), false);
    });

    test('Query entities by component', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final entity1 = engine.world.createEntity();
      entity1.addComponent(TransformComponent(position: Vector3(0, 0, 0)));
      entity1.addComponent(VelocityComponent(velocity: Vector3(10, 0, 0)));

      final entity2 = engine.world.createEntity();
      entity2.addComponent(TransformComponent(position: Vector3(0, 0, 0)));

      final movingEntities = engine.world.query([
        TransformComponent,
        VelocityComponent,
      ]);

      expect(movingEntities.length, 1);
      expect(movingEntities, contains(entity1));
    });

    test('Destroy entity', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final entity = engine.world.createEntity(name: 'ToDestroy');

      engine.world.destroyEntity(entity);
      expect(engine.world.findEntityByName('ToDestroy'), isNull);
    });

    test('Add system to world', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final system = MovementSystem();
      engine.world.addSystem(system);

      expect(engine.world.systems, contains(system));
    });
  });

  group('Asset Management Tests', () {
    test('AssetManager initialization', () {
      final assetManager = AssetManager();
      expect(assetManager, isNotNull);
    });

    test('Cache operations', () {
      final assetManager = AssetManager();

      // Get stats
      final stats = assetManager.getCacheStats();
      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('totalAssets'), true);
      expect(stats.containsKey('memoryUsage'), true);
    });
  });

  group('Input System Tests', () {
    test('InputService initialization', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      expect(engine.input, isNotNull);
      expect(engine.input.devices, [
        engine.input.keyboard,
        engine.input.mouse,
        engine.input.touchscreen,
        engine.input.onScreen,
      ]);
      expect(engine.input.gamepads, isEmpty, reason: 'pads are opt-in');
    });

    test('Mouse state management', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      expect(engine.input.mouse.control('position')!.read(), Offset.zero);
    });

    test('Touch state management', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      expect(engine.input.touchscreen.touches, isEmpty);
    });
  });

  group('Audio Engine Tests', () {
    test('AudioEngine initialization', () async {
      final audioEngine = AudioEngine();

      // Plugins may be unavailable in unit-test/headless environments.
      try {
        await audioEngine.initialize();
      } catch (_) {}

      expect(audioEngine, isNotNull);
    });

    test('Volume control', () async {
      final audioEngine = AudioEngine();

      // Plugins may be unavailable in unit-test/headless environments.
      try {
        await audioEngine.initialize();
      } catch (_) {}

      audioEngine.setMasterVolume(0.5);
      audioEngine.setChannelVolume(AudioChannel.music, 0.7);
      audioEngine.setChannelVolume(AudioChannel.sfx, 0.8);

      // Volumes should be set
      expect(audioEngine.getChannelVolume(AudioChannel.music), 0.7);
      expect(audioEngine.getChannelVolume(AudioChannel.sfx), 0.8);
    });

    test('Mute functionality', () async {
      final audioEngine = AudioEngine();

      // Plugins may be unavailable in unit-test/headless environments.
      try {
        await audioEngine.initialize();
      } catch (_) {}

      audioEngine.mute();
      expect(audioEngine.isMuted, true);

      audioEngine.unmute();
      expect(audioEngine.isMuted, false);
    });
  });

  group('Sprite System Tests', () {
    test('Sprite creation', () {
      final sprite = Sprite();
      expect(sprite, isNotNull);
      expect(sprite.visible, true);
      expect(sprite.opacity, 1.0);
    });

    test('Sprite properties', () {
      final sprite = Sprite(
        position: Vector3(100, 50, 0),
        rotation: math.pi / 4,
        scale: Vector3(2.0, 2.0, 1),
        renderSize: const Size(64, 64),
        flipX: true,
        flipY: false,
      );

      expect(sprite.position, Vector3(100, 50, 0));
      expect(sprite.rotation, math.pi / 4);
      expect(sprite.scale, Vector3(2.0, 2.0, 1));
      expect(sprite.renderSize, const Size(64, 64));
      expect(sprite.flipX, true);
      expect(sprite.flipY, false);
    });
  });
}
