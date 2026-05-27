import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('engine can create a bound debugger controller', () async {
    final engine = Engine();
    await engine.initialize();

    final controller = engine.createDebuggerController();

    expect(controller.isBound, isTrue);
    expect(controller.logs, isNotEmpty);

    controller.dispose();
    engine.stop();
  });

  testWidgets('game widget does not render embedded debugger panel', (
    tester,
  ) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(engine: engine, showFPS: false, showDebug: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ECS Debugger'), findsNothing);
    expect(find.text('Performance'), findsNothing);

    engine.stop();
  });

  testWidgets('game widget does not show the legacy debug dropdown', (
    tester,
  ) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(engine: engine, showFPS: false, showDebug: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Debug'), findsNothing);
    expect(find.text('ECS Debugger'), findsNothing);

    engine.stop();
  });

  testWidgets('showDebug keeps rendering active without debugger panel', (
    tester,
  ) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(engine: engine, showFPS: false, showDebug: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('ECS Debugger'), findsNothing);

    engine.stop();
  });

  testWidgets('fps counter still renders with showDebug enabled', (
    tester,
  ) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(engine: engine, showFPS: true, showDebug: true),
        ),
      ),
    );
    await tester.pump();

    final fpsFinder = find.textContaining('FPS:');
    expect(fpsFinder, findsOneWidget);
    expect(find.text('ECS Debugger'), findsNothing);

    engine.stop();
  });
}
