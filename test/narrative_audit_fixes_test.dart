// Narrative and localization fixes from the 2.0.0-dev.1 release audit: the
// runner's sessions, <<set>> and <<declare>>, the expression evaluator's
// keywords, option conditions, escapes, the localizer's locale switch, and
// the localization manager's tables, plurals and fallbacks.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

DialogueRunner _runner(
  String yarn, {
  DialogueVariableStore? vars,
  DialogueCommandRegistry? commands,
}) => DialogueRunner(
  graph: YarnParser.parse(yarn, id: 'g'),
  variables: vars ?? DialogueVariableStore(),
  conditions: DialogueConditionRegistry(),
  commands: commands ?? DialogueCommandRegistry(),
);

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Everything debugPrint says during the test.
List<String> _captureLog() {
  final lines = <String>[];
  final printer = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  addTearDown(() => debugPrint = printer);
  return lines;
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;
  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(utf8.encode(text));
  }
}

String? _line(DialogueRunner r) => r.signals.currentLine.value?.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('<<set>> and <<declare>>', () {
    Future<DialogueVariableStore> run(
      String body, [
      DialogueVariableStore? vars,
    ]) async {
      final store = vars ?? DialogueVariableStore();
      await _runner(
        'title: Start\n---\n$body\n===\n',
        vars: store,
      ).start('Start');
      return store;
    }

    test('N1 a right side starting with a variable is evaluated', () async {
      final vars = await run(
        r'<<set $rich = $gold >= 100>>',
        DialogueVariableStore()..set('gold', 150),
      );
      expect(vars.getRaw('rich'), isTrue);
      expect(vars.has('gold >= 100'), isFalse);
      final copy = await run(
        r'<<set $copy = $gold>>',
        DialogueVariableStore()..set('gold', 7),
      );
      expect(copy.getRaw('copy'), 7);
    });

    test('N1 a right side with no value leaves the variable alone, and says '
        'so', () async {
      final log = _captureLog();
      final vars = await run(
        r'<<set $x = $missing>>'
        '\n'
        r'<<set $y = nonsense words>>',
        DialogueVariableStore()..set('y', 3),
      );
      expect(vars.has('x'), isFalse);
      expect(vars.getRaw('y'), 3);
      expect(log.where((l) => l.contains('left as it was')), hasLength(2));
    });

    test('N7 a comparison of strings is not a string literal', () async {
      final vars = await run(
        '<<set \$same = "a" == "b">>\n<<set \$name = "Mae">>',
      );
      expect(vars.getRaw('same'), isFalse);
      expect(vars.getRaw('name'), 'Mae');
    });

    test(r'N5 <<set $x to value>>, the standard Yarn form', () async {
      final vars = await run(
        '<<set \$gold to 5>>\n<<set \$total to \$gold * 2 + 1>>',
      );
      expect(vars.getRaw('gold'), 5);
      expect(vars.getRaw('total'), 11);
      expect(vars.has('gold to 5'), isFalse);
    });

    test('N5 a <<set>> that is not an assignment does not parse', () {
      expect(
        () => YarnParser.parse(
          'title: A\n---\n<<set \$gold plus 5>>\n===\n',
          id: 'x',
        ),
        throwsA(isA<YarnParseException>()),
      );
    });

    test('N11 <<declare>> gives a first value, and only a first', () async {
      final fresh = await run(
        '<<declare \$gold = 10>>\n<<declare \$name = "Mae" as String>>',
      );
      expect(fresh.getRaw('gold'), 10);
      expect(fresh.getRaw('name'), 'Mae');

      final saved = await run(
        r'<<declare $gold = 10>>',
        DialogueVariableStore()..set('gold', 99),
      );
      expect(saved.getRaw('gold'), 99, reason: 'a saved value is kept');
    });
  });

  group('N4 the expression evaluator', () {
    late ExpressionEvaluator e;
    setUp(
      () => e = ExpressionEvaluator(
        variables: DialogueVariableStore()
          ..set('a', true)
          ..set('b', false)
          ..set('gold', 12)
          ..set('name', 'Mae'),
        conditions: DialogueConditionRegistry(),
      ),
    );

    test('Yarn keywords and operators', () {
      expect(e.evaluateBool(r'$a and $b'), isFalse);
      expect(e.evaluateBool(r'$b or $a'), isTrue);
      expect(e.evaluateBool(r'$a xor $a'), isFalse);
      expect(e.evaluateBool(r'not $a'), isFalse);
      expect(e.evaluateBool(r'!!$b'), isFalse);
      expect(e.evaluateBool(r'!$b && !(!$a)'), isTrue);
      expect(e.evaluateBool(r'$gold gte 12 and $gold lt 13'), isTrue);
      expect(e.evaluateBool(r'$gold gt 12 or $gold lte 11'), isFalse);
      expect(e.evaluateBool(r'$name eq "Mae"'), isTrue);
      expect(e.evaluateBool(r'$name is "Mae" and $gold neq 3'), isTrue);
      expect(e.evaluateBool(r'$gold == 12.0'), isTrue);
    });

    test('precedence is Yarn\'s: not binds tightest, and before or', () {
      expect(e.evaluateBool(r'$b and $b or $a'), isTrue);
      expect(e.evaluateBool(r'!$b == true'), isTrue);
      expect(e.evaluateBool(r'$gold > 10 == true'), isTrue);
    });

    test('arithmetic', () {
      expect(e.evaluate(r'$gold + 5'), 17);
      expect(e.evaluate(r'$gold - 2 * 3'), 6);
      expect(e.evaluate(r'($gold - 2) * 3'), 30);
      expect(e.evaluate(r'$gold / 4'), 3);
      expect(e.evaluate(r'$gold % 5'), 2);
      expect(e.evaluate(r'-$gold'), -12);
      expect(e.evaluate(r'"Hi " + $name'), 'Hi Mae');
    });

    test('what it cannot read is false, and said in the log', () {
      final log = _captureLog();
      expect(e.evaluateBool(r'visited("Shop")'), isFalse);
      expect(e.evaluateBool('gold > 3'), isFalse, reason: 'no \$');
      expect(e.evaluateBool(r'$a $b'), isFalse, reason: 'left over');
      expect(e.evaluateBool(r'$a and'), isFalse);
      expect(e.evaluateBool(r'($a'), isFalse);
      expect(e.evaluate(r'$gold + true'), isNull);
      expect(log.where((l) => l.contains('could not evaluate')), hasLength(6));
    });
  });

  group('N6 option conditions', () {
    test('-> text <<if cond>> is parsed', () {
      final g = YarnParser.parse(
        'title: Start\n---\n-> Buy the sword <<if \$gold >= 10>> #line:buy\n'
        '-> Leave\n===\n',
        id: 'g',
      );
      final set = g.getNode('Start')!.statements.single as ChoiceSetStatement;
      expect(set.choices.first.rawText, 'Buy the sword');
      expect(set.choices.first.condition, r'$gold >= 10');
      expect(set.choices.first.lineKey, 'buy');
      expect(set.choices.last.condition, isNull);
    });

    test('and decides whether the option is available', () async {
      final r = _runner(
        'title: Start\n---\n-> Buy <<if \$gold >= 10>>\n-> Leave\n===\n',
        vars: DialogueVariableStore()..set('gold', 3),
      );
      unawaited(r.start('Start'));
      await _flush();
      expect(r.signals.choices.value.map((c) => c.isAvailable), [false, true]);
      await r.stop();
    });
  });

  test('N14 escapes in lines are text', () {
    final l =
        YarnParser.parse(
              'title: Start\n---\n'
              r'Item \#5 costs \{3\} \<b\> a\\b #shop'
              '\n===\n',
              id: 'g',
            ).getNode('Start')!.statements.single
            as LineStatement;
    expect(l.rawText, r'Item #5 costs {3} <b> a\b');
    expect(l.tags, ['shop']);
  });

  group('runner sessions', () {
    test('N2 stop() works after a restart', () async {
      final r = _runner(
        'title: A\n---\nA1\nA2\n===\ntitle: B\n---\nB1\nB2\n===\n',
      );
      final first = r.start('A');
      await _flush();
      final second = r.start('B');
      await _flush();
      expect(_line(r), 'B1');
      await r.stop();
      expect(r.isRunning, isFalse);
      expect(_line(r), isNull);
      await first.timeout(const Duration(seconds: 1));
      await second.timeout(const Duration(seconds: 1));
    });

    test('N8 a command pending from the old session does not drive the new '
        'one', () async {
      final gate = Completer<void>();
      final cmds = DialogueCommandRegistry()
        ..register('hold', (_) => gate.future);
      final r = _runner(
        'title: A\n---\n<<hold>>\nA1\n===\ntitle: B\n---\nB1\nB2\n===\n',
        commands: cmds,
      );
      unawaited(r.start('A'));
      await _flush();
      unawaited(r.start('B'));
      await _flush();
      gate.complete();
      await _flush();
      expect(_line(r), 'B1');
      r.advance();
      await _flush();
      expect(_line(r), 'B2');
      await r.stop();
    });

    test('N9 advance from a line listener', () async {
      final r = _runner('title: Start\n---\nOne\nTwo\n===\n');
      final seen = <String>[];
      r.signals.currentLine.addListener(() {
        final l = r.signals.currentLine.value;
        if (l != null) {
          seen.add(l.text);
          r.advance();
        }
      });
      await r.start('Start').timeout(const Duration(seconds: 2));
      expect(seen, ['One', 'Two']);
    });

    test('N9 a choice picked from a choices listener', () async {
      final r = _runner(
        'title: Start\n---\n-> Yes\n    Y\n-> No\n    N\n===\n',
      );
      r.signals.choices.addListener(() {
        if (r.signals.choices.value.isNotEmpty) r.selectChoice(1);
      });
      unawaited(r.start('Start'));
      await _flush();
      expect(_line(r), 'N');
      await r.stop();
    });

    test('N9 stop from a line listener ends the dialogue', () async {
      final r = _runner('title: Start\n---\nOne\nTwo\n===\n');
      r.signals.currentLine.addListener(() {
        if (r.signals.currentLine.value != null) r.stop();
      });
      await r.start('Start').timeout(const Duration(seconds: 2));
      expect(r.isRunning, isFalse);
      expect(r.signals.activeSpeaker.value, isNull);
    });

    test('N10 a throwing command ends the session', () async {
      final cmds = DialogueCommandRegistry()
        ..register('boom', (_) async => throw StateError('x'));
      final r = _runner(
        'title: Start\n---\n<<boom>>\nAfter\n===\n',
        commands: cmds,
      );
      await expectLater(r.start('Start'), throwsStateError);
      expect(r.isRunning, isFalse);
      expect(_line(r), isNull);
    });

    test('N13 an invalid or unavailable choice is ignored', () async {
      final log = _captureLog();
      final r = _runner(
        'title: Start\n---\n-> Yes\n    Y\n-> No #if false\n    N\nAfter\n'
        '===\n',
      );
      unawaited(r.start('Start'));
      await _flush();
      r
        ..selectChoice(5)
        ..selectChoice(-1)
        ..selectChoice(1); // unavailable
      await _flush();
      expect(r.signals.choices.value, hasLength(2), reason: 'still offered');
      expect(log.where((l) => l.contains('cannot be picked')), hasLength(3));
      r.selectChoice(0);
      await _flush();
      expect(_line(r), 'Y');
      await r.stop();
    });

    test('N15 {\$var} in speaker names and command arguments; quoted '
        'arguments stay whole', () async {
      final vars = DialogueVariableStore()
        ..set('npc', 'Mae')
        ..set('item', 'sword');
      final got = <List<String>>[];
      final cmds = DialogueCommandRegistry()
        ..register('give', (ctx) async => got.add(ctx.args));
      final r = _runner(
        'title: Start\n---\n<<give {\$item}>>\n<<give "health potion" 2>>\n'
        '<<give "say \\"hi\\"">>\n{\$npc}: Hello\n===\n',
        vars: vars,
        commands: cmds,
      );
      unawaited(r.start('Start'));
      await _flush();
      expect(got, [
        ['sword'],
        ['health potion', '2'],
        ['say "hi"'],
      ]);
      expect(r.signals.currentLine.value?.character, 'Mae');
      expect(r.signals.activeSpeaker.value, 'Mae');
      await r.stop();
    });

    test('N16 startDialogue with a missing node fails at once, starting '
        'nothing', () async {
      final m = DialogueManager()
        ..parseAndRegister('title: Start\n---\nHi\n===\n', id: 'g');
      Object? caught;
      Object? zoneErr;
      await runZonedGuarded(() async {
        try {
          await m.startDialogue(graphId: 'g', startNode: 'Nope');
        } catch (e) {
          caught = e;
        }
        await _flush();
      }, (e, s) => zoneErr = e);
      expect(caught, isA<ArgumentError>());
      expect(zoneErr, isNull);
      expect(m.runners, isEmpty);
      await m.dispose();
    });
  });

  test('loadFromMap reads names as set does', () {
    final s = DialogueVariableStore()
      ..loadFromMap({'Gold': 5, r'$name': 'Mae'});
    expect(s.getRaw('gold'), 5);
    expect(s.getRaw('name'), 'Mae');
  });

  testWidgets('N12 the typewriter does not split an emoji', (tester) async {
    final m = DialogueManager()
      ..parseAndRegister('title: Start\n---\nA\u{1F600}B\n===\n', id: 'e');
    final r = m.createRunner('e');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DialogueBoxWidget(runner: r, typewriterSpeed: 10)),
      ),
    );
    unawaited(r.start('Start'));
    await tester.pump();
    final shown = <String>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.startsWith('A'))
          .firstOrNull;
      if (text != null) shown.add(text);
    }
    expect(shown, containsAllInOrder(['A', 'A\u{1F600}', 'A\u{1F600}B']));
    await r.stop();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await m.dispose();
  });

  group('localization', () {
    test(
      'N3 DialogueLocalizer.setLocale switches once the file loads',
      () async {
        final loc = DialogueLocalizer(
          manager: LocalizationManager(),
          basePath: 'assets/d/dialogue',
        );
        final bundle = _Bundle({
          'assets/d/dialogue_fr.json': '{"hi": "Salut"}',
          'assets/d/dialogue_en.json': '{"hi": "Hello"}',
        });
        await loc.setLocale(const Locale('fr'), bundle: bundle);
        expect(loc.currentLocale, const Locale('fr'));
        expect(loc.localize('hi'), 'Salut');

        // The current locale ('en' at first) is loaded when it has no strings.
        final fresh = DialogueLocalizer(basePath: 'assets/d/dialogue');
        await fresh.setLocale(const Locale('en'), bundle: bundle);
        expect(fresh.localize('hi'), 'Hello');

        // Back to one already loaded: a switch, no file needed.
        await loc.loadLocale(const Locale('en'), bundle: bundle);
        expect(loc.localize('hi'), 'Hello');
        await loc.setLocale(const Locale('fr'));
        expect(loc.localize('hi'), 'Salut');
      },
    );

    test('L17 two files for one locale and namespace merge', () async {
      final l10n = LocalizationManager();
      final b = _Bundle({
        'ui_en.json': '{"start": "Start", "back": "Back"}',
        'items_en.json': '{"sword": "Sword", "back": "Return"}',
      });
      await l10n.load(const Locale('en'), 'ui_en.json', bundle: b);
      await l10n.load(const Locale('en'), 'items_en.json', bundle: b);
      expect(l10n.t('start'), 'Start');
      expect(l10n.t('sword'), 'Sword');
      expect(l10n.t('back'), 'Return', reason: 'the later file wins');
      expect(l10n.hasTable(const Locale('en')), isTrue);
      expect(l10n.hasTable(const Locale('en'), ns: 'dialogue'), isFalse);
    });

    test('L18 plurals of counts with a fraction, or none at all', () {
      expect(
        StringInterpolator.process('{n, plural, =1{one km} other{{n} km}}', {
          'n': 1.5,
        }),
        '1.5 km',
      );
      expect(
        StringInterpolator.process('{n, plural, one{x} other{{n} km}}', {
          'n': 2.5,
        }),
        '2.5 km',
      );
      expect(
        StringInterpolator.process('{n, plural, =1{one} other{many}}', {
          'n': 1.0,
        }),
        'one',
      );
      expect(
        StringInterpolator.process('{n, plural, =2{two} other{lots}}', {
          'n': double.infinity,
        }),
        'lots',
      );
      expect(
        StringInterpolator.process('{n, plural, =3{three} other{{n}}}', {
          'n': '3',
        }),
        'three',
      );
    });

    test('L19 a fallback with a country falls back to its language', () {
      final l = LocalizationManager(fallbackLocale: const Locale('en', 'US'))
        ..registerMap(const Locale('en'), {'hi': 'Hello'})
        ..registerMap(const Locale('en', 'US'), {'color': 'Color'})
        ..setLocale(const Locale('fr'));
      expect(l.t('hi'), 'Hello');
      expect(l.t('color'), 'Color');
    });

    test('L20 locales with scripts keep their own tables', () {
      const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      const hansCn = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      );
      final l = LocalizationManager()
        ..registerMap(hans, {'hi': 'A'})
        ..registerMap(hant, {'hi': 'B'})
        ..registerMap(const Locale('zh'), {'bye': 'C'});
      expect(l.t('hi', locale: hans), 'A');
      expect(l.t('hi', locale: hant), 'B');
      expect(l.t('hi', locale: hansCn), 'A', reason: 'zh_Hans_CN → zh_Hans');
      expect(l.t('bye', locale: hansCn), 'C', reason: '… → zh');
      expect(LocalizationManager.tagOf(hansCn), 'zh_Hans_CN');
    });
  });
}
