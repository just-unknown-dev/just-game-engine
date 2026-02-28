import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/animation/animation_system.dart' as anim;
import 'dart:math' as math;

/// Performance benchmarks for the Just Game Engine
///
/// These tests measure performance characteristics and ensure the engine
/// can handle typical game scenarios at acceptable frame rates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Engine.resetInstance());

  group('Performance Tests', () {
    test('Engine initialization performance', () async {
      final stopwatch = Stopwatch()..start();

      final engine = Engine();
      await engine.initialize();

      stopwatch.stop();

      debugPrint(
        'Engine initialization took: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
      ); // Should init under 1 second
    });

    test('Rendering performance with 100 objects', () async {
      final engine = Engine();
      await engine.initialize();

      // Add 100 renderables
      for (int i = 0; i < 100; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.blue,
            position: Offset(i * 10.0, i * 5.0),
          ),
        );
      }

      expect(engine.rendering.renderables.length, 100);

      // Measure time to sort/process all renderables
      final stopwatch = Stopwatch()..start();

      // Simulate multiple frames
      for (int i = 0; i < 60; i++) {
        final _ = engine.rendering.renderables;
      }

      stopwatch.stop();

      debugPrint('100 objects, 60 frames: ${stopwatch.elapsedMilliseconds}ms');
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
      ); // Should be very fast
    });

    test('Rendering performance with 1000 objects', () async {
      final engine = Engine();
      await engine.initialize();

      final stopwatch = Stopwatch()..start();

      // Add 1000 renderables
      for (int i = 0; i < 1000; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.blue,
            position: Offset((i % 50) * 10.0, (i ~/ 50) * 10.0),
          ),
        );
      }

      stopwatch.stop();

      expect(engine.rendering.renderables.length, 1000);
      debugPrint(
        'Added 1000 renderables in: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('Animation system performance with 50 animations', () async {
      final engine = Engine();
      await engine.initialize();

      final targets = List.generate(
        50,
        (i) => CircleRenderable(
          radius: 10,
          fillColor: Colors.blue,
          position: Offset(i * 10.0, 0),
        ),
      );

      final stopwatch = Stopwatch()..start();

      // Create 50 animations
      for (final target in targets) {
        final animation = anim.RotationTween(
          target: target,
          start: 0,
          end: math.pi * 2,
          duration: 1.0,
          loop: true,
        );
        animation.play();
        engine.animation.addAnimation(animation);
      }

      stopwatch.stop();

      debugPrint(
        'Created 50 animations in: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(engine.animation.animationCount, 50);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Animation update performance', () async {
      final engine = Engine();
      await engine.initialize();

      // Create 100 animations
      for (int i = 0; i < 100; i++) {
        final target = CircleRenderable(radius: 10, fillColor: Colors.blue);
        final animation = anim.RotationTween(
          target: target,
          start: 0,
          end: math.pi * 2,
          duration: 1.0,
          loop: true,
        );
        animation.play();
        engine.animation.addAnimation(animation);
      }

      final stopwatch = Stopwatch()..start();

      // Update 100 animations for 60 frames
      for (int i = 0; i < 60; i++) {
        engine.animation.update(0.016); // ~60 FPS
      }

      stopwatch.stop();

      debugPrint(
        '100 animations, 60 updates: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('Sprite animation performance', () async {
      final stopwatch = Stopwatch()..start();

      // Create 50 sprite animations
      final animations = <anim.SpriteAnimation>[];
      for (int i = 0; i < 50; i++) {
        final sprite = Sprite();
        final frames = List.generate(
          8,
          (j) => Rect.fromLTWH(j * 64.0, 0, 64, 64),
        );

        final animation = anim.SpriteAnimation(
          sprite: sprite,
          frames: frames,
          duration: 1.0,
          loop: true,
        );
        animation.play();
        animations.add(animation);
      }

      // Update all animations for 60 frames
      for (int i = 0; i < 60; i++) {
        for (final anim in animations) {
          anim.update(0.016);
        }
      }

      stopwatch.stop();

      debugPrint(
        '50 sprite animations, 60 frames: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Physics engine performance with 50 bodies', () async {
      final engine = Engine();
      await engine.initialize();

      // Add 50 physics bodies
      for (int i = 0; i < 50; i++) {
        engine.physics.addBody(
          PhysicsBody(
            position: Offset(i * 20.0, i * 10.0),
            velocity: Offset(
              (i % 2 == 0 ? 1 : -1) * 50.0,
              (i % 3 == 0 ? 1 : -1) * 30.0,
            ),
            shape: CircleShape(15),
            mass: 1.0,
          ),
        );
      }

      expect(engine.physics.bodies.length, 50);

      final stopwatch = Stopwatch()..start();

      // Simulate 60 frames of physics
      for (int i = 0; i < 60; i++) {
        engine.physics.update(0.016);
      }

      stopwatch.stop();

      debugPrint(
        '50 physics bodies, 60 updates: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('Physics collision detection performance', () async {
      final engine = Engine();
      await engine.initialize();

      // Create a dense cluster of bodies
      for (int i = 0; i < 30; i++) {
        for (int j = 0; j < 30; j++) {
          engine.physics.addBody(
            PhysicsBody(
              position: Offset(i * 40.0, j * 40.0),
              velocity: Offset.zero,
              shape: CircleShape(15),
            ),
          );
        }
      }

      expect(engine.physics.bodies.length, 900);

      final stopwatch = Stopwatch()..start();

      // One physics update with many potential collisions
      engine.physics.update(0.016);

      stopwatch.stop();

      debugPrint(
        '900 bodies collision check: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
      ); // Should handle dense scenarios
    });

    test('Particle system performance with 500 particles', () async {
      final emitter = ParticleEmitter(
        position: Offset.zero,
        maxParticles: 500,
        emissionRate: 100, // 100 particles per second
        particleLifetime: 5.0,
      );

      // Emitter starts automatically

      final stopwatch = Stopwatch()..start();

      // Emit and update particles for 5 seconds at 60fps
      for (int i = 0; i < 300; i++) {
        emitter.update(0.016);
      }

      stopwatch.stop();

      debugPrint(
        'Particle system (5s simulation): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('Active particles: ${emitter.particleCount}');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('Scene graph update performance with deep hierarchy', () async {
      final engine = Engine();
      await engine.initialize();

      final scene = engine.sceneEditor.createScene('PerfTest');

      // Create a deep hierarchy (10 levels, 5 children each)
      SceneNode createHierarchy(int depth, String prefix) {
        final node = SceneNode('$prefix-$depth');
        if (depth > 0) {
          for (int i = 0; i < 5; i++) {
            node.addChild(createHierarchy(depth - 1, '$prefix-$i'));
          }
        }
        return node;
      }

      final rootNode = createHierarchy(5, 'root');
      scene.addNode(rootNode);

      final stopwatch = Stopwatch()..start();

      // Scene graph transforms propagate automatically
      // Test accessing world positions to ensure transforms are computed
      for (int i = 0; i < 60; i++) {
        void visitNodes(SceneNode node) {
          final _ = node.worldPosition; // Access world position
          for (final child in node.children) {
            visitNodes(child);
          }
        }

        visitNodes(rootNode);
      }

      stopwatch.stop();

      debugPrint(
        'Deep hierarchy (5 levels) 60 updates: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('ECS query performance with 1000 entities', () async {
      final engine = Engine();
      await engine.initialize();

      // Create 1000 entities with various components
      for (int i = 0; i < 1000; i++) {
        final entity = engine.world.createEntity(name: 'Entity_$i');
        entity.addComponent(TransformComponent(position: Offset(i * 1.0, 0)));

        if (i % 2 == 0) {
          entity.addComponent(VelocityComponent(velocity: const Offset(10, 0)));
        }

        if (i % 3 == 0) {
          entity.addComponent(HealthComponent(maxHealth: 100));
        }
      }

      final stopwatch = Stopwatch()..start();

      // Perform 100 queries
      for (int i = 0; i < 100; i++) {
        final _ = engine.world.query([TransformComponent, VelocityComponent]);
      }

      stopwatch.stop();

      debugPrint(
        '1000 entities, 100 queries: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('ECS system update performance', () async {
      final engine = Engine();
      await engine.initialize();

      // Add systems
      engine.world.addSystem(MovementSystem());
      engine.world.addSystem(RenderSystem());
      engine.world.addSystem(PhysicsSystem());

      // Create 500 entities with components
      for (int i = 0; i < 500; i++) {
        final entity = engine.world.createEntity();
        entity.addComponent(TransformComponent(position: Offset(i * 1.0, 0)));
        entity.addComponent(VelocityComponent(velocity: const Offset(10, 5)));
        entity.addComponent(
          RenderableComponent(
            renderable: CircleRenderable(radius: 5, fillColor: Colors.blue),
          ),
        );
      }

      final stopwatch = Stopwatch()..start();

      // Update all systems for 60 frames
      for (int i = 0; i < 60; i++) {
        engine.world.update(0.016);
      }

      stopwatch.stop();

      debugPrint(
        '500 entities, 3 systems, 60 updates: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('Memory usage - renderables', () async {
      final engine = Engine();
      await engine.initialize();

      // Add and remove renderables repeatedly
      for (int cycle = 0; cycle < 10; cycle++) {
        for (int i = 0; i < 100; i++) {
          engine.rendering.addRenderable(
            CircleRenderable(
              radius: 10,
              fillColor: Colors.blue,
              position: Offset(i * 1.0, 0),
            ),
          );
        }

        engine.rendering.clear();
      }

      expect(engine.rendering.renderables.length, 0);
    });

    test('Combined stress test - full engine load', () async {
      final engine = Engine();
      await engine.initialize();

      // Add 200 renderables
      for (int i = 0; i < 200; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.primaries[i % Colors.primaries.length],
            position: Offset((i % 20) * 30.0, (i ~/ 20) * 30.0),
          ),
        );
      }

      // Add 50 animations
      for (int i = 0; i < 50; i++) {
        final target = engine.rendering.renderables[i];
        final animation = anim.RotationTween(
          target: target,
          start: 0,
          end: math.pi * 2,
          duration: 2.0,
          loop: true,
        );
        animation.play();
        engine.animation.addAnimation(animation);
      }

      // Add 30 physics bodies
      for (int i = 0; i < 30; i++) {
        engine.physics.addBody(
          PhysicsBody(
            position: Offset(i * 50.0, i * 30.0),
            velocity: Offset(
              (i % 2 == 0 ? 1 : -1) * 50.0,
              (i % 3 == 0 ? 1 : -1) * 30.0,
            ),
            shape: CircleShape(15),
          ),
        );
      }

      // Add 100 ECS entities
      for (int i = 0; i < 100; i++) {
        final entity = engine.world.createEntity();
        entity.addComponent(TransformComponent(position: Offset(i * 1.0, 0)));
        entity.addComponent(VelocityComponent(velocity: const Offset(10, 0)));
      }

      // Add particle emitter
      final emitter = ParticleEmitter(
        position: Offset.zero,
        maxParticles: 200,
        emissionRate: 50,
        particleLifetime: 2.0,
      );
      // Emitter starts automatically

      final stopwatch = Stopwatch()..start();

      // Simulate 60 frames of full engine operation
      for (int frame = 0; frame < 60; frame++) {
        engine.animation.update(0.016);
        engine.physics.update(0.016);
        engine.world.update(0.016);
        emitter.update(0.016);
      }

      stopwatch.stop();

      debugPrint(
        'STRESS TEST - Full engine (60 frames): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  - 200 renderables');
      debugPrint('  - 50 animations');
      debugPrint('  - 30 physics bodies');
      debugPrint('  - 100 ECS entities');
      debugPrint(
        '  - 1 particle emitter (~${emitter.particleCount} particles)',
      );

      // Should maintain 60 FPS (16.67ms per frame)
      // 60 frames should take less than 1 second in tests
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));

      final avgFrameTime = stopwatch.elapsedMilliseconds / 60.0;
      debugPrint(
        '  - Average frame time: ${avgFrameTime.toStringAsFixed(2)}ms',
      );
    });

    test('Camera transformation performance', () async {
      final engine = Engine();
      await engine.initialize();

      final camera = engine.rendering.camera;

      final stopwatch = Stopwatch()..start();

      // Perform 10000 camera operations
      for (int i = 0; i < 10000; i++) {
        camera.moveBy(const Offset(1, 1));
        camera.zoomBy(1.01);
        final _ = camera.position;
        final _ = camera.zoom;
      }

      stopwatch.stop();

      debugPrint('10000 camera operations: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Easing function performance', () {
      final stopwatch = Stopwatch()..start();

      // Test all easing functions 10000 times each
      for (int i = 0; i < 10000; i++) {
        final t = i / 10000.0;
        anim.Easings.linear(t);
        anim.Easings.easeInQuad(t);
        anim.Easings.easeOutQuad(t);
        anim.Easings.easeInOutQuad(t);
        anim.Easings.easeInCubic(t);
        anim.Easings.easeOutCubic(t);
        anim.Easings.easeInOutCubic(t);
        anim.Easings.easeInSine(t);
        anim.Easings.easeOutSine(t);
        anim.Easings.easeInOutSine(t);
      }

      stopwatch.stop();

      debugPrint(
        '10000 iterations of 10 easings: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });
  });

  group('Scalability Tests', () {
    test('Rendering scales linearly', () async {
      final engine = Engine();
      if (!engine.isInitialized) {
        try {
          await engine.initialize();
        } catch (e) {
          // Ignore audio plugin errors in tests
          if (!e.toString().contains('MissingPluginException')) {
            rethrow;
          }
        }
      }

      final times = <int, int>{};

      for (final count in [10, 50, 100, 200, 500]) {
        engine.rendering.clear();

        for (int i = 0; i < count; i++) {
          engine.rendering.addRenderable(
            CircleRenderable(
              radius: 10,
              fillColor: Colors.blue,
              position: Offset(i * 1.0, 0),
            ),
          );
        }

        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 60; i++) {
          final _ = engine.rendering.renderables;
        }
        stopwatch.stop();

        times[count] = stopwatch.elapsedMilliseconds;
        debugPrint('$count renderables: ${times[count]}ms');
      }

      // Verify it scales reasonably
      // If operations are too fast to measure (0ms), just verify largest count is fast
      if (times[50]! == 0) {
        expect(times[500]!, lessThan(50)); // Should still be fast even at 500
      } else {
        expect(
          times[500]! < times[50]! * 10,
          true,
        ); // 500 should be < 10x slower than 50
      }
    });

    test('Animation system scales linearly', () async {
      final engine = Engine();
      if (!engine.isInitialized) {
        try {
          await engine.initialize();
        } catch (e) {
          // Ignore audio plugin errors in tests
          if (!e.toString().contains('MissingPluginException')) {
            rethrow;
          }
        }
      }

      final times = <int, int>{};

      for (final count in [10, 25, 50, 100]) {
        engine.animation.clear();

        for (int i = 0; i < count; i++) {
          final target = CircleRenderable(radius: 10, fillColor: Colors.blue);
          final animation = anim.RotationTween(
            target: target,
            start: 0,
            end: math.pi * 2,
            duration: 1.0,
            loop: true,
          );
          animation.play();
          engine.animation.addAnimation(animation);
        }

        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 60; i++) {
          engine.animation.update(0.016);
        }
        stopwatch.stop();

        times[count] = stopwatch.elapsedMilliseconds;
        debugPrint('$count animations: ${times[count]}ms');
      }

      // Verify scaling
      // If operations are too fast to measure (0ms), just verify largest count is fast
      if (times[10]! == 0) {
        expect(times[100]!, lessThan(100)); // Should still be fast even at 100
      } else {
        expect(
          times[100]! < times[10]! * 15,
          true,
        ); // 100 should be < 15x slower than 10
      }
    });
  });
}
