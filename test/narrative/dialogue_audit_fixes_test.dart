// Dialogue fixes from the 2.0.0 final pass: isInDialogue follows the
// entity's runner and triggers auto-advance (F26); malformed Yarn throws
// YarnParseException (F35); the dialogue box follows a new runner (F36).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

const _talk = '''
title: Start
---
One
Two
===
''';

const _other = '''
title: Start
---
Other
===
''';

void main() {
  group('F26 DialogueSystem', () {
    late DialogueManager manager;
    late World world;

    setUp(() {
      manager = DialogueManager()..parseAndRegister(_talk, id: 'talk');
      world = World()..initialize();
      world.addSystem(DialogueSystem(manager: manager));
    });

    tearDown(() async {
      world.dispose();
      await manager.dispose();
    });

    Future<void> step(double seconds) async {
      world.update(seconds);
      await pumpEventQueue();
    }

    String? lineOf(DialogueRunner runner) =>
        runner.signals.currentLine.value?.text;

    test('isInDialogue follows the entity\'s runner, and lines advance by '
        'themselves', () async {
      final dc = DialogueComponent(
        graphId: 'talk',
        autoAdvance: true,
        autoAdvanceDelay: 0.5,
      );
      final npc = world.createEntityWithComponents([TransformComponent(), dc]);
      await step(0.1);
      expect(dc.isInDialogue, isFalse);

      final runner = manager.createRunnerForEntity(npc.id, 'talk');
      unawaited(runner.start('Start'));
      await pumpEventQueue();
      await step(0.1);
      expect(dc.isInDialogue, isTrue, reason: 'it was never set');
      expect(lineOf(runner), 'One');

      await step(0.3);
      expect(lineOf(runner), 'One', reason: 'not shown for 0.5 s yet');
      await step(0.2);
      expect(lineOf(runner), 'Two');
      await step(0.6);
      await step(0.1);
      expect(dc.isInDialogue, isFalse, reason: 'the dialogue ended');
    });

    test('a trigger with autoAdvance starts a dialogue that advances by '
        'itself', () async {
      world.createEntityWithComponents([
        TransformComponent(),
        TagComponent(EngineTags.player),
      ]);
      world.createEntityWithComponents([
        TransformComponent(),
        DialogueTriggerComponent(
          graphId: 'talk',
          autoAdvance: true,
          autoAdvanceDelay: 0.25,
        ),
      ]);
      await step(0.01);
      final runner = manager.runners.single;
      expect(lineOf(runner), 'One');
      await step(0.3);
      expect(lineOf(runner), 'Two', reason: 'autoAdvance was never read');
    });

    test('a trigger without autoAdvance waits for the player', () async {
      world.createEntityWithComponents([
        TransformComponent(),
        TagComponent(EngineTags.player),
      ]);
      world.createEntityWithComponents([
        TransformComponent(),
        DialogueTriggerComponent(graphId: 'talk'),
      ]);
      await step(0.01);
      final runner = manager.runners.single;
      await step(5);
      expect(lineOf(runner), 'One');
    });
  });

  group('F35 YarnParser throws on malformed input', () {
    Matcher parseError(int line) => throwsA(
      isA<YarnParseException>().having((e) => e.lineNumber, 'line', line),
    );

    test('a node with no title', () {
      expect(
        () => YarnParser.parse('tags: a\n---\nHi\n===\n', id: 'x'),
        parseError(1),
      );
    });

    test('two nodes with the same title', () {
      expect(
        () => YarnParser.parse(
          'title: A\n---\nHi\n===\ntitle: A\n---\nHo\n===\n',
          id: 'x',
        ),
        parseError(5),
      );
    });

    test('an <<if>> with no <<endif>>', () {
      expect(
        () => YarnParser.parse('title: A\n---\n<<if \$x>>\nHi\n===\n', id: 'x'),
        parseError(3),
      );
    });

    test('an <<endif>> or <<else>> with no <<if>>', () {
      expect(
        () => YarnParser.parse('title: A\n---\nHi\n<<endif>>\n===\n', id: 'x'),
        parseError(4),
      );
      expect(
        () => YarnParser.parse('title: A\n---\n<<else>>\n===\n', id: 'x'),
        parseError(3),
      );
    });

    test('well-formed conditionals, also inside choices, still parse', () {
      final graph = YarnParser.parse('''
title: A
---
<<if \$x>>
-> Yes
    Good.
    <<if \$y>>
    Both.
    <<endif>>
-> No
<<elseif \$z>>
Z.
<<else>>
None.
<<endif>>
After.
===
''', id: 'x');
      expect(graph.getNode('A'), isNotNull);
    });
  });

  testWidgets('F36 the dialogue box follows a new runner', (tester) async {
    final manager = DialogueManager()
      ..parseAndRegister(_talk, id: 'talk')
      ..parseAndRegister(_other, id: 'other');
    addTearDown(manager.dispose);
    final first = manager.createRunner('talk');
    final second = manager.createRunner('other');

    Widget box(DialogueRunner runner) => MaterialApp(
      home: Scaffold(
        body: DialogueBoxWidget(runner: runner, typewriterSpeed: 0),
      ),
    );

    await tester.pumpWidget(box(first));
    unawaited(first.start('Start'));
    await tester.pump();
    expect(find.text('One'), findsOneWidget);

    unawaited(second.start('Start'));
    await tester.pump();
    await tester.pumpWidget(box(second));
    await tester.pump();
    expect(find.text('Other'), findsOneWidget, reason: 'the new runner');

    first.advance();
    await tester.pump();
    expect(find.text('Two'), findsNothing, reason: 'the old one let go');
    expect(find.text('Other'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await first.stop();
    await second.stop();
  });
}
