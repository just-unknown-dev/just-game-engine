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

  testWidgets('game widget can expose integrated debugger tools', (
    tester,
  ) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    final controller = engine.createDebuggerController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(
            engine: engine,
            showFPS: false,
            showDebug: false,
            debuggerController: controller,
            showDebuggerTools: true,
            showDebuggerInspector: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ECS Debugger'), findsOneWidget);
    expect(find.text('Performance'), findsWidgets);

    controller.dispose();
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
          child: GameWidget(
            engine: engine,
            showFPS: false,
            showDebug: false,
            showDebuggerTools: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Debug'), findsNothing);
    expect(find.text('ECS Debugger'), findsOneWidget);

    engine.stop();
  });

  testWidgets('showDebug exposes the ECS debugger overlay', (tester) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(
            engine: engine,
            showFPS: false,
            showDebug: true,
            showDebuggerTools: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ECS Debugger'), findsOneWidget);

    engine.stop();
  });

  testWidgets('fps counter stacks above the ECS overlay', (tester) async {
    final engine = Engine();
    await engine.initialize();
    engine.start();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameWidget(
            engine: engine,
            showFPS: true,
            showDebug: true,
            showDebuggerTools: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final fpsFinder = find.textContaining('FPS:');
    final overlayFinder = find.text('ECS Debugger');

    expect(fpsFinder, findsOneWidget);
    expect(overlayFinder, findsOneWidget);

    final fpsRect = tester.getRect(fpsFinder);
    final overlayRect = tester.getRect(overlayFinder);
    expect(overlayRect.top, greaterThanOrEqualTo(fpsRect.bottom + 8));

    engine.stop();
  });
}
