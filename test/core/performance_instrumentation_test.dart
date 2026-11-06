import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final physics = PhysicsEngineFactory.create2D();
      physics.initialize();

      physics.update(1 / 60);

      final stats = physics.stats;
      expect(stats['bodyCount'], 0);
      expect(stats['awakeBodies'], 0);
      expect(stats['potentialPairs'], 0);
      expect(stats['resolvedCollisions'], 0);
      expect(stats['lastStepMs'], isA<double>());
    });

    test('physics broadphase reports zero dirty bodies when nothing moved', () {
      // Explicitly the pure-Dart backend: broadphaseDirtyBodies reports on the
      // Dart SpatialGrid, which the Box2D backend does not use at all — it has
      // its own broad phase — so on native this statistic is always zero and
      // the assertions below would be testing nothing.
      final physics = Physics2DEngine.pureDart();
      physics.initialize();

      physics.addBody(
        Physics2DBody(
          position: Vector2(0, 0),
          shape: Circle2DShape(10),
          useGravity: false,
        ),
      );
      physics.addBody(
        Physics2DBody(
          position: Vector2(140, 0),
          shape: Circle2DShape(10),
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
      // standalone 'physics' task — Physics2DSystem steps engine.physics
      // inline from within the 'ecs' task instead (see Engine.physics'
      // doc comment for why).
      // Audio is a frame task: it places sounds once the frame has moved
      // everything. The camera's post effects advance once per frame on
      // real time, outside the fixed step.
      const expectedTasks = ['input', 'ecs'];
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
            Physics2DBody(
              position: Vector2(i * 40.0, 0),
              velocity: Vector2(10, 5),
              shape: Circle2DShape(12),
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
