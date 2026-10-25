// Timeline playback fixes from the 2.0.0-dev.1 release audit: big
// ping-pong steps, re-entrant signals, nested blocks' laps and end states,
// blocks reaching the end of a timeline, the ping-pong direction, a range
// pulled behind the playhead, zero-length timelines, instant blocks, and
// the player component's forwards() and new paths.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

const _lin = KeyInterpolation.linear;

PropertyTrack _x(
  List<TimelineKey> keys, {
  String channel = 'x',
  PropertyTrackMode mode = PropertyTrackMode.absolute,
}) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: channel,
  mode: mode,
  curve: KeyCurve(keys),
);

TimelinePlayback _pingPong(World w) => TimelinePlayback(
  TimelineAsset(
    duration: 1,
    wrap: TimelineWrap.pingPong,
    tracks: [
      _x([
        const TimelineKey(time: 0, value: 0.0, interpolation: _lin),
        const TimelineKey(time: 1, value: 100.0),
      ]),
    ],
  ),
  world: w,
  owner: w.createEntityWithComponents([TransformComponent()]),
)..play();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  test('T21 a handler destroying a later player does not throw', () {
    registerSpriteSystems(world);
    final system = world.systems.whereType<TimelineSystem>().single;
    world.createEntityWithComponents([
      TimelinePlayerComponent(
        playOnStart: true,
        inline: TimelineAsset(
          duration: 1,
          tracks: [
            EventTrack(events: const [TimelineEvent(time: 0.1, name: 'boom')]),
          ],
        ),
      ),
    ]);
    final victim = world.createEntityWithComponents([
      TimelinePlayerComponent(
        playOnStart: true,
        inline: TimelineAsset(duration: 1),
      ),
    ]);
    system.events.listen((e) {
      if (e.name == 'boom') world.destroyEntity(victim);
    });
    world.update(1 / 60);
    expect(() => world.update(0.2), returnsNormally);
    expect(victim.isAlive, isFalse);
  });

  test('T22 one big ping-pong step lands where many small ones do', () {
    final big = _pingPong(world)..update(5.25);
    final small = _pingPong(world);
    for (var i = 0; i < 21; i++) {
      small.update(0.25);
    }
    expect(small.time, closeTo(0.75, 1e-9));
    expect(big.time, closeTo(small.time, 1e-9));
    big.update(0.1);
    small.update(0.1);
    expect(
      big.time,
      closeTo(small.time, 1e-9),
      reason: 'and heads the same way',
    );
  });

  test('T23 a signal listener can relay another signal', () {
    final signals = TimelineSignals();
    final heard = <String>[];
    Object? zoneErr;
    runZonedGuarded(() {
      signals.stream.listen((s) {
        if (s == 'boss_defeated') signals.emit('open_gate');
      });
      signals.stream.listen(heard.add);
      signals.emit('boss_defeated');
    }, (e, s) => zoneErr = e);
    expect(zoneErr, isNull);
    expect(heard, ['boss_defeated', 'open_gate']);
  });

  test('T24 a looping nested block of three laps ticks three times, either '
      'way', () async {
    TimelineAsset parent() => TimelineAsset(
      duration: 4,
      tracks: [
        NestedTimelineTrack(
          blocks: const [
            TimelineBlock(
              start: 0.5,
              length: 3,
              value: 'lap.timeline.json',
              loop: true,
            ),
          ],
        ),
      ],
    );
    final lap = TimelineAsset(
      duration: 1,
      tracks: [
        EventTrack(
          events: const [
            TimelineEvent(time: 0, name: 'start'),
            TimelineEvent(time: 1, name: 'end'),
          ],
        ),
      ],
    );
    Future<List<String>> run({required bool backwards}) async {
      final fired = <String>[];
      final p = TimelinePlayback(
        parent(),
        world: world,
        owner: world.createEntity(),
        loader: (_) async => lap,
        onEvent: (e) => fired.add(e.name),
      )..speed = backwards ? -1 : 1;
      p.play();
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 10; i++) {
        p.update(0.5);
      }
      return fired;
    }

    final forwards = await run(backwards: false);
    expect(forwards.where((n) => n == 'start'), hasLength(3));
    expect(forwards.where((n) => n == 'end'), hasLength(3));
    final back = await run(backwards: true);
    expect(back.where((n) => n == 'start'), hasLength(3));
    expect(back.where((n) => n == 'end'), hasLength(3));
  });

  test('T25 a nested block stepped clean over leaves its timeline at its '
      'end', () async {
    final door = world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 0, 0)),
    ], name: 'Door');
    final slide = TimelineAsset(
      duration: 1,
      tracks: [
        _x([
          const TimelineKey(time: 0, value: 0.0, interpolation: _lin),
          const TimelineKey(time: 1, value: 10.0),
        ]),
      ],
    );
    final p = TimelinePlayback(
      TimelineAsset(
        duration: 4,
        tracks: [
          NestedTimelineTrack(
            binding: const TrackBinding.name('Door'),
            blocks: const [
              TimelineBlock(
                start: 1,
                length: 0.5,
                value: 's.timeline.json',
                speed: 2,
              ),
            ],
          ),
        ],
      ),
      world: world,
      owner: world.createEntity(),
      loader: (_) async => slide,
    )..play();
    await Future<void>.delayed(Duration.zero);
    p.update(0.9);
    expect(door.getComponent<TransformComponent>()!.position.x, 100);
    p.update(0.7);
    expect(
      door.getComponent<TransformComponent>()!.position.x,
      closeTo(10, 1e-6),
    );
  });

  test('T26 forwards after reverse turns round, keeping a relative base', () {
    registerSpriteSystems(world);
    final player = TimelinePlayerComponent(
      inline: TimelineAsset(
        duration: 1,
        tracks: [
          _x(
            [
              const TimelineKey(time: 0, value: 10.0, interpolation: _lin),
              const TimelineKey(time: 1, value: 74.0),
            ],
            channel: 'y',
            mode: PropertyTrackMode.relative,
          ),
        ],
      ),
    );
    final door = world.createEntityWithComponents([
      TransformComponent(),
      player,
    ]);
    double y() => door.getComponent<TransformComponent>()!.position.y;
    world.update(0);
    player.forwards();
    world.update(1);
    final a = y();
    player.reverse();
    world.update(1);
    final b = y();
    player.forwards();
    world.update(1);
    final c = y();
    expect(a, closeTo(74, 1e-6));
    expect(b, closeTo(10, 1e-6));
    expect(c, closeTo(a, 1e-6));
  });

  group('T27 a block reaching the end of a once timeline holds there', () {
    test('activation', () {
      final lamp = world.createEntity(name: 'Lamp')..isActive = false;
      final p = TimelinePlayback(
        TimelineAsset(
          duration: 2,
          tracks: [
            ActivationTrack(
              binding: const TrackBinding.name('Lamp'),
              blocks: const [TimelineBlock(start: 1, length: 1)],
            ),
          ],
        ),
        world: world,
        owner: world.createEntity(),
      )..play();
      p.update(1.5);
      expect(lamp.isActive, isTrue);
      p.update(1.0);
      expect(p.isFinished, isTrue);
      expect(lamp.isActive, isTrue, reason: 'as the timeline left it');
    });

    test('sprite clip — but a loop goes on to its start', () {
      final sprite = SpriteAnimationComponent(
        atlasPath: 'a.json',
        clip: 'idle',
      );
      final e = world.createEntityWithComponents([sprite]);
      TimelinePlayback play(TimelineWrap wrap) => TimelinePlayback(
        TimelineAsset(
          duration: 2,
          wrap: wrap,
          tracks: [
            SpriteClipTrack(
              blocks: const [TimelineBlock(start: 1, length: 1, value: 'wave')],
            ),
          ],
        ),
        world: world,
        owner: e,
      )..play();
      final once = play(TimelineWrap.once)..update(2);
      expect(once.isFinished, isTrue);
      expect(sprite.playingClip, 'wave');
      once.dispose();
      expect(
        sprite.playingClip,
        'idle',
        reason: 'given back when the play ends',
      );

      final loop = play(TimelineWrap.loop)..seek(1.5);
      expect(sprite.playingClip, 'wave');
      loop.seek(2);
      expect(sprite.playingClip, 'idle', reason: 'its end is its start');
      loop.dispose();
    });
  });

  test('T28 a sprite block spanning a loop restarts its clip each lap', () {
    final sprite = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle');
    final e = world.createEntityWithComponents([sprite]);
    final p = TimelinePlayback(
      TimelineAsset(
        duration: 1,
        wrap: TimelineWrap.loop,
        tracks: [
          SpriteClipTrack(
            blocks: const [TimelineBlock(start: 0, length: 1, value: 'wave')],
          ),
        ],
      ),
      world: world,
      owner: e,
    )..play();
    p.update(0.5);
    sprite
      ..elapsed = 0.9
      ..isComplete = true;
    p.update(0.25);
    expect(sprite.elapsed, 0.9, reason: 'not restarted inside a lap');
    p.update(0.5);
    expect(sprite.playingClip, 'wave');
    expect(sprite.elapsed, 0);
  });

  test(
    'T28 a skeletal clip block spanning a loop restarts its clip each lap',
    () {
      world.context.install(Graphics3D());
      final player = AnimationPlayerComponent(clip: 'idle');
      final e = world.createEntityWithComponents([player]);
      final p = TimelinePlayback(
        TimelineAsset(
          duration: 1,
          wrap: TimelineWrap.loop,
          tracks: [
            SkeletalClipTrack(
              blocks: const [TimelineBlock(start: 0, length: 1, value: 'wave')],
            ),
          ],
        ),
        world: world,
        owner: e,
      )..play();
      p.update(0.5);
      expect(player.playingClip, 'wave');
      player.time = 0.9;
      p.update(0.25);
      expect(player.time, 0.9, reason: 'not restarted inside a lap');
      p.update(0.5);
      expect(player.time, 0);
    },
    tags: ['graphics3d'],
  );

  test('T29 a new path then play() plays the new timeline', () async {
    final files = {
      'a': TimelineAsset(duration: 1),
      'b': TimelineAsset(duration: 2),
    };
    registerSpriteSystems(world, timelineLoader: (p) async => files[p]!);
    final player = TimelinePlayerComponent(timelinePath: 'a');
    world.createEntityWithComponents([player]);
    world.update(1 / 60);
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    player.timelinePath = 'b';
    player.play();
    world.update(1 / 60);
    await Future<void>.delayed(Duration.zero);
    world.update(0.5);
    expect(player.playback?.asset.duration, 2);
    expect(player.isPlaying, isTrue);
    expect(player.time, closeTo(0.5, 1e-9));
  });

  group('T30 the ping-pong direction', () {
    test('stop and seek send it forwards again', () {
      final p = _pingPong(world)..update(1.5);
      p
        ..stop()
        ..seek(0.25)
        ..play()
        ..update(0.25);
      expect(p.time, closeTo(0.5, 1e-9));

      final q = _pingPong(world)..update(1.5);
      q
        ..seek(0.25)
        ..update(0.25);
      expect(q.time, closeTo(0.5, 1e-9));
    });

    test('switched to loop on its way back, it plays forwards', () {
      final p = _pingPong(world)..update(1.5);
      p.wrap = TimelineWrap.loop;
      p.update(0.25);
      expect(p.time, closeTo(0.75, 1e-9));
    });
  });

  test('T31 a range end pulled behind the playhead fires nothing '
      'backwards', () {
    final fired = <String>[];
    final p = TimelinePlayback(
      TimelineAsset(
        duration: 2,
        tracks: [
          EventTrack(events: const [TimelineEvent(time: 1.3, name: 'late')]),
        ],
      ),
      world: world,
      owner: world.createEntity(),
      onEvent: (f) => fired.add(f.name),
    )..play();
    p.update(1.5);
    p.range = (0, 1.2);
    p.update(0.1);
    expect(fired, ['late']);
    expect(p.time, 1.2);
    expect(p.isFinished, isTrue);
  });

  test('T32 a colour field keyed without the colour flag blends as one', () {
    final sprite = SpriteAnimationComponent(atlasPath: 'a.json');
    final e = world.createEntityWithComponents([sprite]);
    final track = PropertyTrack.fromJson({
      'kind': 'property',
      'component': 'SpriteAnimationComponent',
      'field': 'tint',
      'keys': [
        {'t': 0, 'v': 0xFF000000, 'i': 'linear'},
        {'t': 1, 'v': 0xFFFF0000},
      ],
    });
    final p = TimelinePlayback(
      TimelineAsset(duration: 1, tracks: [track]),
      world: world,
      owner: e,
    )..play();
    expect(() => p.update(0.5), returnsNormally);
    expect(sprite.tint, isNotNull);
    expect(sprite.tint!.toARGB32(), isNot(0xFF000000));
  });

  test('T33 a zero-length timeline fires and shows its one moment, each '
      'play', () {
    final fired = <String>[];
    final e = world.createEntityWithComponents([TransformComponent()]);
    final p = TimelinePlayback(
      TimelineAsset(
        duration: 0,
        tracks: [
          EventTrack(events: const [TimelineEvent(time: 0, name: 'go')]),
          _x([const TimelineKey(time: 0, value: 42.0)]),
        ],
      ),
      world: world,
      owner: e,
      onEvent: (f) => fired.add(f.name),
    )..play();
    p.update(1 / 60);
    expect(fired, ['go']);
    expect(p.isFinished, isTrue);
    expect(e.getComponent<TransformComponent>()!.position.x, 42);
    p
      ..play()
      ..update(1 / 60);
    expect(fired, ['go', 'go']);
  });

  test('T34 an instant block counts where it starts, not its drawn length', () {
    final a = TimelineAsset(
      duration: 2,
      tracks: [
        AudioTrack(blocks: const [TimelineBlock(start: 1.9, value: 'a.wav')]),
      ],
    );
    expect(a.validate(), isEmpty);
    expect(a.contentEnd, 1.9);
  });

  test('T35 a cue on a ping-pong\'s start plays every time round', () {
    final heard = <String>[];
    world.context.timelineAudio = (c, at, cue) => heard.add(cue.value);
    final p = TimelinePlayback(
      TimelineAsset(
        duration: 1,
        wrap: TimelineWrap.pingPong,
        tracks: [
          AudioTrack(
            blocks: const [
              TimelineBlock(start: 0, value: 'a.wav'),
              TimelineBlock(start: 0.5, value: 'b.wav'),
            ],
          ),
        ],
      ),
      world: world,
      owner: world.createEntity(),
    )..play();
    for (var i = 0; i < 9; i++) {
      p.update(0.5);
    }
    expect(heard.where((s) => s == 'a.wav'), hasLength(3));
    expect(heard.where((s) => s == 'b.wav'), hasLength(3), reason: 'forwards');
  });
}
