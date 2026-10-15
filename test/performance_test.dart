import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Performance benchmarks for the Just Game Engine
///
/// These tests measure performance characteristics and ensure the engine
/// can handle typical game scenarios at acceptable frame rates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test makes its own engine and disposes it when done.

  group('Performance Tests', () {
    test('Engine initialization performance', () async {
      final stopwatch = Stopwatch()..start();

      final engine = Engine();
      addTearDown(engine.dispose);
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
      addTearDown(engine.dispose);
      await engine.initialize();

      // Add 100 renderables
      for (int i = 0; i < 100; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.blue,
            position: Vector3(i * 10.0, i * 5.0, 0),
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
      addTearDown(engine.dispose);
      await engine.initialize();

      final stopwatch = Stopwatch()..start();

      // Add 1000 renderables
      for (int i = 0; i < 1000; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.blue,
            position: Vector3((i % 50) * 10.0, (i ~/ 50) * 10.0, 0),
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

    test('Physics engine performance with 50 bodies', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      // Add 50 physics bodies
      for (int i = 0; i < 50; i++) {
        engine.physics.addBody(
          PhysicsBody(
            position: Vector2(i * 20.0, i * 10.0),
            velocity: Vector2(
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
      addTearDown(engine.dispose);
      await engine.initialize();

      // Create a dense cluster of bodies
      for (int i = 0; i < 30; i++) {
        for (int j = 0; j < 30; j++) {
          engine.physics.addBody(
            PhysicsBody(
              position: Vector2(i * 40.0, j * 40.0),
              velocity: Vector2.zero(),
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
        position: null,
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

    test('ECS query performance with 1000 entities', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      // Create 1000 entities with various components
      for (int i = 0; i < 1000; i++) {
        final entity = engine.world.createEntity(name: 'Entity_$i');
        entity.addComponent(
          TransformComponent(position: Vector3(i * 1.0, 0, 0)),
        );

        if (i % 2 == 0) {
          entity.addComponent(VelocityComponent(velocity: Vector3(10, 0, 0)));
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
      addTearDown(engine.dispose);
      await engine.initialize();

      // Add systems
      engine.world.addSystem(MovementSystem());
      engine.world.addSystem(RenderSystem());
      engine.world.addSystem(PhysicsSystem(engine.physics));

      // Create 500 entities with components
      for (int i = 0; i < 500; i++) {
        final entity = engine.world.createEntity();
        entity.addComponent(
          TransformComponent(position: Vector3(i * 1.0, 0, 0)),
        );
        entity.addComponent(VelocityComponent(velocity: Vector3(10, 5, 0)));
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
      addTearDown(engine.dispose);
      await engine.initialize();

      // Add and remove renderables repeatedly
      for (int cycle = 0; cycle < 10; cycle++) {
        for (int i = 0; i < 100; i++) {
          engine.rendering.addRenderable(
            CircleRenderable(
              radius: 10,
              fillColor: Colors.blue,
              position: Vector3(i * 1.0, 0, 0),
            ),
          );
        }

        engine.rendering.clear();
      }

      expect(engine.rendering.renderables.length, 0);
    });

    test('Combined stress test - full engine load', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      // Add 200 renderables
      for (int i = 0; i < 200; i++) {
        engine.rendering.addRenderable(
          CircleRenderable(
            radius: 10,
            fillColor: Colors.primaries[i % Colors.primaries.length],
            position: Vector3((i % 20) * 30.0, (i ~/ 20) * 30.0, 0),
          ),
        );
      }

      // Add 30 physics bodies
      for (int i = 0; i < 30; i++) {
        engine.physics.addBody(
          PhysicsBody(
            position: Vector2(i * 50.0, i * 30.0),
            velocity: Vector2(
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
        entity.addComponent(
          TransformComponent(position: Vector3(i * 1.0, 0, 0)),
        );
        entity.addComponent(VelocityComponent(velocity: Vector3(10, 0, 0)));
      }

      // Add particle emitter
      final emitter = ParticleEmitter(
        position: null,
        maxParticles: 200,
        emissionRate: 50,
        particleLifetime: 2.0,
      );
      // Emitter starts automatically

      final stopwatch = Stopwatch()..start();

      // Simulate 60 frames of full engine operation
      for (int frame = 0; frame < 60; frame++) {
        engine.physics.update(0.016);
        engine.world.update(0.016);
        emitter.update(0.016);
      }

      stopwatch.stop();

      debugPrint(
        'STRESS TEST - Full engine (60 frames): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  - 200 renderables');
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
      addTearDown(engine.dispose);
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
        Easings.linear(t);
        Easings.easeInQuad(t);
        Easings.easeOutQuad(t);
        Easings.easeInOutQuad(t);
        Easings.easeInCubic(t);
        Easings.easeOutCubic(t);
        Easings.easeInOutCubic(t);
        Easings.easeInSine(t);
        Easings.easeOutSine(t);
        Easings.easeInOutSine(t);
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
      addTearDown(engine.dispose);
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
              position: Vector3(i * 1.0, 0, 0),
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
  });

  // ── Stats-driven frame budget benchmarks ──────────────────────────────────
  // These tests exercise the live diagnostics APIs and assert that real update
  // cycles remain within the 60 Hz budget under representative loads.  They
  // serve as a CI gate: if a regression bloats a hot path enough to blow the
  // budget, the test fails with a concrete timing figure.
  group('Frame budget benchmarks (stats API)', () {
    test('scheduler completes a full update cycle within 16.67ms', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      // Warm up to stabilise timings (JIT, first-frame overhead).
      for (int i = 0; i < 5; i++) {
        engine.physics.update(0.016);
        engine.world.update(0.016);
      }

      // Drive one full update cycle through the authoritative scheduler.
      engine.systemManager.runUpdateCycle(1 / 60);

      final stats = engine.performanceStats;
      final lastUpdateMs = stats['lastUpdateMs'] as double;
      final isOverBudget = stats['isOverBudget'] as bool;

      debugPrint(
        'Scheduler update cycle: ${lastUpdateMs.toStringAsFixed(2)} ms  '
        '(budget remaining: ${(stats['budgetRemainingMs'] as double).toStringAsFixed(2)} ms)',
      );

      expect(
        isOverBudget,
        isFalse,
        reason:
            'Engine update cycle took ${lastUpdateMs.toStringAsFixed(2)} ms — '
            'exceeded the 16.67 ms / 60 Hz frame budget.',
      );
    });

    test('scheduler records timings for all registered tasks', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      // Drive one update cycle directly through the scheduler so taskTimesMs
      // is populated without depending on the GameLoop clock accumulator.
      engine.systemManager.runUpdateCycle(1 / 60);

      final scheduler =
          engine.performanceStats['scheduler'] as Map<String, dynamic>;
      final taskTimes = scheduler['taskTimesMs'] as Map<String, double>;

      // Tasks registered in Engine._registerSystems must be present. No
      // standalone 'physics' task — PhysicsSystem steps engine.physics
      // inline from within the 'ecs' task instead (see Engine.physics'
      // doc comment for why).
      // Audio is a frame task: it places sounds once the frame has moved
      // everything.
      const expectedTasks = ['input', 'camera', 'parallax', 'ecs'];
      expect(taskTimes.keys, containsAll(expectedTasks));
      expect(
        scheduler['updateTaskCount'],
        greaterThanOrEqualTo(expectedTasks.length),
      );
    });

    test(
      'physics stats stay coherent after 60 steps with moving bodies',
      () async {
        final engine = Engine();
        addTearDown(engine.dispose);
        await engine.initialize();

        for (int i = 0; i < 20; i++) {
          engine.physics.addBody(
            PhysicsBody(
              position: Vector2(i * 40.0, 0),
              velocity: Vector2(10, 5),
              shape: CircleShape(12),
              mass: 1.0,
            ),
          );
        }

        for (int i = 0; i < 60; i++) {
          engine.physics.update(0.016);
        }

        final ps = engine.physics.stats;
        expect(ps['bodyCount'], 20);
        expect(ps['lastStepMs'], isA<double>());
        // Incremental broadphase: dirty count must not exceed total body count.
        expect(
          ps['broadphaseDirtyBodies'] as int,
          lessThanOrEqualTo(ps['bodyCount'] as int),
        );
      },
    );

    test('rendering stats confirm spatial index reuse on static scene', () async {
      // Drive RenderingEngine directly (same pattern used in performance_instrumentation_test).
      final rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(800, 600));
      rendering.initialize();

      // Add 250 renderables to activate the quadtree path (threshold = 200).
      for (int i = 0; i < 250; i++) {
        rendering.addRenderable(
          CircleRenderable(
            radius: 8,
            fillColor: Colors.green,
            position: Vector3((i % 25) * 30.0, (i ~/ 25) * 30.0, 0),
          ),
        );
      }

      // First pass seeds the spatial index.
      final rec1 = ui.PictureRecorder();
      rendering.render(Canvas(rec1), const Size(800, 600));
      rec1.endRecording();

      // Second pass on the same static scene should reuse the index.
      final rec2 = ui.PictureRecorder();
      rendering.render(Canvas(rec2), const Size(800, 600));
      rec2.endRecording();

      final rs = rendering.stats;
      expect(rs['usedSpatialIndex'], isTrue);
      expect(
        rs['spatialReusedLastFrame'],
        isTrue,
        reason:
            'Quadtree should be reused when renderables and camera are '
            'unchanged between frames.',
      );
    });
  });
}
