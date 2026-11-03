// GameWidget fix from the 2.0.0 final pass (F42): a GameWidget built before
// its engine is initialized starts drawing and ticking it once it is, with
// no rebuild.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts updates and draws.
class _Counting extends System {
  int updates = 0;
  int renders = 0;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) => updates++;

  @override
  void render(Canvas canvas, Size size) => renders++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an engine initialized after its GameWidget is drawn and '
      'ticked', (tester) async {
    final engine = Engine();
    addTearDown(() => tester.runAsync(engine.dispose));
    final states = <EngineState>[];
    engine.stateListenable.addListener(
      () => states.add(engine.stateListenable.value),
    );

    await tester.pumpWidget(
      MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.runAsync(engine.initialize);
    expect(
      states,
      containsAllInOrder([EngineState.initializing, EngineState.initialized]),
    );
    final counting = _Counting();
    engine.world.addSystem(counting);
    engine.start();

    // No rebuild of the widget: only frames.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(counting.updates, greaterThan(0), reason: 'the tick runs');
    expect(counting.renders, greaterThan(0), reason: 'the world is drawn');
  });

  testWidgets('showDebug waits for the engine too', (tester) async {
    final engine = Engine();
    addTearDown(() => tester.runAsync(engine.dispose));
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(engine: engine, showFPS: false, showDebug: true),
      ),
    );
    await tester.runAsync(engine.initialize);
    expect(engine.world.getSystem<ColliderDebuggerSystem>(), isNotNull);
    expect(engine.rendering.debugMode, isTrue);
  });
}
