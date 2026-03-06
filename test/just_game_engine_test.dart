import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/animation/animation_system.dart' as anim;
import 'dart:math' as math;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Engine.resetInstance());

  group('Core Engine Tests', () {
    test('Engine initialization', () async {
      final engine = Engine();
      expect(engine.isInitialized, false);
      expect(engine.isRunning, false);

      await engine.initialize();
      expect(engine.isInitialized, true);
      expect(engine.isRunning, false);
    });

    test('Engine lifecycle', () async {
      final engine = Engine();
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

    test('Engine singleton instance', () {
      final engine1 = Engine.instance;
      final engine2 = Engine.instance;
      expect(engine1, same(engine2));
    });
  });

  group('Rendering Engine Tests', () {
    test('Add and remove renderables', () async {
      final engine = Engine();
      await engine.initialize();

      final circle = CircleRenderable(
        radius: 50,
        fillColor: Colors.red,
        position: const Offset(0, 0),
      );

      engine.rendering.addRenderable(circle);
      expect(engine.rendering.renderables, contains(circle));

      engine.rendering.removeRenderable(circle);
      expect(engine.rendering.renderables, isNot(contains(circle)));
    });

    test('Layer sorting', () async {
      final engine = Engine();
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

  group('Animation System Tests', () {
    test('PositionTween animation', () async {
      final engine = Engine();
      await engine.initialize();

      final target = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        position: const Offset(0, 0),
      );

      final animation = anim.PositionTween(
        target: target,
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        duration: 1.0,
      );

      animation.play();
      expect(animation.isPaused, false);

      // Simulate halfway through animation
      animation.update(0.5);
      expect(animation.normalizedTime, closeTo(0.5, 0.01));
    });

    test('RotationTween animation', () async {
      final engine = Engine();
      await engine.initialize();

      final target = CircleRenderable(radius: 10, fillColor: Colors.blue);

      final animation = anim.RotationTween(
        target: target,
        start: 0,
        end: math.pi * 2,
        duration: 1.0,
      );

      animation.play();
      animation.update(1.0);
      expect(animation.isComplete, true);
      expect(target.rotation, closeTo(math.pi * 2, 0.01));
    });

    test('ScaleTween animation', () async {
      final engine = Engine();
      await engine.initialize();

      final target = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        scale: 1.0,
      );

      final animation = anim.ScaleTween(
        target: target,
        start: 1.0,
        end: 2.0,
        duration: 1.0,
      );

      animation.play();
      animation.update(1.0);
      expect(target.scale, closeTo(2.0, 0.01));
    });

    test('OpacityTween animation', () async {
      final engine = Engine();
      await engine.initialize();

      final target = CircleRenderable(
        radius: 10,
        fillColor: Colors.blue,
        opacity: 1.0,
      );

      final animation = anim.OpacityTween(
        target: target,
        start: 1.0,
        end: 0.0,
        duration: 1.0,
      );

      animation.play();
      animation.update(1.0);
      expect(target.opacity, closeTo(0.0, 0.01));
    });

    test('Animation loop', () async {
      final target = CircleRenderable(radius: 10, fillColor: Colors.blue);

      final animation = anim.RotationTween(
        target: target,
        start: 0,
        end: math.pi * 2,
        duration: 1.0,
        loop: true,
      );

      animation.play();
      animation.update(1.5);
      expect(animation.isComplete, false);
      expect(animation.currentTime, closeTo(0.5, 0.01));
    });

    test('Animation speed control', () async {
      final target = CircleRenderable(radius: 10, fillColor: Colors.blue);

      final animation = anim.RotationTween(
        target: target,
        start: 0,
        end: math.pi * 2,
        duration: 1.0,
      );

      animation.speed = 2.0;
      animation.play();
      animation.update(0.5);
      expect(animation.currentTime, closeTo(1.0, 0.01));
    });

    test('AnimationSequence', () async {
      final target = CircleRenderable(radius: 10, fillColor: Colors.blue);

      final anim1 = anim.RotationTween(
        target: target,
        start: 0,
        end: math.pi,
        duration: 1.0,
      );

      final anim2 = anim.ScaleTween(
        target: target,
        start: 1.0,
        end: 2.0,
        duration: 1.0,
      );

      final sequence = anim.AnimationSequence(animations: [anim1, anim2]);

      sequence.play();
      expect(sequence.duration, 2.0);
    });

    test('AnimationGroup parallel execution', () async {
      final target = CircleRenderable(radius: 10, fillColor: Colors.blue);

      final anim1 = anim.RotationTween(
        target: target,
        start: 0,
        end: math.pi,
        duration: 1.0,
      );

      final anim2 = anim.ScaleTween(
        target: target,
        start: 1.0,
        end: 2.0,
        duration: 0.5,
      );

      final group = anim.AnimationGroup(animations: [anim1, anim2]);

      expect(group.duration, 1.0); // Max of both durations
    });

    test('Sprite animation frame cycling', () async {
      final sprite = Sprite();
      final frames = [
        const Rect.fromLTWH(0, 0, 64, 64),
        const Rect.fromLTWH(64, 0, 64, 64),
        const Rect.fromLTWH(128, 0, 64, 64),
        const Rect.fromLTWH(192, 0, 64, 64),
      ];

      final animation = anim.SpriteAnimation(
        sprite: sprite,
        frames: frames,
        duration: 1.0,
      );

      animation.play();

      // At start
      expect(animation.currentFrame, 0);

      // At 25%
      animation.update(0.25);
      expect(animation.currentFrame, 1);

      // At 50%
      animation.update(0.25);
      expect(animation.currentFrame, 2);
    });
  });

  group('Physics Engine Tests', () {
    test('Add and remove physics bodies', () async {
      final engine = Engine();
      await engine.initialize();

      final body = PhysicsBody(
        position: const Offset(0, 0),
        shape: CircleShape(30),
      );

      engine.physics.addBody(body);
      expect(engine.physics.bodies, contains(body));

      engine.physics.removeBody(body);
      expect(engine.physics.bodies, isNot(contains(body)));
    });

    test('Physics body velocity integration', () async {
      final engine = Engine();
      await engine.initialize();

      final body = PhysicsBody(
        position: const Offset(0, 0),
        velocity: const Offset(100, 0),
        shape: CircleShape(30),
        drag: 0.0,
      );

      engine.physics.addBody(body);
      final initialPos = body.position;
      engine.physics.update(1.0); // 1 second

      expect(body.position.dx, closeTo(initialPos.dx + 100, 0.01));
    });

    test('Collision detection', () async {
      final engine = Engine();
      await engine.initialize();

      final body1 = PhysicsBody(
        position: const Offset(0, 0),
        shape: CircleShape(30),
      );

      final body2 = PhysicsBody(
        position: const Offset(50, 0),
        shape: CircleShape(30),
      );

      engine.physics.addBody(body1);
      engine.physics.addBody(body2);

      final distance = (body1.position - body2.position).distance;
      final combinedRadius =
          (body1.shape as CircleShape).radius +
          (body2.shape as CircleShape).radius;
      expect(distance < combinedRadius, true);
    });

    test('Physics body mass and restitution', () async {
      final body = PhysicsBody(
        position: const Offset(0, 0),
        shape: CircleShape(30),
        mass: 2.0,
        restitution: 0.8,
      );

      expect(body.mass, 2.0);
      expect(body.restitution, 0.8);
    });

    test('Gravity simulation', () async {
      final engine = Engine();
      await engine.initialize();

      final body = PhysicsBody(
        position: const Offset(0, 0),
        velocity: Offset.zero,
        shape: CircleShape(30),
      );

      engine.physics.gravity = const Offset(0, 100);
      engine.physics.addBody(body);

      final initialY = body.position.dy;
      engine.physics.update(1.0);

      // Body should have fallen due to gravity
      expect(body.position.dy > initialY, true);
    });
  });

  group('Particle System Tests', () {
    test('ParticleEmitter creation', () {
      final emitter = ParticleEmitter(
        position: const Offset(0, 0),
        maxParticles: 100,
        emissionRate: 30,
        particleLifetime: 2.0,
      );

      expect(emitter.position, const Offset(0, 0));
      expect(emitter.emissionRate, 30);
      expect(emitter.particleLifetime, 2.0);
    });

    test('Particle emission', () {
      final emitter = ParticleEmitter(
        position: const Offset(0, 0),
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
        position: const Offset(0, 0),
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
      final explosion = ParticleEffects.explosion(position: Offset.zero);
      expect(explosion.emissionRate, greaterThan(0));

      final fire = ParticleEffects.fire(position: Offset.zero);
      expect(fire.emissionRate, greaterThan(0));

      final sparkle = ParticleEffects.sparkle(position: Offset.zero);
      expect(sparkle.emissionRate, greaterThan(0));
    });
  });

  group('Scene Graph Tests', () {
    test('Create scene', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('TestScene');
      expect(scene, isNotNull);
      expect(scene.name, 'TestScene');
    });

    test('Add node to scene', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('TestScene');
      final node = SceneNode('TestNode');

      scene.addNode(node);
      expect(scene.findNode('TestNode'), same(node));
    });

    test('Parent-child hierarchy', () {
      final parent = SceneNode('Parent');
      final child = SceneNode('Child');

      parent.addChild(child);

      expect(child.parent, same(parent));
      expect(parent.children, contains(child));
    });

    test('Transform propagation', () {
      final parent = SceneNode('Parent')..localPosition = const Offset(100, 0);
      final child = SceneNode('Child')..localPosition = const Offset(50, 0);

      parent.addChild(child);
      // Transform propagation happens automatically in scene graph

      expect(child.worldPosition.dx, closeTo(150, 0.01));
    });

    test('Find node by name', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('TestScene');
      final node = SceneNode('TargetNode');
      scene.addNode(node);

      final found = scene.findNode('TargetNode');
      expect(found, same(node));
    });
  });

  group('Entity-Component System Tests', () {
    test('Create entity', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity(name: 'TestEntity');
      expect(entity, isNotNull);
      expect(entity.name, 'TestEntity');
    });

    test('Add components to entity', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity();
      final transform = TransformComponent(position: const Offset(0, 0));

      entity.addComponent(transform);
      expect(entity.hasComponent<TransformComponent>(), true);
      expect(entity.getComponent<TransformComponent>(), same(transform));
    });

    test('Remove component from entity', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity();
      final transform = TransformComponent(position: const Offset(0, 0));

      entity.addComponent(transform);
      entity.removeComponent<TransformComponent>();
      expect(entity.hasComponent<TransformComponent>(), false);
    });

    test('Query entities by component', () async {
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

    test('Destroy entity', () async {
      final engine = Engine();
      await engine.initialize();

      final entity = engine.world.createEntity(name: 'ToDestroy');

      engine.world.destroyEntity(entity);
      expect(engine.world.findEntityByName('ToDestroy'), isNull);
    });

    test('Add system to world', () async {
      final engine = Engine();
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
    test('InputManager initialization', () async {
      final engine = Engine();
      await engine.initialize();

      expect(engine.input, isNotNull);
      expect(engine.input.keyboard, isNotNull);
      expect(engine.input.mouse, isNotNull);
      expect(engine.input.touch, isNotNull);
      expect(engine.input.controller, isNotNull);
    });

    test('Keyboard state management', () async {
      final engine = Engine();
      await engine.initialize();

      final keyboard = engine.input.keyboard;
      // Keyboard is initialized
      expect(keyboard, isNotNull);
    });

    test('Mouse state management', () async {
      final engine = Engine();
      await engine.initialize();

      final mouse = engine.input.mouse;
      expect(mouse.position, Offset.zero);
    });

    test('Touch state management', () async {
      final engine = Engine();
      await engine.initialize();

      final touch = engine.input.touch;
      expect(touch.touches, isEmpty);
    });
  });

  group('Audio Engine Tests', () {
    test('AudioEngine initialization', () {
      final audioEngine = AudioEngine();
      audioEngine.initialize();
      expect(audioEngine, isNotNull);
    });

    test('Volume control', () {
      final audioEngine = AudioEngine();
      audioEngine.initialize();

      audioEngine.setMasterVolume(0.5);
      audioEngine.setChannelVolume(AudioChannel.music, 0.7);
      audioEngine.setChannelVolume(AudioChannel.sfx, 0.8);

      // Volumes should be set
      expect(audioEngine.getChannelVolume(AudioChannel.music), 0.7);
      expect(audioEngine.getChannelVolume(AudioChannel.sfx), 0.8);
    });

    test('Mute functionality', () {
      final audioEngine = AudioEngine();
      audioEngine.initialize();

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
        position: const Offset(100, 50),
        rotation: math.pi / 4,
        scale: 2.0,
        renderSize: const Size(64, 64),
        flipX: true,
        flipY: false,
      );

      expect(sprite.position, const Offset(100, 50));
      expect(sprite.rotation, math.pi / 4);
      expect(sprite.scale, 2.0);
      expect(sprite.renderSize, const Size(64, 64));
      expect(sprite.flipX, true);
      expect(sprite.flipY, false);
    });
  });
}
