// A plugin is ticked once per frame on wall-clock time. An editor is the
// obvious plugin, and an editor holds the game's time scale at zero while
// authoring — so a tick that came through the scaled fixed step would be a
// tick of nothing.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Counting extends EnginePlugin {
  int attached = 0, ticks = 0, detached = 0;
  double time = 0;

  @override
  String get id => 'counting';

  @override
  Future<void> attach(Engine engine) async => attached++;

  @override
  void update(double dt) {
    ticks++;
    time += dt;
  }

  @override
  void renderOverlay(Canvas canvas, Size size) {}

  @override
  void detach() => detached++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'plugins tick every frame on unscaled time, even at time scale 0',
    () async {
      Engine.resetInstance();
      final engine = Engine();
      await engine.initialize();
      addTearDown(Engine.resetInstance);

      final plugin = _Counting();
      engine.plugins.register(plugin);
      expect(plugin.attached, 1);

      engine.time.timeScale = 0;
      engine.start();
      engine.gameLoop.tick();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      engine.gameLoop.tick();

      expect(plugin.ticks, 2);
      expect(plugin.time, greaterThan(0), reason: 'wall time, not scaled time');

      engine.plugins.unregister('counting');
      expect(plugin.detached, 1);
      engine.gameLoop.tick();
      expect(plugin.ticks, 2);
    },
  );

  test(
    'registering the same id again replaces and detaches the old one',
    () async {
      Engine.resetInstance();
      final engine = Engine();
      await engine.initialize();
      addTearDown(Engine.resetInstance);

      final first = _Counting();
      final second = _Counting();
      engine.plugins.register(first);
      engine.plugins.register(second);
      expect(first.detached, 1);
      expect(engine.plugins.byId('counting'), same(second));
    },
  );
}
