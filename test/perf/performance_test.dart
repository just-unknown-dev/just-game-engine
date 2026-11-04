// Performance benchmarks for the Just Game Engine.
//
// Each prints what it measured and fails only when something is badly
// wrong: ceilings are at least ten times what a busy machine measures, as
// timing on a shared machine is too noisy for more. Tagged `perf`, so a
// plain `flutter test` skips them; a before/after comparison runs only
// them (`flutter test --tags perf --run-skipped`).
@Tags(['perf'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The median of [samples].
int _median(List<int> samples) {
  final sorted = [...samples]..sort();
  return sorted[sorted.length ~/ 2];
}

/// A world of [count] circle shapes moving with a velocity, drawn by a
/// RenderSystem through [camera].
World _shapes(int count, Camera camera) {
  final world = World(extensions: [BuiltInComponents.extension])
    ..addSystem(MovementSystem())
    ..addSystem(RenderSystem(camera: camera));
  for (var i = 0; i < count; i++) {
    world.createEntityWithComponents([
      TransformComponent(position: Vector3((i % 50) * 10.0, (i ~/ 50) * 10.0, 0)),
      VelocityComponent(velocity: Vector3(10, 5, 0)),
      Circle2DComponent(radius: 4),
    ]);
  }
  return world;
}

/// Microseconds [world] takes to draw one frame.
int _drawMicros(World world) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final watch = Stopwatch()..start();
  world.render(canvas, const Size(800, 600));
  watch.stop();
  recorder.endRecording().dispose();
  return watch.elapsedMicroseconds;
}

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
      // About 200 ms; over 1 s on a machine busy with other test runs.
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
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
      // About 60 ms with coverage on.
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
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
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('Particle system performance with 500 particles', () async {
      final emitter = ParticleEmitter(
        position: null,
        maxParticles: 500,
        emissionRate: 100, // 100 particles per second
        particleLifetime: 5.0,
      );

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
      expect(emitter.particleCount, greaterThan(0));
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('ECS query performance with 1000 entities', () async {
      final world = World();
      addTearDown(world.dispose);

      // Create 1000 entities with various components
      for (int i = 0; i < 1000; i++) {
        final entity = world.createEntity(name: 'Entity_$i');
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

      // Perform 100 queries, each after a change so none is a cache hit.
      var found = 0;
      for (int i = 0; i < 100; i++) {
        world.createEntityWithComponents([
          TransformComponent(),
          VelocityComponent(),
        ]);
        found = world.query([TransformComponent, VelocityComponent]).length;
      }

      stopwatch.stop();

      expect(found, 600);
      debugPrint(
        '1000 entities, 100 queries: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('ECS system update and draw with 500 entities', () async {
      final camera = Camera(viewportSize: const Size(800, 600));
      final world = _shapes(500, camera);
      addTearDown(world.dispose);

      final stopwatch = Stopwatch()..start();

      // Update and draw for 60 frames
      for (int i = 0; i < 60; i++) {
        world.update(0.016);
        _drawMicros(world);
      }

      stopwatch.stop();

      debugPrint(
        '500 entities, update + draw, 60 frames: '
        '${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });

    test('Camera transformation performance', () async {
      final camera = Camera(viewportSize: const Size(800, 600));

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
      // About 5 ms.
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
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
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('Scalability Tests', () {
    test('Drawing scales about linearly with the entity count', () {
      final camera = Camera(viewportSize: const Size(800, 600));
      final medians = <int, int>{};
      for (final count in [100, 1000]) {
        final world = _shapes(count, camera);
        addTearDown(world.dispose);
        world.update(0.016);
        _drawMicros(world); // warm up
        medians[count] = _median([
          for (var run = 0; run < 15; run++) _drawMicros(world),
        ]);
        debugPrint('$count shapes: ${medians[count]} µs a frame (median)');
      }
      // Linear is 10x; well past that is a regression, not noise.
      expect(medians[1000]!, lessThan(medians[100]! * 40 + 2000));
    });
  });

  // ── Stats-driven frame budget benchmarks ──────────────────────────────────
  // These tests exercise the live diagnostics APIs under a real load.
  group('Frame budget benchmarks (stats API)', () {
    test(
      'scheduler completes a loaded update cycle within the 60 Hz budget',
      () async {
        final engine = Engine();
        addTearDown(engine.dispose);
        await engine.initialize();
        final world = engine.world
          ..addSystem(MovementSystem())
          ..addSystem(RenderSystem(camera: engine.camera.mainCamera));
        for (var i = 0; i < 500; i++) {
          world.createEntityWithComponents([
            TransformComponent(position: Vector3(i * 2.0, 0, 0)),
            VelocityComponent(velocity: Vector3(10, 5, 0)),
            Circle2DComponent(radius: 4),
          ]);
        }

        // Warm up to stabilise timings (JIT, first-frame overhead).
        for (int i = 0; i < 5; i++) {
          engine.systemManager.runUpdateCycle(1 / 60);
        }

        // Drive one full update cycle through the authoritative scheduler.
        engine.systemManager.runUpdateCycle(1 / 60);

        // The scheduler's own timing: performanceStats' lastUpdateMs is
        // the game loop's, and this cycle did not come through it.
        final scheduler =
            engine.performanceStats['scheduler'] as Map<String, dynamic>;
        final lastFrameMs = scheduler['lastFrameMs'] as double;

        debugPrint(
          'Scheduler update cycle, 500 entities: '
          '${lastFrameMs.toStringAsFixed(2)} ms',
        );

        expect(lastFrameMs, greaterThan(0), reason: 'something was timed');
        expect(
          lastFrameMs,
          lessThan(1000 / 60),
          reason:
              'Engine update cycle took ${lastFrameMs.toStringAsFixed(2)} '
              'ms — exceeded the 16.67 ms / 60 Hz frame budget.',
        );
      },
    );
  });
}
