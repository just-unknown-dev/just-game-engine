// DialogueChoices: shows the runner's pending choices, picks the one
// tapped, greys out (or hides) unavailable ones, and builds nothing while
// no choice is pending.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

const _source = '''
title: Start
---
Pick one.
-> Red
    You chose red.
-> Blue
    You chose blue.
-> Gold <<if \$rich>>
    You chose gold.
===
''';

void main() {
  late DialogueRunner runner;

  setUp(() {
    runner = DialogueRunner(
      graph: YarnParser.parse(_source, id: 'g'),
      variables: DialogueVariableStore()..set('rich', false),
      conditions: DialogueConditionRegistry(),
      commands: DialogueCommandRegistry(),
    );
  });

  Widget host({bool showUnavailable = true}) => MaterialApp(
    home: Scaffold(
      body: DialogueChoices(runner: runner, showUnavailable: showUnavailable),
    ),
  );

  Future<void> toChoices(WidgetTester tester, {bool show = true}) async {
    unawaited(runner.start('Start'));
    await tester.pumpWidget(host(showUnavailable: show));
    runner.advance(); // past "Pick one."
    await tester.pump();
  }

  testWidgets('nothing while no choice is pending', (tester) async {
    unawaited(runner.start('Start'));
    await tester.pumpWidget(host());
    expect(find.text('Red'), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    await runner.stop();
  });

  testWidgets('tapping the second option plays the line after it', (
    tester,
  ) async {
    await toChoices(tester);
    expect(find.text('Red'), findsOneWidget);
    expect(find.text('Blue'), findsOneWidget);
    await tester.tap(find.text('Blue'));
    await tester.pump();
    expect(runner.signals.currentLine.value?.text, 'You chose blue.');
    expect(find.text('Red'), findsNothing, reason: 'the choices went away');
    await runner.stop();
  });

  testWidgets('an unavailable option is shown greyed out and cannot be '
      'picked', (tester) async {
    await toChoices(tester);
    expect(find.text('Gold'), findsOneWidget);
    final style = tester.widget<Text>(find.text('Gold')).style!;
    expect(style.color, Colors.white38);
    await tester.tap(find.text('Gold'));
    await tester.pump();
    expect(runner.signals.choices.value, hasLength(3), reason: 'still up');
    expect(runner.signals.currentLine.value, isNull);
    await runner.stop();
  });

  testWidgets('showUnavailable: false hides it', (tester) async {
    await toChoices(tester, show: false);
    expect(find.text('Gold'), findsNothing);
    expect(find.text('Red'), findsOneWidget);
    await runner.stop();
  });
}
