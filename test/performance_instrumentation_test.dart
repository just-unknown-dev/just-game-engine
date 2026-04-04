import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('performance instrumentation', () {
    test('world stats capture per-system timings after update', () {
      final world = World();
      world.addSystem(_ProbeSystem());
      world.initialize();

      world.update(1 / 60);

      final stats = world.stats;
      final systemTimes = stats['systemTimesMs'] as Map<String, double>;

      expect(stats['lastUpdateMs'], isA<double>());
      expect(stats['lastCommandFlushes'], 0);
      expect(systemTimes, contains('_ProbeSystem'));
    });

    test('physics stats expose last simulation step counters', () {
      final physics = PhysicsEngine();
      physics.initialize();

      physics.update(1 / 60);

      final stats = physics.stats;
      expect(stats['bodyCount'], 0);
      expect(stats['awakeBodies'], 0);
      expect(stats['potentialPairs'], 0);
      expect(stats['resolvedCollisions'], 0);
      expect(stats['lastStepMs'], isA<double>());
    });

    test('rendering stats reuse the spatial index for unchanged scenes', () {
      final rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(800, 600));
      rendering.initialize();

      for (var i = 0; i < 250; i++) {
        rendering.addRenderable(
          CircleRenderable(
            radius: 4,
            fillColor: Colors.white,
            position: Offset(i * 10.0, 0),
          ),
        );
      }

      final recorder1 = ui.PictureRecorder();
      rendering.render(Canvas(recorder1), const Size(800, 600));
      recorder1.endRecording();

      final firstStats = rendering.stats;
      expect(firstStats['usedSpatialIndex'], true);
      expect(firstStats['spatialRebuilds'], 1);

      final recorder2 = ui.PictureRecorder();
      rendering.render(Canvas(recorder2), const Size(800, 600));
      recorder2.endRecording();

      final secondStats = rendering.stats;
      expect(secondStats['spatialRebuilds'], 1);
      expect(secondStats['spatialReusedLastFrame'], true);
    });

    test('physics broadphase reports zero dirty bodies when nothing moved', () {
      final physics = PhysicsEngine();
      physics.initialize();

      physics.addBody(
        PhysicsBody(
          position: Vector2(0, 0),
          shape: CircleShape(10),
          useGravity: false,
        ),
      );
      physics.addBody(
        PhysicsBody(
          position: Vector2(140, 0),
          shape: CircleShape(10),
          useGravity: false,
        ),
      );

      physics.update(1 / 60);
      final firstStats = physics.stats;
      expect(firstStats['broadphaseDirtyBodies'], 2);

      physics.update(1 / 60);
      final secondStats = physics.stats;
      expect(secondStats['broadphaseDirtyBodies'], 0);
      expect(secondStats['trackedCells'], greaterThan(0));
    });

    test(
      'cache manager falls back to in-memory storage when plugins are unavailable',
      () async {
        final cache = CacheManager();

        await cache.initialize();
        await cache.setString('test_key', 'value');
        await cache.setBinary('test-binary', Uint8List.fromList([1, 2, 3]));

        expect(cache.isInitialized, true);
        expect(await cache.getString('test_key'), 'value');
        expect(
          await cache.getBinary('test-binary'),
          Uint8List.fromList([1, 2, 3]),
        );
      },
    );

    test('system manager owns update scheduling diagnostics', () async {
      final manager = SystemManager();
      final order = <String>[];

      await manager.initialize();
      manager.registerUpdateTask('input', (_) => order.add('input'));
      manager.registerUpdateTask('physics', (_) => order.add('physics'));

      manager.runUpdateCycle(1 / 60);

      final stats = manager.schedulerStats;
      final taskTimes = stats['taskTimesMs'] as Map<String, double>;

      expect(order, ['input', 'physics']);
      expect(stats['lastFrameMs'], isA<double>());
      expect(taskTimes.keys, containsAll(['input', 'physics']));
    });
  });
}

class _ProbeSystem extends System {
  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    // Intentionally empty: the test only verifies that timing metadata is recorded.
  }
}
