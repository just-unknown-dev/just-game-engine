// RenderingEngine.drawInterval: a GameWidget draws no more often than it
// says, while the game goes on running every frame.

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

  testWidgets('drawInterval spares drawing, not running', (tester) async {
    final engine = Engine();
    addTearDown(() => tester.runAsync(engine.dispose));
    await tester.runAsync(engine.initialize);
    final counting = _Counting();
    engine.world.addSystem(counting);
    engine.start();
    await tester.pumpWidget(
      MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
    );

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // Every frame, by default.
    await frames(5);
    counting
      ..renders = 0
      ..updates = 0;
    await frames(10);
    expect(counting.renders, 10);

    // At most every 100 ms: 30 frames of 16 ms are 480 ms, so five draws.
    engine.rendering.drawInterval = const Duration(milliseconds: 100);
    counting
      ..renders = 0
      ..updates = 0;
    await frames(30);
    expect(counting.renders, inInclusiveRange(4, 6));
    expect(counting.updates, greaterThan(20), reason: 'the game runs on');

    // Back to every frame at once.
    engine.rendering.drawInterval = null;
    counting.renders = 0;
    await frames(10);
    expect(counting.renders, 10);
  });
}
