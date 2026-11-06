// Dialogue: a choice set with nothing available is passed over; a restart
// keeps the dialogue active; a box made after the first line shows it; a
// trigger naming a missing graph is reported, not thrown; the manager takes
// its listener off caller-owned signals and leaves them undisposed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

DialogueRunner _runner(String source, {DialogueVariableStore? variables}) =>
    DialogueRunner(
      graph: YarnParser.parse(source, id: 'g'),
      variables: variables ?? DialogueVariableStore(),
      conditions: DialogueConditionRegistry(),
      commands: DialogueCommandRegistry(),
    );

/// Advances every line it shows, collecting their text.
List<String> _readAlong(DialogueRunner runner) {
  final lines = <String>[];
  runner.signals.currentLine.addListener(() {
    final line = runner.signals.currentLine.value;
    if (line == null) return;
    lines.add(line.text);
    scheduleMicrotask(runner.advance);
  });
  return lines;
}

void main() {
  test('a choice set with no available option is passed over', () async {
    final runner = _runner('''
title: Start
---
-> A <<if \$hasKey>>
    Opened.
-> B <<if \$hasGold>>
    Paid.
Done.
===
''');
    final offered = <List<DialogueChoice>>[];
    runner.signals.choices.addListener(
      () => offered.add(runner.signals.choices.value),
    );
    final lines = _readAlong(runner);
    await runner.start('Start').timeout(const Duration(seconds: 2));
    expect(lines, ['Done.']);
    expect(offered, isEmpty, reason: 'nothing to pick was never shown');
    expect(runner.isRunning, isFalse);
  });

  test('a set with one available option still waits for the pick', () async {
    final runner = _runner('''
title: Start
---
-> A <<if false>>
-> B
    Picked B.
===
''');
    unawaited(runner.start('Start'));
    await pumpEventQueue();
    expect(runner.signals.choices.value, hasLength(2));
    runner.selectChoice(1);
    await pumpEventQueue();
    expect(runner.signals.currentLine.value?.text, 'Picked B.');
    await runner.stop();
  });

  group('start while a session runs', () {
    test('keeps the dialogue active throughout', () async {
      final runner = _runner('''
title: Start
---
Hello.
===
title: Hub
---
Welcome back.
===
''');
      final activity = <bool>[];
      runner.signals.isDialogueActive.addListener(
        () => activity.add(runner.signals.isDialogueActive.value),
      );
      unawaited(runner.start('Start'));
      await pumpEventQueue();
      unawaited(runner.start('Hub'));
      await pumpEventQueue();
      expect(activity, [true], reason: 'no spurious end mid-conversation');
      expect(runner.signals.activeNodeTitle.value, 'Hub');
      expect(runner.signals.currentLine.value?.text, 'Welcome back.');
      await runner.stop();
      expect(activity, [true, false]);
    });

    test(
      "the manager still lets go of a restarted runner it started",
      () async {
        final manager = DialogueManager()
          ..parseAndRegister('''
title: Start
---
Hello.
===
title: Hub
---
Hub.
===
''', id: 'talk');
        addTearDown(manager.dispose);
        final ends = <bool>[];
        manager.isAnyDialogueActive.addListener(
          () => ends.add(manager.isAnyDialogueActive.value),
        );
        final runner = await manager.startDialogue(graphId: 'talk');
        await pumpEventQueue();
        unawaited(runner.start('Hub'));
        await pumpEventQueue();
        expect(ends, [true], reason: 'still talking');
        await runner.stop();
        await pumpEventQueue();
        expect(manager.runners, isEmpty, reason: 'transient: let go when over');
        expect(manager.isAnyDialogueActive.value, isFalse);
      },
    );
  });

  group('caller-owned signals', () {
    const source = '''
title: Start
---
Hi.
===
''';

    test('are not disposed by the manager, nor listened to after', () async {
      final manager = DialogueManager()..parseAndRegister(source, id: 'g');
      final shared = NarrativeSignals();
      final shown = <String?>[];
      shared.currentLine.addListener(
        () => shown.add(shared.currentLine.value?.text),
      );
      final first = manager.createRunner('g', signals: shared);
      await manager.disposeRunner(first);
      // Still usable — its listeners too: a second runner reports through
      // them.
      final second = manager.createRunner('g', signals: shared);
      unawaited(second.start('Start'));
      await pumpEventQueue();
      expect(shared.currentLine.value?.text, 'Hi.');
      expect(shown, contains('Hi.'), reason: 'the UI still hears it');
      expect(manager.runners, [second], reason: 'the first is not tracked');
      await manager.dispose();
      shared.dispose();
    });

    test('one runner per dialogue on them leaves no runner behind', () async {
      final manager = DialogueManager()..parseAndRegister(source, id: 'g');
      addTearDown(manager.dispose);
      final shared = NarrativeSignals();
      for (var i = 0; i < 3; i++) {
        final runner = manager.createRunnerForEntity(1, 'g', signals: shared);
        unawaited(runner.start('Start'));
        await pumpEventQueue();
        runner.advance();
        await pumpEventQueue();
      }
      manager.releaseRunnerForEntity(1);
      final last = manager.createRunner('g', signals: shared);
      unawaited(last.start('Start'));
      await pumpEventQueue();
      expect(manager.runners, [last], reason: 'old runners are not re-added');
    });
  });

  testWidgets('a dialogue box made after the first line shows it', (
    tester,
  ) async {
    final runner = _runner('''
title: Start
---
Ann: Hello there.
===
''');
    unawaited(runner.start('Start'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DialogueBox(runner: runner, typewriterSpeed: 0)),
      ),
    );
    await tester.pump();
    expect(find.text('Hello there.'), findsOneWidget);
    await runner.stop();
    await tester.pump();
  });

  test('a trigger naming a missing graph is reported, not thrown', () async {
    final manager = DialogueManager();
    addTearDown(manager.dispose);
    final world = World()..initialize();
    addTearDown(world.dispose);
    world.addSystem(DialogueSystem(manager: manager));
    world.createEntityWithComponents([
      TransformComponent(),
      TagComponent('player'),
    ], name: 'Player');
    world.createEntityWithComponents([
      TransformComponent(),
      DialogueTriggerComponent(graphId: 'intro_typo', triggerOnce: false),
    ]);
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add('$message');
    addTearDown(() => debugPrint = print);
    final errors = <Object>[];
    await runZonedGuarded(() async {
      world.update(1 / 60);
      await pumpEventQueue();
    }, (error, _) => errors.add(error));
    expect(errors, isEmpty);
    expect(logged.where((l) => l.contains('intro_typo')), hasLength(1));
  });
}
