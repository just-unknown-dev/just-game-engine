// Reloading a timeline file: players of it that were playing — set going at
// run time by a trigger, a signal or an animator, not only on start — play
// the new one from its start; players that were waiting go on waiting.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late TimelineSystem system;
  var loads = 0;

  setUp(() {
    loads = 0;
    world = World(extensions: [BuiltInComponents.extension]);
    registerSpriteSystems(
      world,
      timelineLoader: (_) async {
        loads++;
        return TimelineAsset(duration: 4);
      },
    );
    system = world.systems.whereType<TimelineSystem>().single;
  });
  tearDown(() => world.dispose());

  Future<void> settle() async {
    world.update(0);
    await pumpEventQueue();
    world.update(0);
  }

  test(
    'a player started at run time plays the new one from its start',
    () async {
      final player = TimelinePlayerComponent(timelinePath: 'cut.timeline.json');
      world.createEntityWithComponents([player]);
      await settle();
      player.play(); // as a trigger would
      world.update(1.5);
      expect(player.time, closeTo(1.5, 1e-9));

      system.reload('cut.timeline.json');
      await settle();
      world.update(0.25);
      expect(loads, 2);
      expect(player.isPlaying, isTrue);
      expect(player.time, closeTo(0.25, 1e-9));
    },
  );

  test('a player that was waiting goes on waiting', () async {
    final player = TimelinePlayerComponent(timelinePath: 'cut.timeline.json');
    world.createEntityWithComponents([player]);
    await settle();
    system.reload('cut.timeline.json');
    await settle();
    world.update(0.25);
    expect(player.isPlaying, isFalse);
    expect(player.time, 0);
  });
}
