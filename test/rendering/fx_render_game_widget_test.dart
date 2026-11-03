// GameWidget and the game loop it drives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Layer extends GameLayer {
  _Layer(this.id, this.name, this.log);
  @override
  final String id;
  final String name;
  final List<String> log;

  @override
  GameLayerController createController(Engine engine) {
    log.add('create $name');
    return _Controller(name, log);
  }
}

class _Controller extends GameLayerController {
  _Controller(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  Widget build(BuildContext context) => Text(name);

  @override
  void dispose() => log.add('dispose $name');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Engine> boot() async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    return engine;
  }

  Future<Engine> pumpGame(
    WidgetTester tester, {
    bool start = true,
    bool showDebug = false,
  }) async {
    final engine = (await tester.runAsync(boot))!;
    if (start) engine.start();
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(engine: engine, showFPS: false, showDebug: showDebug),
      ),
    );
    return engine;
  }

  group('going to the background and back', () {
    testWidgets('resumes a game it paused', (tester) async {
      final engine = await pumpGame(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(engine.isPaused, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(engine.isRunning, isTrue);
    });

    testWidgets('leaves a game the player paused paused', (tester) async {
      final engine = await pumpGame(tester);
      engine.pause(); // The pause menu.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(engine.isPaused, isTrue, reason: 'it used to resume');
    });
  });

  group('localization', () {
    testWidgets("a layer reads the engine's strings", (tester) async {
      final engine = (await tester.runAsync(boot))!;
      final l10n = LocalizationManager();
      engine.context.localization = l10n;
      final seen = <LocalizationManager?>[];
      engine.layers.register(_Probe(seen));
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      expect(seen.last, same(l10n));
    });

    testWidgets('without them there is no scope, and no global', (
      tester,
    ) async {
      final engine = (await tester.runAsync(boot))!;
      final seen = <LocalizationManager?>[];
      engine.layers.register(_Probe(seen));
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      expect(seen, isNotEmpty);
      expect(seen.last, isNull);
    });
  });

  group('layers', () {
    testWidgets('a layer re-registered under its id gets a new controller', (
      tester,
    ) async {
      final engine = await pumpGame(tester);
      final log = <String>[];
      engine.layers.register(_Layer('hud', 'first', log));
      await tester.pump();
      expect(find.text('first'), findsOneWidget);

      engine.layers.register(_Layer('hud', 'second', log));
      await tester.pump();
      expect(log, ['create first', 'dispose first', 'create second']);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });

    testWidgets('a new engine: the old one no longer reaches this view', (
      tester,
    ) async {
      final first = await pumpGame(tester);
      final log = <String>[];
      final second = (await tester.runAsync(boot))!;
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: second, showFPS: false)),
      );
      first.layers.register(_Layer('old', 'old', log));
      second.layers.register(_Layer('new', 'new', log));
      await tester.pump();
      expect(log, ['create new']);
      expect(find.text('new'), findsOneWidget);
    });
  });

  testWidgets('showDebug follows the widget', (tester) async {
    final engine = await pumpGame(tester);
    bool hasDebugger() =>
        engine.world.getSystem<ColliderDebuggerSystem>() != null;
    expect(hasDebugger(), isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(engine: engine, showFPS: false, showDebug: true),
      ),
    );
    expect(hasDebugger(), isTrue);
    expect(engine.rendering.debugMode, isTrue);

    await tester.pumpWidget(
      MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
    );
    expect(hasDebugger(), isFalse);
    expect(engine.rendering.debugMode, isFalse);
  });

  testWidgets('interpolation reaches a render system added later', (
    tester,
  ) async {
    // The frame phase hands it on, and runs while the engine runs.
    final engine = await pumpGame(tester);
    final firstSystem = RenderSystem();
    engine.world.addSystem(firstSystem);
    await tester.pump(const Duration(milliseconds: 16));
    expect(firstSystem.interpolation, engine.gameLoop.interpolation);

    // A level loads: every system is cleared and added again.
    engine.world.clearSystems();
    final second = RenderSystem();
    engine.world.addSystem(second);
    expect(second.interpolation, 1.0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(second.interpolation, engine.gameLoop.interpolation);
    expect(second.interpolation, isNot(1.0));
  });

  group('GameLoop', () {
    test('timed by frame stamps: one update per 60 Hz frame, every frame', () {
      var updates = 0;
      final loop = GameLoop(
        onUpdate: (_) => updates++,
        timeManager: TimeManager(),
      )..start();
      loop.tick(Duration.zero);
      expect(updates, 0);
      for (var frame = 1; frame <= 120; frame++) {
        final before = updates;
        loop.tick(Duration(microseconds: (frame * 1000000 / 60).round()));
        expect(updates - before, 1, reason: 'frame $frame');
      }
    });

    test('a ticker starting again from zero is not a negative frame', () {
      var updates = 0;
      final loop = GameLoop(
        onUpdate: (_) => updates++,
        timeManager: TimeManager(),
      )..start();
      loop
        ..tick(const Duration(seconds: 5))
        ..tick(Duration.zero)
        ..tick(const Duration(milliseconds: 17));
      expect(updates, 1);
    });

    test('without stamps it times frames itself, as before', () async {
      var updates = 0;
      final loop = GameLoop(
        onUpdate: (_) => updates++,
        timeManager: TimeManager(),
      )..start();
      loop.tick();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      loop.tick();
      expect(updates, greaterThan(0));
    });
  });
}

/// Records which strings its layer can see.
class _Probe extends GameLayer {
  _Probe(this.seen);
  final List<LocalizationManager?> seen;

  @override
  String get id => 'probe';

  @override
  GameLayerController createController(Engine engine) => _ProbeController(seen);
}

class _ProbeController extends GameLayerController {
  _ProbeController(this.seen);
  final List<LocalizationManager?> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(LocalizationScope.maybeOf(context));
    return const SizedBox();
  }
}
