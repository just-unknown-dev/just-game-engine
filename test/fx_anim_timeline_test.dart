// Timeline regressions: players dropped without ending, restarts that ran
// the wrong way, event handlers whose stop was overwritten, nested
// timelines that lost events, newer files read as older ones, and tracks
// that could not be read without saying why.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

/// A timeline whose only track moves `TransformComponent.position.y` from 0
/// to [by] over one second, relative to where it starts.
TimelineAsset _slide({
  double by = -64,
  TimelineWrap wrap = TimelineWrap.once,
}) => TimelineAsset(
  duration: 1,
  wrap: wrap,
  tracks: [
    PropertyTrack(
      component: 'TransformComponent',
      field: 'position',
      channel: 'y',
      mode: PropertyTrackMode.relative,
      curve: KeyCurve([
        const TimelineKey(
          time: 0,
          value: 0.0,
          interpolation: KeyInterpolation.linear,
        ),
        TimelineKey(time: 1, value: by),
      ]),
    ),
  ],
);

TimelineAsset _events(List<(double, String)> events, {double duration = 1}) =>
    TimelineAsset(
      duration: duration,
      tracks: [
        EventTrack(
          events: [
            for (final (time, name) in events)
              TimelineEvent(time: time, name: name),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  double yOf(Entity e) => e.getComponent<TransformComponent>()!.position.y;

  group('the player system (C10)', () {
    setUp(() => registerSpriteSystems(world));

    test('a pooled entity switched off and on keeps playing', () {
      final player = TimelinePlayerComponent(
        playOnStart: true,
        inline: _slide(by: -10, wrap: TimelineWrap.loop),
      );
      final coin = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        player,
      ]);
      world.update(_dt);
      world.update(0.25);
      expect(player.isPlaying, isTrue);
      coin.isActive = false;
      world.createEntity(); // the world's structure changes meanwhile
      world.update(0.25);
      coin.isActive = true;
      world.createEntity();
      world.update(0.25);
      expect(player.isPlaying, isTrue, reason: 'the bob carries on');
      final before = yOf(coin);
      world.update(0.1);
      expect(yOf(coin), isNot(before));
    });

    Entity cutscene(VirtualCameraComponent camera) {
      world.createEntityWithComponents([camera], name: 'Close');
      return world.createEntityWithComponents([
        TimelinePlayerComponent(
          playOnStart: true,
          inline: TimelineAsset(
            duration: 5,
            tracks: [
              CameraShotTrack(
                blocks: const [
                  TimelineBlock(
                    start: 0,
                    length: 5,
                    value: 'Close',
                    amount: 100,
                  ),
                ],
              ),
            ],
          ),
        ),
      ]);
    }

    test('a cutscene destroyed mid-shot gives the camera its priority '
        'back', () {
      final camera = VirtualCameraComponent(priority: 1);
      final scene = cutscene(camera);
      world.update(_dt);
      world.update(0.5);
      expect(camera.priority, 101);
      world.destroyEntity(scene);
      world.update(_dt);
      expect(camera.priority, 1);
    });

    test('a player taken off its entity mid-shot ends its timeline', () {
      final camera = VirtualCameraComponent(priority: 1);
      final scene = cutscene(camera);
      world.update(_dt);
      world.update(0.5);
      expect(camera.priority, 101);
      scene.removeComponent<TimelinePlayerComponent>();
      world.update(_dt);
      expect(camera.priority, 1);
    });
  });

  test('a door that restarts on the way in, after reversing on the way '
      'out, opens from the start again (C26)', () {
    registerSpriteSystems(world);
    final player = TimelinePlayerComponent(inline: _slide());
    final door = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
      player,
    ], name: 'Door');
    final hero = world.createEntityWithComponents([
      TransformComponent(position: Vector3(500, 0, 0)),
      TagComponent('player'),
    ]);
    void walkTo(double x) =>
        hero.getComponent<TransformComponent>()!.setPositionXY(x, 0);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
      TimelineTriggerComponent(
        width: 100,
        height: 100,
        playerName: 'Door',
        onEnter: TimelineTriggerAction.restart,
        onExit: TimelineTriggerAction.reverse,
      ),
    ]);
    world.update(_dt);

    walkTo(10);
    world.update(0);
    world.update(1);
    expect(yOf(door), closeTo(-64, 1e-6));
    walkTo(500);
    world.update(0);
    world.update(1);
    expect(yOf(door), closeTo(0, 1e-6));

    walkTo(10);
    world.update(0);
    world.update(0.5);
    expect(yOf(door), closeTo(-32, 1e-6), reason: 'half open, not snapped');
  });

  group('event handlers (C27)', () {
    test('stop() in a handler stops the step: the clock stays rewound and '
        'later events do not fire', () {
      final fired = <String>[];
      late TimelinePlayback playback;
      playback = TimelinePlayback(
        _events([(0.2, 'stop'), (0.3, 'later')]),
        world: world,
        owner: world.createEntity(),
        onEvent: (e) {
          fired.add(e.name);
          if (e.name == 'stop') playback.stop();
        },
      )..play();
      playback.update(0.5);
      expect(fired, ['stop']);
      expect(playback.isPlaying, isFalse);
      expect(playback.time, 0);
    });

    test('seek() in a handler is where the clock stays', () {
      late TimelinePlayback playback;
      playback = TimelinePlayback(
        _events([(0.1, 'jump')]),
        world: world,
        owner: world.createEntity(),
        onEvent: (e) => playback.seek(0.9),
      )..play();
      playback.update(0.3);
      expect(playback.time, closeTo(0.9, 1e-9));
    });

    test('a handler stopping the parent stops a nested child too', () async {
      final fired = <String>[];
      late TimelinePlayback playback;
      playback = TimelinePlayback(
        TimelineAsset(
          duration: 2,
          tracks: [
            NestedTimelineTrack(
              blocks: const [
                TimelineBlock(start: 0, length: 1, value: 'inner.json'),
              ],
            ),
          ],
        ),
        world: world,
        owner: world.createEntity(),
        loader: (_) async => _events([(0.1, 'a'), (0.2, 'b')]),
        onEvent: (e) {
          fired.add(e.name);
          if (e.name == 'a') playback.stop();
        },
      )..play();
      await Future<void>.delayed(Duration.zero);
      playback.update(0.5);
      expect(fired, ['a']);
    });
  });

  group('nested timelines (C28)', () {
    TimelinePlayback nested(
      List<TimelineBlock> blocks,
      Map<String, TimelineAsset> files,
      List<String> fired, {
      int Function()? onLoad,
    }) => TimelinePlayback(
      TimelineAsset(duration: 4, tracks: [NestedTimelineTrack(blocks: blocks)]),
      world: world,
      owner: world.createEntity(),
      loader: (path) async {
        onLoad?.call();
        final file = files[path];
        if (file == null) throw StateError('no such file');
        return file;
      },
      onEvent: (e) => fired.add(e.name),
    )..play();

    test('a step across a block boundary fires both blocks', () async {
      final fired = <String>[];
      final playback = nested(
        const [
          TimelineBlock(start: 0, length: 1, value: 'a'),
          TimelineBlock(start: 1, length: 1, value: 'b'),
        ],
        {
          'a': _events([(0.9, 'endA')]),
          'b': _events([(0, 'startB'), (0.05, 'b1')]),
        },
        fired,
      );
      await Future<void>.delayed(Duration.zero);
      playback.update(0.5);
      playback.update(0.7);
      expect(fired, ['endA', 'startB', 'b1']);
    });

    test('a looping child fires its start again on every lap', () async {
      final fired = <String>[];
      final playback = nested(
        const [TimelineBlock(start: 0, length: 3, value: 'lap', loop: true)],
        {
          'lap': _events([(0, 'tick'), (0.5, 'mid')]),
        },
        fired,
      );
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 5; i++) {
        playback.update(0.4);
      }
      expect(fired.where((e) => e == 'tick'), hasLength(3));
      expect(fired.where((e) => e == 'mid'), hasLength(2));
    });

    test('a restart has its children at once, without reading them '
        'again', () async {
      final fired = <String>[];
      var loads = 0;
      final playback = nested(
        const [TimelineBlock(start: 0, length: 1, value: 'a')],
        {
          'a': _events([(0.05, 'early')]),
        },
        fired,
        onLoad: () => ++loads,
      );
      await Future<void>.delayed(Duration.zero);
      playback.update(0.1);
      expect(fired, ['early']);
      playback.play(from: 0);
      playback.update(0.1);
      expect(fired, ['early', 'early'], reason: 'the first frame is not lost');
      expect(loads, 1);
    });

    test('a nested timeline that cannot be read is said once', () async {
      final said = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => said.add('$message');
      addTearDown(() => debugPrint = previous);

      final playback = nested(
        const [TimelineBlock(start: 0, length: 1, value: 'missing.json')],
        const {},
        [],
      );
      await Future<void>.delayed(Duration.zero);
      playback.play(from: 0);
      await Future<void>.delayed(Duration.zero);
      playback.play(from: 0);
      await Future<void>.delayed(Duration.zero);
      expect(said.where((m) => m.contains('missing.json')), hasLength(1));
    });
  });

  group('reading (C16)', () {
    test('a timeline from a newer engine is refused, not read as this '
        'one', () {
      expect(
        () => TimelineAsset.fromJson({
          'formatVersion': TimelineFormat.current + 1,
          'duration': 1.0,
          'tracks': [],
        }),
        throwsA(
          isA<UnsupportedFormatVersionException>()
              .having((e) => e.kind, 'kind', 'timeline')
              .having((e) => e.found, 'found', TimelineFormat.current + 1)
              .having((e) => e.supported, 'supported', TimelineFormat.current),
        ),
      );
    });

    test('a track whose reader throws says why', () {
      final kinds = TimelineTrackKinds()
        ..register(
          'fx_anim_broken',
          (json) => throw const FormatException('bad keys'),
        );
      final track = kinds.read({'kind': 'fx_anim_broken'});
      expect(track, isA<UnknownTrack>());
      expect((track as UnknownTrack).error, isA<FormatException>());
      expect(
        TimelineAsset(tracks: [track]).validate().single,
        contains('bad keys'),
      );
      expect(track.withBase(name: 'renamed'), isA<UnknownTrack>());
      expect((track.withBase(name: 'x') as UnknownTrack).error, isNotNull);
    });

    test("an editor's add menu is offered every kind that says what it is",
        () {
      final kinds = TimelineTrackKinds();
      expect(kinds.offered, isNot(contains(PropertyTrack.kindId)),
          reason: 'a property track is added by choosing a field');
      expect(kinds.offered, contains(EventTrack.kindId));
      expect(kinds.offerFor(EventTrack.kindId)!.label, 'Events');
      expect(kinds.offerFor(AudioTrack.kindId)!.create(), isA<AudioTrack>());

      kinds.register(
        'fx_anim_offered',
        EventTrack.fromJson,
        offer: TimelineTrackOffer('Weather', EventTrack.new),
      );
      expect(kinds.offered.last, 'fx_anim_offered');
      // Registered again without one, it is no longer offered.
      kinds.register('fx_anim_offered', EventTrack.fromJson);
      expect(kinds.offered, isNot(contains('fx_anim_offered')));
      kinds.unregister(EventTrack.kindId);
      expect(kinds.offerFor(EventTrack.kindId), isNull);
      expect(TimelineTrackKinds.builtIn.offered, contains(AudioTrack.kindId));
    });
  });

  group('property tracks (P27)', () {
    test('a component swapped for a new one is written, not the old', () {
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
      ]);
      final playback = TimelinePlayback(
        _slide(by: -10),
        world: world,
        owner: entity,
      )..play();
      playback.update(0.5);
      expect(yOf(entity), closeTo(-5, 1e-6));
      final old = entity.getComponent<TransformComponent>()!;
      entity.removeComponent<TransformComponent>();
      entity.addComponent(TransformComponent(position: Vector3(0, 100, 0)));
      playback.update(0.25);
      expect(yOf(entity), closeTo(100 - 7.5, 1e-6));
      expect(old.position.y, closeTo(-5, 1e-6));
    });

    test('whole-number keys read from a file write a channel', () {
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(3, 4, 5)),
      ]);
      final track = PropertyTrack.fromJson({
        'kind': 'property',
        'component': 'TransformComponent',
        'field': 'position',
        'channel': 'x',
        'keys': [
          {'t': 0, 'v': 0, 'i': 'linear'},
          {'t': 1, 'v': 10},
        ],
      });
      final playback = TimelinePlayback(
        TimelineAsset(duration: 2, tracks: [track]),
        world: world,
        owner: entity,
      )..play();
      playback.update(1.5);
      final at = entity.getComponent<TransformComponent>()!.position;
      expect([at.x, at.y, at.z], [10, 4, 5]);
    });
  });
}
