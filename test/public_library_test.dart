// The public library as a game first meets it: an engine's states through
// its life, two engines that share nothing, its subsystems reachable once
// it is initialized, and the input devices it starts with.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an engine goes through its states', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.state, EngineState.uninitialized);
    expect(engine.isInitialized, isFalse);

    await engine.initialize();
    expect(engine.state, EngineState.initialized);
    expect(engine.isRunning, isFalse);

    engine.start();
    expect(engine.state, EngineState.running);
    engine.pause();
    expect(engine.state, EngineState.paused);
    engine.resume();
    expect(engine.state, EngineState.running);
    engine.stop();
    expect(engine.state, EngineState.initialized);

    await engine.dispose();
    expect(engine.state, EngineState.disposed);
    expect(() => engine.world, throwsA(isA<EngineNotReadyError>()));
  });

  test('two engines share nothing', () async {
    final a = Engine();
    final b = Engine();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.initialize();
    await b.initialize();
    expect(a.world, isNot(same(b.world)));
    expect(a.context, isNot(same(b.context)));
    expect(a.assets, isNot(same(b.assets)));
    expect(a.world.context, same(a.context));
    expect(b.world.context, same(b.context));
  });

  test('its subsystems are reachable once initialized', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(() => engine.rendering, throwsA(isA<EngineNotReadyError>()));
    await engine.initialize();
    expect(engine.subsystem<RenderingEngine>(), same(engine.rendering));
    expect(engine.subsystem<Physics2DEngine>(), same(engine.physics));
    expect(engine.subsystem<InputService>(), same(engine.input));
    expect(engine.subsystem<AudioEngine>(), same(engine.audio));
    expect(engine.subsystem<CacheManager>(), same(engine.cache));
    expect(engine.subsystem<AssetManager>(), same(engine.assets));
    expect(engine.subsystem<CameraEngine>(), same(engine.camera));
    expect(engine.subsystem<World>(), same(engine.world));
    expect(engine.assets, same(engine.context.assets));
  });

  test('its input starts with keyboard, mouse and touch; no pads', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final input = engine.input;
    expect(input.devices, [
      input.keyboard,
      input.mouse,
      input.touchscreen,
      input.onScreen,
    ]);
    expect(input.gamepads, isEmpty, reason: 'gamepads are opt-in');
  });
}
