// The block tracks, and the ways a timeline gets started: a trigger, a
// signal, an animator state.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreCodecs);

  late World world;
  setUp(() => world = World());

  TimelinePlayback playing(
    TimelineAsset asset,
    Entity owner, {
    bool preview = false,
    Future<TimelineAsset> Function(String)? loader,
    void Function(TimelineEventFired)? onEvent,
  }) => TimelinePlayback(
    asset,
    world: world,
    owner: owner,
    isPreview: preview,
    loader: loader,
    onEvent: onEvent,
  )..play();

  group('block tracks', () {
    test('every kind round-trips', () {
      final asset = TimelineAsset(
        duration: 4,
        tracks: [
          SpriteClipTrack(
            blocks: const [
              TimelineBlock(start: 1, length: 2, value: 'run', speed: 2),
            ],
          ),
          CameraShotTrack(
            blocks: const [
              TimelineBlock(start: 0, length: 1, value: 'Cam', amount: 50),
            ],
          ),
          AudioTrack(
            binding: const TrackBinding.name('Door'),
            blocks: const [
              TimelineBlock(start: 0.5, value: 'a.wav', amount: 0.4),
            ],
          ),
          ActivationTrack(blocks: const [TimelineBlock(start: 0, length: 3)]),
          NestedTimelineTrack(
            blocks: const [
              TimelineBlock(start: 2, length: 2, value: 'x.timeline.json'),
            ],
          ),
          EventTrack(
            events: const [TimelineEvent(time: 1, name: 'go', signal: true)],
          ),
        ],
      );
      final back = TimelineAsset.parse(asset.encode());
      expect(back.toJson(), asset.toJson());
      expect(back.tracks.map((t) => t.kind), [
        'spriteClip',
        'cameraShot',
        'audio',
        'activation',
        'nested',
        'event',
      ]);
      expect(back.tracks.whereType<UnknownTrack>(), isEmpty);
      expect(back.validate(), isEmpty);
      expect((back.tracks[1] as BlockTrack).blocks.single.amount, 50);
      expect(back.contentEnd, 4);
    });

    test('a sprite block switches the clip, and back afterwards', () {
      final sprite = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle')
        ..speed = 1.5;
      final entity = world.createEntityWithComponents([sprite]);
      final playback = playing(
        TimelineAsset(
          duration: 3,
          tracks: [
            SpriteClipTrack(
              blocks: const [
                TimelineBlock(start: 1, length: 1, value: 'wave', speed: 2),
              ],
            ),
          ],
        ),
        entity,
      );
      playback.update(0.5);
      expect(sprite.clip, 'idle');
      playback.update(1.0);
      expect(sprite.clip, 'wave');
      expect(sprite.speed, 2);
      expect(sprite.isPlaying, isTrue);
      sprite.elapsed = 0.3;
      playback.update(0.1);
      expect(sprite.elapsed, 0.3, reason: 'inside a block it is left to play');
      playback.update(1.0);
      expect(sprite.clip, 'idle');
      expect(sprite.speed, 1.5);
    });

    test('a camera shot raises a priority for its length, and on stop', () {
      final a = VirtualCameraComponent(priority: 5);
      final b = VirtualCameraComponent(priority: 1);
      world.createEntityWithComponents([a], name: 'Wide');
      world.createEntityWithComponents([b], name: 'Close');
      final playback = playing(
        TimelineAsset(
          duration: 4,
          tracks: [
            CameraShotTrack(
              blocks: const [
                TimelineBlock(start: 0, length: 1, value: 'Wide', amount: 100),
                TimelineBlock(start: 1, length: 1, value: 'Close', amount: 100),
              ],
            ),
          ],
        ),
        world.createEntity(),
      );
      playback.update(0.5);
      expect([a.priority, b.priority], [105, 1]);
      playback.update(1.0);
      expect([a.priority, b.priority], [5, 101]);
      playback.stop();
      expect([a.priority, b.priority], [5, 1], reason: 'nothing left raised');
      playback.play();
      playback.update(2.5);
      expect([a.priority, b.priority], [5, 1]);
    });

    test('a sound starts once as time passes it; a preview stays quiet', () {
      final heard = <String>[];
      final previous = TimelineAudio.play;
      TimelineAudio.play = (context, at, cue) =>
          heard.add('${at.name}:${cue.value}@${cue.amount}');
      addTearDown(() => TimelineAudio.play = previous);

      final door = world.createEntity(name: 'Door');
      final asset = TimelineAsset(
        duration: 2,
        tracks: [
          AudioTrack(
            binding: const TrackBinding.name('Door'),
            blocks: const [
              TimelineBlock(start: 0, value: 'creak.wav', amount: 0.5),
              TimelineBlock(start: 1, value: 'slam.wav'),
            ],
          ),
        ],
      );
      final playback = playing(asset, world.createEntity());
      playback.update(0.5);
      expect(heard, ['Door:creak.wav@0.5']);
      playback.update(0.4);
      playback.update(0.4);
      expect(heard, hasLength(2));
      playback.seek(0.5);
      playback.update(0.1);
      expect(heard, hasLength(2), reason: 'a seek passes nothing');

      heard.clear();
      playing(asset, door, preview: true).update(1.5);
      expect(heard, isEmpty);

      // The default asks the engine's audio system through a component.
      TimelineAudio.play = TimelineAudio.viaComponent;
      playing(asset, world.createEntity()).update(0.1);
      expect(door.getComponent<AudioPlayComponent>()!.clipPath, 'creak.wav');
    });

    test('activation switches an entity off and finds it again', () {
      final ghost = world.createEntity(name: 'Ghost');
      final asset = TimelineAsset(
        duration: 3,
        tracks: [
          ActivationTrack(
            binding: const TrackBinding.name('Ghost'),
            blocks: const [TimelineBlock(start: 1, length: 1)],
          ),
        ],
      );
      final playback = playing(asset, world.createEntity());
      playback.update(0.5);
      expect(ghost.isActive, isFalse);
      playback.update(1.0);
      expect(ghost.isActive, isTrue, reason: 'found though it was off');
      playback.update(1.0);
      expect(ghost.isActive, isFalse);
      playback.stop();
      expect(ghost.isActive, isFalse, reason: 'a play leaves what it did');

      ghost.isActive = true;
      final look = playing(asset, world.createEntity(), preview: true);
      look.seek(0);
      expect(ghost.isActive, isFalse);
      look.dispose();
      expect(ghost.isActive, isTrue, reason: 'a preview puts it back');
    });

    test('a nested timeline runs on its own clock, for the bound entity, '
        'and its events come out', () async {
      final child = TimelineAsset(
        duration: 1,
        tracks: [
          PropertyTrack(
            component: 'TransformComponent',
            field: 'position',
            channel: 'x',
            mode: PropertyTrackMode.relative,
            curve: KeyCurve([
              const TimelineKey(
                time: 0,
                value: 0.0,
                interpolation: KeyInterpolation.linear,
              ),
              const TimelineKey(time: 1, value: 10.0),
            ]),
          ),
          EventTrack(events: const [TimelineEvent(time: 0.6, name: 'inner')]),
        ],
      );
      final fired = <String>[];
      final door = world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 0, 0)),
      ], name: 'Door');
      var loads = 0;
      final playback = playing(
        TimelineAsset(
          duration: 4,
          tracks: [
            NestedTimelineTrack(
              binding: const TrackBinding.name('Door'),
              blocks: const [
                TimelineBlock(
                  start: 1,
                  length: 2,
                  value: 'open.timeline.json',
                  speed: 0.5,
                ),
              ],
            ),
          ],
        ),
        world.createEntity(),
        loader: (path) async {
          loads++;
          return child;
        },
        onEvent: (e) => fired.add('${e.owner.name}:${e.name}'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(loads, 1);
      double x() => door.getComponent<TransformComponent>()!.position.x;

      playback.update(0.5);
      expect(x(), 100, reason: 'before the block');
      playback.update(1.5); // 1 s into the block, at half speed
      expect(x(), closeTo(105, 1e-6));
      expect(fired, isEmpty);
      playback.update(0.5);
      expect(fired, ['Door:inner']);
      playback.update(1.0);
      expect(x(), closeTo(110, 1e-6));
    });

    test('a timeline that nests itself stops at a depth', () async {
      late TimelineAsset self;
      self = TimelineAsset(
        duration: 1,
        tracks: [
          NestedTimelineTrack(
            blocks: const [
              TimelineBlock(start: 0, length: 1, value: 'self.timeline.json'),
            ],
          ),
        ],
      );
      var loads = 0;
      final playback = playing(
        self,
        world.createEntity(),
        loader: (path) async {
          loads++;
          return self;
        },
      );
      for (var i = 0; i < 40; i++) {
        playback.update(0.01);
        await Future<void>.delayed(Duration.zero);
      }
      expect(loads, NestedTimelineTrack.maxDepth);
    });
  });

  group('starting', () {
    late Entity door;
    late TimelinePlayerComponent player;
    late Entity hero;

    setUp(() {
      registerSpriteSystems(world);
      player = TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: 1,
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
                const TimelineKey(time: 1, value: -64.0),
              ]),
            ),
          ],
        ),
      );
      door = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        player,
      ], name: 'Door');
      hero = world.createEntityWithComponents([
        TransformComponent(position: Vector3(500, 0, 0)),
        TagComponent('player'),
      ]);
    });

    double y() => door.getComponent<TransformComponent>()!.position.y;
    void walkTo(double x) =>
        hero.getComponent<TransformComponent>()!.setPositionXY(x, 0);

    test('a trigger opens the door on the way in and shuts it on the way '
        'out', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        TimelineTriggerComponent(
          width: 100,
          height: 100,
          playerName: 'Door',
          onEnter: TimelineTriggerAction.play,
          onExit: TimelineTriggerAction.reverse,
        ),
      ]);
      world.update(_dt);
      expect(player.isPlaying, isFalse);

      walkTo(10);
      world.update(0);
      world.update(0.5);
      expect(y(), closeTo(-32, 1e-6));

      walkTo(500);
      world.update(0.25);
      expect(y(), closeTo(-16, 1e-6), reason: 'back the way it came');
      world.update(1);
      expect(y(), closeTo(0, 1e-6));
      expect(player.isFinished, isTrue);

      walkTo(10);
      world.update(1);
      expect(y(), closeTo(-64, 1e-6), reason: 'and forwards again');
    });

    test('a one-shot trigger fires once', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        TimelineTriggerComponent(
          width: 100,
          height: 100,
          playerName: 'Door',
          oneShot: true,
        ),
      ]);
      walkTo(10);
      world.update(0);
      world.update(1);
      expect(y(), closeTo(-64, 1e-6));
      walkTo(500);
      world.update(_dt);
      walkTo(10);
      world.update(1);
      expect(y(), closeTo(-64, 1e-6), reason: 'not another 64');
    });

    test('a signal starts whoever listens — from code or from a timeline', () {
      player.listenSignal = 'open_sesame';
      world.update(_dt);
      TimelineSignals.emit('something_else');
      world.update(0.5);
      expect(y(), 0);
      TimelineSignals.emit('open_sesame');
      world.update(0.5);
      expect(y(), closeTo(-32, 1e-6));

      world.createEntityWithComponents([
        TimelinePlayerComponent(
          playOnStart: true,
          inline: TimelineAsset(
            duration: 1,
            tracks: [
              EventTrack(
                events: const [
                  TimelineEvent(time: 0.1, name: 'open_sesame', signal: true),
                ],
              ),
            ],
          ),
        ),
      ]);
      // The door finishes; the new player is seen, plays and signals, and
      // the door starts over.
      world.update(1);
      expect(y(), closeTo(-64, 1e-6));
      world.update(0.25);
      expect(y(), closeTo(-64 - 16, 1e-6));
    });

    test('an animator state plays its timeline, and exit time waits for '
        'it', () async {
      final graph = AnimatorGraph.fromJson({
        'entry': 'idle',
        'parameters': [
          {'name': 'open', 'type': 'trigger'},
        ],
        'states': [
          {'name': 'idle'},
          {'name': 'opening', 'timeline': 'door.timeline.json'},
        ],
        'transitions': [
          {
            'from': 'idle',
            'to': 'opening',
            'conditions': [
              {'param': 'open', 'op': '==', 'value': true},
            ],
          },
          {
            'from': 'opening',
            'to': 'idle',
            'hasExitTime': true,
            'exitTime': 1.0,
          },
        ],
      });
      expect(graph.stateNamed('opening')!.timeline, 'door.timeline.json');
      expect(
        AnimatorGraph.fromJson(graph.toJson()).stateNamed('opening')!.timeline,
        'door.timeline.json',
      );

      final w = World();
      final asset = player.inline!;
      registerSpriteSystems(
        w,
        graphLoader: (_) async => graph,
        timelineLoader: (_) async => asset,
      );
      final animator = AnimatorComponent(graphPath: 'door.animator.json');
      final timeline = TimelinePlayerComponent();
      final entity = w.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        SpriteAnimationComponent(atlasPath: ''),
        animator,
        timeline,
      ]);
      w.update(_dt);
      await Future<void>.delayed(Duration.zero);
      w.update(_dt);
      expect(animator.currentState, 'idle');

      animator.setTrigger('open');
      w.update(_dt);
      expect(animator.currentState, 'opening');
      expect(timeline.timelinePath, 'door.timeline.json');
      w.update(_dt);
      await Future<void>.delayed(Duration.zero);
      expect(timeline.isPlaying, isTrue);
      w.update(0.5);
      expect(animator.currentState, 'opening', reason: 'half way');
      expect(
        entity.getComponent<TransformComponent>()!.position.y,
        closeTo(-32, 1),
      );
      w.update(0.6);
      w.update(_dt);
      expect(animator.currentState, 'idle', reason: 'the timeline finished');
    });
  });
}
