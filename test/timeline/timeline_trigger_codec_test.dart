// A Timeline Trigger saves and loads every field: one a codec did not write
// would come back as its default after every editor save.

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  final definitions = BuiltInComponents.registry();

  test('every field of a trigger survives a save and a load', () {
    final trigger = TimelineTriggerComponent(
      width: 300,
      height: 40,
      target: const EntityTarget.name('Hero'),
      playerName: 'Door',
      enterAction: TimelineTriggerAction.reverse,
      exitAction: TimelineTriggerAction.stop,
      oneShot: true,
    );
    final saved = definitions.encode(trigger)!;
    final back = definitions.decode(saved) as TimelineTriggerComponent;
    expect(
      (
        back.width,
        back.height,
        back.target,
        back.playerName,
        back.enterAction,
        back.exitAction,
        back.oneShot,
      ),
      (
        300.0,
        40.0,
        const EntityTarget.name('Hero'),
        'Door',
        TimelineTriggerAction.reverse,
        TimelineTriggerAction.stop,
        true,
      ),
    );
    expect(definitions.encode(back), saved);
  });

  test('a trigger is sized and scaled like a shape', () {
    final definition = definitions.definitionByType(
      'TimelineTriggerComponent',
    )!;
    final trigger = TimelineTriggerComponent(width: 100, height: 50);
    expect(definition.extent!.sizeOf(trigger), const Size(100, 50));
    expect(definition.extent!.scale(trigger, -2, 0.5), isTrue);
    expect((trigger.width, trigger.height), (200.0, 25.0));
  });

  test('every field of a player survives a save and a load', () {
    final player = TimelinePlayerComponent(
      timelinePath: 'cut.timeline.json',
      playOnStart: true,
      speed: -1.5,
      wrap: TimelineWrapChoice.pingPong,
      listenSignal: 'go',
      from: 0.5,
      to: 2,
    );
    final saved = definitions.encode(player)!;
    final back = definitions.decode(saved) as TimelinePlayerComponent;
    expect(
      (
        back.timelinePath,
        back.playOnStart,
        back.speed,
        back.wrap,
        back.listenSignal,
        back.from,
        back.to,
      ),
      (
        'cut.timeline.json',
        true,
        -1.5,
        TimelineWrapChoice.pingPong,
        'go',
        0.5,
        2.0,
      ),
    );
    expect(definitions.encode(back), saved);
  });
}
