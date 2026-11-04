// The core's small helpers: GameTerminal runs typed commands, SystemManager
// runs its tasks in order and refuses a second of a name, TimeManager
// scales, clamps and pauses time.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('GameTerminal', () {
    late GameTerminal terminal;
    setUp(() {
      terminal = GameTerminal()
        ..registerCommand(
          name: 'echo',
          description: 'Says it back.',
          handler: (args) => args.join(' '),
        );
    });
    tearDown(() => terminal.dispose());

    void type(String text) {
      for (final c in text.split('')) {
        terminal.appendCharacter(c);
      }
      terminal.handleKeyDown(LogicalKeyboardKey.enter);
    }

    test('a command typed and entered runs, its output in the history', () {
      type('echo a b');
      expect(terminal.history, ['> echo a b', 'a b']);
      expect(terminal.inputBuffer, isEmpty);
    });

    test('an unknown command says so', () {
      type('jump');
      expect(terminal.history.last, contains("Unknown command: 'jump'"));
    });

    test('help lists the commands; clear empties the history', () {
      type('help');
      expect(terminal.history.last, contains('echo'));
      expect(terminal.history.last, contains('Says it back.'));
      type('clear');
      expect(terminal.history, isEmpty);
    });

    test('backspace edits; control characters are not typed', () {
      terminal
        ..appendCharacter('e')
        ..appendCharacter('x')
        ..handleKeyDown(LogicalKeyboardKey.backspace);
      expect(terminal.inputBuffer, 'e');
      expect(terminal.appendCharacter('\n'), isFalse);
      expect(terminal.inputBuffer, 'e');
    });

    test('the history keeps the last 100 lines', () {
      for (var i = 0; i < 60; i++) {
        type('echo $i');
      }
      expect(terminal.history, hasLength(100));
      expect(terminal.history.last, '59');
      expect(terminal.history.first, '> echo 10');
    });
  });

  group('SystemManager tasks', () {
    test('run in registration order, each name once', () {
      final manager = SystemManager();
      final ran = <String>[];
      manager
        ..registerUpdateTask('a', (_) => ran.add('a'))
        ..registerUpdateTask('b', (_) => ran.add('b'))
        ..registerFrameTask('f', (_, _) => ran.add('f'));
      expect(() => manager.registerUpdateTask('a', (_) {}), throwsStateError);
      expect(() => manager.registerFrameTask('f', (_, _) {}), throwsStateError);
      manager
        ..runUpdateCycle(1 / 60)
        ..runFrameCycle(1 / 60, 0.5);
      expect(ran, ['a', 'b', 'f']);
      expect(manager.lastTaskTimesMs.keys, ['a', 'b']);
    });

    test('unregister removes a task once', () {
      final manager = SystemManager();
      var ran = 0;
      manager.registerUpdateTask('a', (_) => ran++);
      expect(manager.unregisterUpdateTask('a'), isTrue);
      expect(manager.unregisterUpdateTask('a'), isFalse);
      manager.registerFrameTask('f', (_, _) {});
      expect(manager.unregisterFrameTask('f'), isTrue);
      expect(manager.unregisterFrameTask('f'), isFalse);
      manager.runUpdateCycle(1 / 60);
      expect(ran, 0);
    });
  });

  group('TimeManager', () {
    test('a negative time scale is refused', () {
      expect(() => TimeManager().timeScale = -1, throwsArgumentError);
      expect(() => TimeManager().maxDeltaTime = 0, throwsArgumentError);
    });

    test('a long frame is clamped to maxDeltaTime', () {
      final time = TimeManager()..maxDeltaTime = 0.1;
      time.update(1.0);
      expect(time.deltaTime, 0.1);
      expect(time.unscaledDeltaTime, 0.1);
    });

    test('slow motion halves deltaTime; fastForward doubles it', () {
      final time = TimeManager()..slowMotion();
      time.update(0.05);
      expect(time.deltaTime, closeTo(0.025, 1e-12));
      expect(time.unscaledDeltaTime, 0.05);
      time
        ..fastForward()
        ..update(0.05);
      expect(time.deltaTime, closeTo(0.1, 1e-12));
    });

    test('paused, totalTime stands still while real time goes on', () {
      final time = TimeManager()..update(0.05);
      final total = time.totalTime;
      time.update(0.05, paused: true);
      expect(time.deltaTime, 0);
      expect(time.totalTime, total);
      expect(time.unscaledTotalTime, closeTo(0.1, 1e-12));
      expect(time.frameCount, 2);
    });

    test('reset puts everything back', () {
      final time = TimeManager()
        ..slowMotion()
        ..update(0.05)
        ..reset();
      expect(time.totalTime, 0);
      expect(time.timeScale, 1);
      expect(time.frameCount, 0);
    });
  });
}
