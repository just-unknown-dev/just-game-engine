import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:flutter/material.dart';
import 'test_helpers.dart';

/// Basic sanity tests for the Just Game Engine
/// More comprehensive tests require API consistency fixes
void main() {
  // Initialize Flutter bindings for all tests
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Engine.resetInstance());

  group('Core Engine Sanity Tests', () {
    test('Engine can be instantiated', () {
      final engine = Engine();
      expect(engine, isNotNull);
    });

    test('Engine singleton works', () {
      final engine1 = Engine.instance;
      final engine2 = Engine.instance;
      expect(engine1, same(engine2));
    });

    test('Engine initializes successfully', () async {
      final engine = Engine();
      await engine.initialize();
      expect(engine.isInitialized, true);
    });

    test('Engine lifecycle methods work', () async {
      final engine = Engine();
      await engine.initialize();

      engine.start();
      expect(engine.isRunning, true);

      engine.pause();
      expect(engine.isPaused, true);

      engine.resume();
      expect(engine.isPaused, false);

      engine.stop();
      expect(engine.isRunning, false);
    });

    test('All subsystems are initialized', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.rendering, isNotNull);
      expect(engine.physics, isNotNull);
      expect(engine.input, isNotNull);
      expect(engine.animation, isNotNull);
      expect(engine.sceneEditor, isNotNull);
      expect(engine.world, isNotNull);
      expect(engine.assets, isNotNull);
      expect(engine.audio, isNotNull);
    });
  });

  group('Rendering System Tests', () {
    test('Can add renderables to rendering engine', () async {
      final engine = Engine();
      await engine.initialize();

      final circle = createTestCircle(radius: 50);
      engine.rendering.addRenderable(circle);

      expect(engine.rendering.renderables, contains(circle));
    });

    test('Can remove renderables', () async {
      final engine = Engine();
      await engine.initialize();

      final circle = createTestCircle();
      engine.rendering.addRenderable(circle);
      engine.rendering.removeRenderable(circle);

      expect(engine.rendering.renderables, isNot(contains(circle)));
    });

    test('Renderables are sorted by layer', () async {
      final engine = Engine();
      await engine.initialize();

      final obj1 = createTestCircle(layer: 2);
      final obj2 = createTestCircle(layer: 0);
      final obj3 = createTestCircle(layer: 1);

      engine.rendering.addRenderable(obj1);
      engine.rendering.addRenderable(obj2);
      engine.rendering.addRenderable(obj3);

      final renderables = engine.rendering.renderables;
      expect(renderables[0].layer, lessThanOrEqualTo(renderables[1].layer));
      expect(renderables[1].layer, lessThanOrEqualTo(renderables[2].layer));
    });

    test('Camera can be manipulated', () async {
      final engine = Engine();
      await engine.initialize();

      final camera = engine.rendering.camera;
      final initialPos = camera.position;

      camera.moveBy(const Offset(100, 50));
      expect(camera.position, isNot(equals(initialPos)));

      camera.reset();
      expect(camera.position, equals(initialPos));
    });

    test('Camera zoom works', () async {
      final engine = Engine();
      await engine.initialize();

      final camera = engine.rendering.camera;
      final initialZoom = camera.zoom;

      camera.zoomBy(2.0);
      expect(camera.zoom, initialZoom * 2.0);
    });
  });

  group('Physics System Tests', () {
    test('Can add physics bodies', () async {
      final engine = Engine();
      await engine.initialize();

      final body = PhysicsBody(position: const Offset(0, 0), radius: 30);

      engine.physics.addBody(body);
      expect(engine.physics.bodies, contains(body));
    });

    test('Can remove physics bodies', () async {
      final engine = Engine();
      await engine.initialize();

      final body = PhysicsBody(position: const Offset(0, 0), radius: 30);

      engine.physics.addBody(body);
      engine.physics.removeBody(body);
      expect(engine.physics.bodies, isNot(contains(body)));
    });

    test('Physics bodies have correct properties', () {
      final body = PhysicsBody(
        position: const Offset(100, 200),
        velocity: const Offset(50, 30),
        radius: 30,
        mass: 2.0,
        restitution: 0.8,
      );

      expect(body.position, const Offset(100, 200));
      expect(body.velocity, const Offset(50, 30));
      expect(body.radius, 30);
      expect(body.mass, 2.0);
      expect(body.restitution, 0.8);
    });
  });

  group('Animation System Tests', () {
    test('Animation system is initialized', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.animation, isNotNull);
      expect(engine.animation.animationCount, 0);
    });

    test('Can add animations to animation system', () async {
      final engine = Engine();
      await engine.initialize();

      final target = createTestCircle();
      final animation = RotationTween(
        target: target,
        start: 0,
        end: 3.14159 * 2,
        duration: 1.0,
      );

      engine.animation.addAnimation(animation);
      expect(engine.animation.animationCount, 1);
    });
  });

  group('Scene Graph Tests', () {
    test('Can create scenes', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('TestScene');
      expect(scene, isNotNull);
      expect(scene.name, 'TestScene');
    });

    test('Can add nodes to scene', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('TestScene');
      final node = SceneNode('TestNode');

      scene.addNode(node);
      expect(scene.findNode('TestNode'), same(node));
    });

    test('Parent-child hierarchy works', () {
      final parent = SceneNode('Parent');
      final child = SceneNode('Child');

      parent.addChild(child);

      expect(child.parent, same(parent));
      expect(parent.children, contains(child));
    });
  });

  group('ECS Tests', () {
    test('Can create entities', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity(name: 'TestEntity');
      expect(entity, isNotNull);
      expect(entity.name, 'TestEntity');
    });

    test('Can add components to entities', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity();
      final transform = TransformComponent(position: const Offset(0, 0));

      entity.addComponent(transform);
      expect(entity.hasComponent<TransformComponent>(), true);
    });

    test('Can query entities by component', () async {
      final engine = Engine();
      await engine.initialize();

      final entity1 = engine.world.createEntity();
      entity1.addComponent(TransformComponent(position: const Offset(0, 0)));
      entity1.addComponent(VelocityComponent(velocity: const Offset(10, 0)));

      final entity2 = engine.world.createEntity();
      entity2.addComponent(TransformComponent(position: const Offset(0, 0)));

      final movingEntities = engine.world.query([
        TransformComponent,
        VelocityComponent,
      ]);

      expect(movingEntities.length, 1);
      expect(movingEntities, contains(entity1));
    });
  });

  group('Particle System Tests', () {
    test('Can create particle emitters', () {
      final emitter = createTestEmitter();
      expect(emitter, isNotNull);
    });

    test('Particle emitter properties are correct', () {
      final emitter = createTestEmitter(
        maxParticles: 200,
        emissionRate: 50,
        particleLifetime: 2.0,
      );

      expect(emitter.maxParticles, 200);
      expect(emitter.emissionRate, 50);
      expect(emitter.particleLifetime, 2.0);
    });

    test('Particle preset effects can be created', () {
      final explosion = ParticleEffects.explosion(position: Offset.zero);
      expect(explosion, isNotNull);

      final fire = ParticleEffects.fire(position: Offset.zero);
      expect(fire, isNotNull);

      final sparkle = ParticleEffects.sparkle(position: Offset.zero);
      expect(sparkle, isNotNull);
    });
  });

  group('Input System Tests', () {
    test('Input subsystems exist', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.input, isNotNull);
      expect(engine.input.keyboard, isNotNull);
      expect(engine.input.mouse, isNotNull);
      expect(engine.input.touch, isNotNull);
      expect(engine.input.controller, isNotNull);
    });
  });

  group('Asset System Tests', () {
    test('Asset manager exists', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.assets, isNotNull);
    });

    test('Asset manager can provide cache stats', () {
      final assetManager = AssetManager();
      final stats = assetManager.getCacheStats();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('totalAssets'), true);
    });
  });

  group('Audio System Tests', () {
    test('Audio engine exists', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.audio, isNotNull);
    });

    test('Audio engine can be initialized', () {
      final audioEngine = AudioEngine();
      audioEngine.initialize();
      expect(audioEngine, isNotNull);
    });
  });

  group('Sprite System Tests', () {
    test('Can create sprites', () {
      final sprite = Sprite();
      expect(sprite, isNotNull);
      expect(sprite.visible, true);
      expect(sprite.opacity, 1.0);
    });

    test('Sprite properties can be set', () {
      final sprite = Sprite(
        position: const Offset(100, 50),
        rotation: 0.785398, // pi/4
        scale: 2.0,
        renderSize: const Size(64, 64),
        flipX: true,
        flipY: false,
      );

      expect(sprite.position, const Offset(100, 50));
      expect(sprite.scale, 2.0);
      expect(sprite.renderSize, const Size(64, 64));
      expect(sprite.flipX, true);
      expect(sprite.flipY, false);
    });
  });

  group('Integration Tests', () {
    test('Multiple systems work together', () async {
      final engine = Engine();
      await engine.initialize();
      engine.start();

      // Add renderable
      final circle = createTestCircle();
      engine.rendering.addRenderable(circle);

      // Add physics body
      final body = PhysicsBody(position: Offset.zero, radius: 30);
      engine.physics.addBody(body);

      // Create entity
      final entity = engine.world.createEntity();
      entity.addComponent(TransformComponent(position: Offset.zero));

      // Create scene
      final scene = engine.sceneEditor.createScene('IntegrationTest');
      final node = SceneNode('TestNode');
      scene.addNode(node);

      expect(engine.rendering.renderables.length, greaterThan(0));
      expect(engine.physics.bodies.length, greaterThan(0));
      expect(engine.world.entities.length, greaterThan(0));
      expect(scene.findNode('TestNode'), isNotNull);
    });
  });
}
