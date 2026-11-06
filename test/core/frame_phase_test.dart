// The per-frame phase: after a frame's fixed updates, before it is drawn.
// (The 3-D camera rigs that use it are in camera/rig_3d_brain_test.dart.)

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Frames extends System implements PerFrame {
  _Frames(this.log, this.name, int priority) {
    this.priority = priority;
  }

  final List<String> log;
  final String name;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) => log.add('update $name');

  @override
  void frame(double deltaTime, double alpha) => log.add('frame $name');
}

class _UpdatesOnly extends System {
  _UpdatesOnly(this.log);
  final List<String> log;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) => log.add('update plain');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the per-frame phase', () {
    test('the loop calls it once a frame, after that frame\'s fixed updates', () {
      final log = <String>[];
      final loop = GameLoop(
        onUpdate: (_) => log.add('update'),
        onFrame: (dt, alpha) => log.add('frame ${alpha.toStringAsFixed(2)}'),
        timeManager: TimeManager(),
      )..start();
      loop.tick(Duration.zero);
      loop.tick(const Duration(microseconds: 41667)); // two and a half steps
      expect(log, ['frame 0.00', 'update', 'update', 'frame 0.50']);
      log.clear();
      loop.pause();
      loop.tick(const Duration(microseconds: 60000));
      expect(log, isEmpty, reason: 'paused: no updates, no frame phase');
    });

    test('the world runs only frame systems, in priority order', () {
      final log = <String>[];
      final world = World()..initialize();
      world
        ..addSystem(_Frames(log, 'low', 10))
        ..addSystem(_UpdatesOnly(log))
        ..addSystem(_Frames(log, 'high', 90));
      world.frame(1 / 60, 0.5);
      expect(log, ['frame high', 'frame low']);
      world.systems.whereType<_Frames>().first.isActive = false;
      log.clear();
      world.frame(1 / 60, 0.5);
      expect(log, ['frame low']);
    });

    test('a running engine reaches frame systems through the scheduler', () async {
      final log = <String>[];
      final engine = Engine();
      await engine.initialize();
      addTearDown(engine.dispose);
      engine.world.addSystem(_Frames(log, 'game', 0));
      engine.start();
      engine.gameLoop.tick(Duration.zero);
      engine.gameLoop.tick(const Duration(microseconds: 16667));
      expect(log, containsAllInOrder(['update game', 'frame game']));
      expect(log.last, 'frame game');
    });
  });
}
