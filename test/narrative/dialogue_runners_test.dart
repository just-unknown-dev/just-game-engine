// Dialogue: a repeating trigger fires once per entry, finished runners are let
// go; and the failures that used to vanish — a broken localization file, an
// expression that cannot be evaluated, a lost achievement restore — are
// reported.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _shop = '''
title: Start
---
<<entered>>
Keeper: Welcome back.
===
''';

/// Everything debugPrint says during the test.
List<String> _captureLog() {
  final lines = <String>[];
  final printer = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  addTearDown(() => debugPrint = printer);
  return lines;
}

/// A bundle holding only [files]; anything else is missing, as a real
/// bundle reports it.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dialogue triggers', () {
    late DialogueManager manager;
    late World world;
    late Entity player;
    var entries = 0;

    Entity trigger({bool once = false}) => world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 0, 0)),
      DialogueTriggerComponent(
        graphId: 'shop',
        triggerOnce: once,
        triggerRadius: 50,
      ),
    ]);

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        world.update(1 / 60);
      }
      await pumpEventQueue();
    }

    setUp(() {
      entries = 0;
      manager = DialogueManager()..parseAndRegister(_shop, id: 'shop');
      manager.commands.register('entered', (_) async => entries++);
      world = World()..initialize();
      world.addSystem(DialogueSystem(manager: manager));
      player = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        TagComponent(EngineTags.player),
      ]);
    });

    tearDown(() async {
      world.dispose();
      await manager.dispose();
    });

    test('a repeating trigger fires as the player steps in, not every '
        'frame they stay', () async {
      trigger();
      await frames(10);
      expect(entries, 1);

      player.getComponent<TransformComponent>()!.position.x = 1000;
      await frames(3);
      expect(entries, 1);

      player.getComponent<TransformComponent>()!.position.x = 0;
      await frames(10);
      expect(entries, 2, reason: 'once more for the second entry');
    });

    test('a one-time trigger fires once, entries or not', () async {
      trigger(once: true);
      await frames(5);
      player.getComponent<TransformComponent>()!.position.x = 1000;
      await frames(1);
      player.getComponent<TransformComponent>()!.position.x = 0;
      await frames(5);
      expect(entries, 1);
    });

    test('runners bound to destroyed entities are let go', () async {
      final npc = world.createEntityWithComponents([
        TransformComponent(position: Vector3(500, 0, 0)),
        DialogueComponent(graphId: 'shop'),
      ]);
      final runner = manager.createRunnerForEntity(npc.id, 'shop');
      await frames(1);
      expect(manager.runners, contains(runner));

      world.destroyEntity(npc);
      await frames(1);
      expect(manager.boundEntityIds, isEmpty);
      expect(manager.runners, isNot(contains(runner)));
    });
  });

  group('dialogue runners', () {
    late DialogueManager manager;

    setUp(
      () => manager = DialogueManager()..parseAndRegister(_shop, id: 'shop'),
    );
    tearDown(() => manager.dispose());

    test('one started by startDialogue is let go when it ends', () async {
      final runner = await manager.startDialogue(graphId: 'shop');
      await pumpEventQueue();
      expect(manager.runners, contains(runner));
      expect(manager.isAnyDialogueActive.value, isTrue);

      runner.advance();
      await pumpEventQueue();
      expect(manager.runners, isNot(contains(runner)));
      expect(manager.isAnyDialogueActive.value, isFalse);
      expect(runner.isRunning, isFalse);
    });

    test('an entity\'s runner, replaced mid-dialogue, is let go when its '
        'dialogue ends', () async {
      final first = manager.createRunnerForEntity(7, 'shop');
      unawaited(first.start('Start'));
      await pumpEventQueue();

      final second = manager.createRunnerForEntity(7, 'shop');
      expect(manager.getRunnerForEntity(7), same(second));
      expect(manager.runners, contains(first), reason: 'still talking');

      first.advance();
      await pumpEventQueue();
      expect(manager.runners, isNot(contains(first)));
      expect(manager.runners, contains(second));
    });

    test('replaced while idle, it is let go at once', () async {
      final first = manager.createRunnerForEntity(7, 'shop');
      manager.createRunnerForEntity(7, 'shop');
      expect(manager.runners, isNot(contains(first)));
    });

    test('one the game created itself stays until disposed', () async {
      final runner = manager.createRunner('shop');
      unawaited(runner.start('Start'));
      await pumpEventQueue();
      runner.advance();
      await pumpEventQueue();
      expect(manager.runners, contains(runner));
      await manager.disposeRunner(runner);
      expect(manager.runners, isNot(contains(runner)));
    });
  });

  group('failures are reported, not taken for something else', () {
    test('a localization file that is there but broken', () async {
      final log = _captureLog();
      final l10n = LocalizationManager();
      await l10n.loadAll(
        const [Locale('en'), Locale('fr'), Locale('de')],
        'assets/l10n/ui_{locale}.json',
        bundle: _Bundle({
          'assets/l10n/ui_en.json': '{"hello": "Hello"}',
          'assets/l10n/ui_fr.json': '{"hello": ', // cut off
        }),
      );
      expect(log.where((l) => l.contains('ui_fr.json')), hasLength(1));
      expect(log.where((l) => l.contains('ui_de.json')), isEmpty);
      expect(l10n.t('hello'), 'Hello');
    });

    test('a dialogue file that is there but broken', () async {
      final log = _captureLog();
      final localizer = DialogueLocalizer(basePath: 'assets/d/dialogue');
      await localizer.loadLocale(
        const Locale('fr', 'CA'),
        bundle: _Bundle({
          'assets/d/dialogue_fr.json': '[1, 2]', // not an object
          'assets/d/dialogue_en.json': '{"shop.hello": "Welcome"}',
        }),
      );
      // fr_CA is missing — quiet; fr is broken — reported; en is used.
      expect(log.where((l) => l.contains('dialogue_fr_CA.json')), isEmpty);
      expect(log.where((l) => l.contains('dialogue_fr.json')), hasLength(1));
      expect(log.where((l) => l.contains('dialogue_en.json')), isEmpty);
    });

    test('an expression that cannot be evaluated', () {
      final log = _captureLog();
      final evaluator = ExpressionEvaluator(
        variables: DialogueVariableStore(),
        conditions: DialogueConditionRegistry()
          ..register('broken', (_) => throw StateError('no such quest')),
      );
      expect(evaluator.evaluateBool('[broken]'), isFalse);
      expect(evaluator.evaluate('[broken] && true'), isNull);
      expect(log.where((l) => l.contains('could not evaluate')), hasLength(2));
      // An unmet condition is not a failure, and says nothing.
      expect(evaluator.evaluateBool(r'$gold > 10'), isFalse);
      expect(log.where((l) => l.contains('could not evaluate')), hasLength(2));
    });
  });
}
