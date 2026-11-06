// Controlling a playback while it runs: a pause from an event handler ends
// the step on that event; a direction asked for on a ping-pong's way back is
// the direction it goes; a trigger's restart plays as authored; and the
// laps a playback has run, for an animator's exit time.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

PropertyTrack _x() => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: 'x',
  curve: KeyCurve([
    const TimelineKey(
      time: 0,
      value: 0.0,
      interpolation: KeyInterpolation.linear,
    ),
    const TimelineKey(time: 1, value: 100.0),
  ]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  setUp(() => world = World(extensions: [BuiltInComponents.extension]));
  tearDown(() => world.dispose());

  group('pause from an event handler', () {
    late TimelinePlayback playback;
    late List<String> fired;

    setUp(() {
      fired = [];
      playback = TimelinePlayback(
        TimelineAsset(
          duration: 1,
          tracks: [
            EventTrack(
              events: const [
                TimelineEvent(time: 0.2, name: 'wait_for_input'),
                TimelineEvent(time: 0.25, name: 'door_open'),
              ],
            ),
          ],
        ),
        world: world,
        owner: world.createEntity(),
        onEvent: (e) {
          fired.add(e.name);
          if (e.name == 'wait_for_input') playback.pause();
        },
      )..play();
    });

    test('ends the step: later events in it do not fire', () {
      playback.update(0.15);
      playback.update(0.15); // 0.15 → 0.30 passes both
      expect(fired, ['wait_for_input']);
      expect(playback.isPlaying, isFalse);
    });

    test('parks the playhead on the event, so playing on does not fire it '
        'again', () {
      playback.update(0.15);
      playback.update(0.15);
      expect(playback.time, closeTo(0.2, 1e-9));
      playback.play();
      playback.update(0.1);
      expect(fired, ['wait_for_input', 'door_open']);
      expect(playback.time, closeTo(0.3, 1e-9));
    });
  });

  group('a direction asked for on a ping-pong', () {
    late TimelinePlayerComponent player;

    setUp(() {
      player = TimelinePlayerComponent();
      final owner = world.createEntityWithComponents([
        TransformComponent(),
        player,
      ]);
      player.playback = TimelinePlayback(
        TimelineAsset(duration: 1, wrap: TimelineWrap.pingPong, tracks: [_x()]),
        world: world,
        owner: owner,
      )..play();
      player.playback!.update(1.5); // at 0.5, on the way back
      expect(player.time, closeTo(0.5, 1e-9));
    });

    test('reverse on the way back carries on back', () {
      player.reverse();
      player.playback!.update(0.1);
      expect(player.time, closeTo(0.4, 1e-9));
    });

    test('forwards on the way back turns it round', () {
      player.forwards();
      player.playback!.update(0.1);
      expect(player.time, closeTo(0.6, 1e-9));
    });
  });

  test('a trigger restarts a player as authored, backwards when its speed '
      'is negative', () {
    registerSpriteSystems(world);
    world.createEntityWithComponents([
      TransformComponent(),
      TagComponent('player'),
    ]);
    final player = TimelinePlayerComponent(
      speed: -1,
      inline: TimelineAsset(duration: 1, tracks: [_x()]),
    );
    world.createEntityWithComponents([
      TransformComponent(),
      TimelineTriggerComponent(enterAction: TimelineTriggerAction.restart),
      player,
    ]);
    world.update(0.1);
    expect(player.playingSpeed, -1);
    expect(player.time, closeTo(0.9, 1e-9), reason: 'from the end, back');
  });

  test('a trigger restart forgets a direction an earlier action set', () {
    final player = TimelinePlayerComponent();
    final owner = world.createEntityWithComponents([player]);
    player.playback = TimelinePlayback(
      TimelineAsset(duration: 1),
      world: world,
      owner: owner,
    );
    player.reverse();
    expect(player.playingSpeed, -1);
    player.resetSpeed();
    expect(player.playingSpeed, 1);
    player.playback!.dispose();
  });

  group('laps', () {
    TimelinePlayback playing(TimelineWrap wrap) => TimelinePlayback(
      TimelineAsset(duration: 1, wrap: wrap),
      world: world,
      owner: world.createEntity(),
    )..play();

    test('count on past one for a loop, where progress folds back', () {
      final p = playing(TimelineWrap.loop)..update(2.5);
      expect(p.laps, closeTo(2.5, 1e-9));
      expect(p.progress, closeTo(0.5, 1e-9));
    });

    test('count each way of a ping-pong', () {
      final p = playing(TimelineWrap.pingPong)..update(1.5);
      expect(p.laps, closeTo(1.5, 1e-9));
    });

    test('stop at one for a once timeline, and start over with it', () {
      final p = playing(TimelineWrap.once)..update(2);
      expect(p.laps, closeTo(1, 1e-9));
      p.play();
      expect(p.laps, 0);
      p.update(0.25);
      p.stop();
      expect(p.laps, 0);
    });

    test('count a step many laps long', () {
      final p = playing(TimelineWrap.loop)..update(10.25);
      expect(p.laps, closeTo(10.25, 1e-9));
    });
  });

  test('direction is the way the clock runs, and setting it turns a '
      'ping-pong on its way back', () {
    final p = TimelinePlayback(
      TimelineAsset(duration: 1, wrap: TimelineWrap.pingPong),
      world: world,
      owner: world.createEntity(),
    )..play();
    expect(p.direction, 1);
    p.update(1.5);
    expect(p.direction, -1);
    p.direction = 1;
    expect(p.speed, 1);
    p.update(0.1);
    expect(p.time, closeTo(0.6, 1e-9));
    p.direction = -1;
    expect(p.speed, -1);
  });
}
