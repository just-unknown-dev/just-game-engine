// The game loop, its clock and the views that drive it: two GameWidgets on
// one engine count each frame once (C1); the per-frame phase gets a clamped
// frame (C12); game time stands still while paused (C14); interpolation has
// one source (D1); camera post effects run on real time (E23); audio still
// updates while paused (C3); the app going to the background silences the
// game (C2); keys held as the terminal opens are let go (C6).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts the fixed updates and the rendered frames it is given.
class _Counter extends System implements FrameSystem {
  int updates = 0;
  int frames = 0;
  final List<double> frameTimes = [];

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) => updates++;

  @override
  void frame(double deltaTime, double alpha) {
    frames++;
    frameTimes.add(deltaTime);
  }

  void reset() {
    updates = 0;
    frames = 0;
    frameTimes.clear();
  }
}

/// An audio engine that never starts a backend and records what the engine
/// and the widget ask of it.
class _Audio extends AudioEngine {
  int updates = 0;
  bool musicPlaying = false;
  final List<String> log = [];

  @override
  bool get isMusicPlaying => musicPlaying;

  @override
  Future<void> initialize() async {}

  @override
  void update({double? dt}) => updates++;

  @override
  Future<void> pauseMusic() async {
    log.add('pause music');
    musicPlaying = false;
  }

  @override
  Future<void> resumeMusic() async {
    log.add('resume music');
    musicPlaying = true;
  }

  @override
  void mute() {
    log.add('mute');
    super.mute();
  }

  @override
  void unmute() {
    log.add('unmute');
    super.unmute();
  }

  @override
  Future<void> dispose() async {}
}

const _frame = Duration(microseconds: 16667);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Engine> boot([AudioEngine Function()? audio]) async {
    final engine = Engine(config: EngineConfig(createAudio: audio));
    addTearDown(engine.dispose);
    await engine.initialize();
    return engine;
  }

  /// Ticks [engine]'s loop [count] times, a 60 Hz frame apart, as a view
  /// would, from frame [at]; returns the frame after. A loop's first tick
  /// only starts its clock.
  int run(Engine engine, int count, {int at = 0}) {
    for (var i = 0; i < count; i++) {
      engine.gameLoop.tick(_frame * (at + i));
    }
    return at + count;
  }

  group('C1 two views of one engine', () {
    testWidgets('count each frame once, and either can go', (tester) async {
      final engine = (await tester.runAsync(boot))!;
      final counter = _Counter();
      engine.world.addSystem(counter);
      engine.start();
      final views = ValueNotifier<List<String>>(['first']);
      addTearDown(views.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<List<String>>(
            valueListenable: views,
            builder: (_, shown, _) => Column(
              children: [
                for (final name in shown)
                  Expanded(
                    key: ValueKey(name),
                    child: GameWidget(engine: engine, showFPS: false),
                  ),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(_frame);
      }

      // A second view, whose ticker starts half a second later.
      views.value = ['first', 'second'];
      await tester.pump(_frame);
      counter.reset();
      for (var i = 0; i < 120; i++) {
        await tester.pump(_frame);
      }
      expect(counter.frames, 120, reason: 'once a frame, not once a view');
      expect(counter.updates, inInclusiveRange(119, 121));
      expect(engine.gameLoop.currentFPS, inInclusiveRange(59, 61));
      expect(counter.frameTimes, everyElement(closeTo(1 / 60, 1e-6)));

      // The first view goes; the second drives on, with no jump in time.
      views.value = ['second'];
      await tester.pump(_frame);
      counter.reset();
      for (var i = 0; i < 60; i++) {
        await tester.pump(_frame);
      }
      expect(counter.frames, 60);
      expect(counter.updates, inInclusiveRange(59, 61));
      expect(counter.frameTimes, everyElement(closeTo(1 / 60, 1e-6)));
    });

    test('a frame ticked again with its own stamp does nothing', () {
      var updates = 0;
      var frames = 0;
      final loop = GameLoop(
        onUpdate: (_) => updates++,
        onFrame: (_, _) => frames++,
        timeManager: TimeManager(),
      )..start();
      for (var frame = 0; frame <= 60; frame++) {
        final stamp = _frame * frame;
        loop
          ..tick(stamp)
          ..tick(stamp);
      }
      expect(frames, 61);
      expect(updates, 60);
      expect(loop.timeManager.frameCount, 61);
    });

    test('resuming in the middle of a frame does not count it twice', () {
      var frames = 0;
      final loop = GameLoop(
        onUpdate: (_) {},
        onFrame: (_, _) => frames++,
        timeManager: TimeManager(),
      )..start();
      loop
        ..tick(_frame)
        ..pause()
        ..tick(_frame * 2)
        ..resume()
        ..tick(_frame * 2); // the other view, same frame
      expect(frames, 1);
    });
  });

  test('C12 the per-frame phase gets a clamped frame after a hitch', () {
    final frameTimes = <double>[];
    final time = TimeManager()..timeScale = 2;
    final loop = GameLoop(
      onUpdate: (_) {},
      onFrame: (dt, _) => frameTimes.add(dt),
      timeManager: time,
    )..start();
    loop
      ..tick(Duration.zero)
      ..tick(const Duration(seconds: 5));
    expect(frameTimes.last, closeTo(time.maxDeltaTime * 2, 1e-9));
  });

  group('C14 game time while paused', () {
    test('stands still; real time goes on', () {
      final time = TimeManager();
      final loop = GameLoop(onUpdate: (_) {}, timeManager: time)..start();
      for (var i = 0; i <= 60; i++) {
        loop.tick(_frame * i);
      }
      final gameTime = time.totalTime;
      final realTime = time.unscaledTotalTime;
      expect(gameTime, closeTo(1, 1e-3));

      loop.pause();
      for (var i = 61; i <= 120; i++) {
        loop.tick(_frame * i);
      }
      expect(time.totalTime, gameTime, reason: 'a cooldown must not run out');
      expect(time.deltaTime, 0);
      expect(time.unscaledDeltaTime, closeTo(1 / 60, 1e-6));
      expect(time.unscaledTotalTime, closeTo(realTime + 1, 1e-3));
      expect(time.fps, closeTo(60, 0.1));

      loop.resume();
      for (var i = 121; i <= 180; i++) {
        loop.tick(_frame * i);
      }
      expect(time.totalTime, closeTo(gameTime + 59 / 60, 1e-3));
    });

    test('engine.time stops behind a pause menu', () async {
      final engine = await boot();
      engine.start();
      final next = run(engine, 31);
      final before = engine.time.totalTime;
      engine.pause();
      run(engine, 60, at: next);
      expect(engine.time.totalTime, before);
    });
  });

  test('D1 the frame phase hands the interpolation on, with no view', () async {
    final engine = await boot();
    final render = RenderSystem();
    engine.world.addSystem(render);
    engine.start();
    engine.gameLoop
      ..tick(Duration.zero)
      ..tick(const Duration(microseconds: 41667)); // two and a half steps
    expect(engine.gameLoop.interpolation, closeTo(0.5, 0.01));
    expect(render.interpolation, engine.gameLoop.interpolation);
    expect(engine.rendering.interpolation, engine.gameLoop.interpolation);
  });

  group('E23 camera post effects run on real time', () {
    for (final (name, halt) in <(String, void Function(Engine))>[
      ('while paused', (engine) => engine.pause()),
      ('at time scale 0', (engine) => engine.time.timeScale = 0),
    ]) {
      test('a flash finishes $name', () async {
        final engine = await boot();
        engine.start();
        final effects = engine.cameraSystem.mainCamera.effectManager;
        final flash = ScreenFadeEffect();
        effects.addEffect(flash);
        halt(engine);
        flash.flash(Colors.white, holdDuration: 0.1, fadeDuration: 0.3);
        run(engine, 31); // half a second
        expect(flash.isComplete, isTrue);
        expect(effects.hasEffects, isFalse);
      });
    }

    test('letterbox bars slide in while paused', () async {
      final engine = await boot();
      engine.start();
      final effects = engine.cameraSystem.mainCamera.effectManager;
      final bars = LetterboxEffect();
      effects.addEffect(bars);
      engine.pause();
      bars.show(0.25);
      final next = run(engine, 31);
      bars.hide(0.25);
      run(engine, 30, at: next);
      expect(bars.isComplete, isTrue, reason: 'in and out again');
    });
  });

  test('C3 audio keeps updating while paused', () async {
    final audio = _Audio();
    final engine = await boot(() => audio);
    engine.start();
    final next = run(engine, 6);
    engine.pause();
    final before = audio.updates;
    run(engine, 10, at: next);
    // A volume changed in the pause menu is flushed by these.
    expect(audio.updates - before, 10);
  });

  group('C2 going to the background', () {
    testWidgets('pauses the music and mutes; coming back undoes it', (
      tester,
    ) async {
      final audio = _Audio()..musicPlaying = true;
      final engine = (await tester.runAsync(() => boot(() => audio)))!;
      engine.start();
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(engine.isAudioSuspended, isTrue);
      expect(audio.log, ['pause music', 'mute']);
      expect(audio.isMuted, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(engine.isAudioSuspended, isFalse);
      expect(audio.log, ['pause music', 'mute', 'unmute', 'resume music']);
      expect(audio.isMuted, isFalse);
      expect(engine.isRunning, isTrue);
    });

    testWidgets('leaves what the player paused or muted alone', (tester) async {
      final audio = _Audio(); // the music paused from the pause menu
      final engine = (await tester.runAsync(() => boot(() => audio)))!;
      engine.start();
      audio.mute(); // and the sound muted in the options
      audio.log.clear();
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(audio.log, isEmpty);
      expect(audio.isMuted, isTrue);
      expect(audio.musicPlaying, isFalse);
    });
  });

  testWidgets('C6 a key held as the terminal opens is let go', (tester) async {
    final engine = (await tester.runAsync(boot))!;
    engine.start();
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(engine: engine, showFPS: false, showTerminal: true),
      ),
    );
    await tester.pump(_frame);
    final keyboard = engine.input.keyboard;
    bool held() => keyboard.isDown(PhysicalKeyboardKey.keyD, live: true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.pump(_frame);
    expect(held(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backquote); // opens it
    await tester.pump(_frame);
    expect(engine.terminal.isVisible, isTrue);
    expect(held(), isFalse, reason: 'it stayed down for good');

    // A key pressed and let go while it is open: the up still reaches the
    // game, which never saw the down.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump(_frame);
    expect(held(), isFalse);
    expect(keyboard.isDown(PhysicalKeyboardKey.keyA, live: true), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.backquote); // closes it
    await tester.pump(_frame);
    expect(engine.terminal.isVisible, isFalse);
  });
}
