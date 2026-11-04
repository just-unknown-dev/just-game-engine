// Animator states that play timelines: on a change of state the old
// state's timeline ends before the new state's clip is set (so what it gives
// back cannot overwrite that clip), a state with no timeline stops the one
// before it, a looping state timeline still reaches its exit time, and a
// sprite blend tree plays its motion at the motion's speed.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _clips = ['idle', 'attack', 'swing', 'hurt', 'walk', 'run'];

Map<String, dynamic> _atlasJson() => {
  'frames': {
    for (var i = 0; i < _clips.length * 2; i++)
      'f$i': {
        'frame': {'x': i * 4, 'y': 0, 'w': 4, 'h': 4},
        'sourceSize': {'w': 4, 'h': 4},
        'spriteSourceSize': {'x': 0, 'y': 0, 'w': 4, 'h': 4},
        'duration': 100,
      },
  },
  'meta': {
    'app': 'aseprite',
    'image': 'hero.png',
    'size': {'w': _clips.length * 8, 'h': 4},
    'frameTags': [
      for (var i = 0; i < _clips.length; i++)
        {
          'name': _clips[i],
          'from': i * 2,
          'to': i * 2 + 1,
          'direction': 'forward',
        },
    ],
  },
};

class _Loader extends SpriteAssetLoader {
  @override
  Future<ui.Image> loadImage(String path) async => _image();

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      SpriteAtlas.fromJson(_atlasJson(), loadImage: (_) async => _image());

  static ui.Image _image() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint());
    return recorder.endRecording().toImageSync(_clips.length * 8, 4);
  }
}

/// Attack plays a timeline holding the "swing" clip over its whole length,
/// with a "hit" event late in it; Idle's timeline has no sprite track;
/// Hurt has none at all.
const _graph = AnimatorGraph(
  entry: 'attack',
  parameters: [
    AnimatorParameter(name: 'hit', type: AnimatorParameterType.trigger),
  ],
  states: [
    AnimatorState(name: 'attack', timeline: 'attack.timeline.json'),
    AnimatorState(name: 'idle', timeline: 'idle.timeline.json'),
    AnimatorState(name: 'hurt'),
  ],
  transitions: [
    AnimatorTransition(from: 'attack', to: 'idle', hasExitTime: true),
    AnimatorTransition(
      from: AnimatorTransition.anyState,
      to: 'hurt',
      conditions: [AnimatorCondition(parameter: 'hit')],
    ),
  ],
);

TimelineAsset _timeline(String path) => switch (path) {
  'attack.timeline.json' => TimelineAsset(
    duration: 0.4,
    tracks: [
      SpriteClipTrack(
        blocks: const [TimelineBlock(start: 0, length: 0.4, value: 'swing')],
      ),
      EventTrack(events: const [TimelineEvent(time: 0.3, name: 'blow')]),
    ],
  ),
  'idle.timeline.json' => TimelineAsset(
    duration: 1,
    wrap: TimelineWrap.loop,
    tracks: [EventTrack()],
  ),
  // A looping timeline, for a state left by its exit time.
  _ => TimelineAsset(duration: 0.5, wrap: TimelineWrap.loop),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late List<String> events;

  // Graph, atlas and the state's timeline each load in turn.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      world.update(0);
      await pumpEventQueue();
    }
    world.update(0);
  }

  ({
    Entity entity,
    AnimatorComponent animator,
    SpriteAnimationComponent sprite,
    TimelinePlayerComponent player,
  })
  hero({AnimatorGraph graph = _graph}) {
    world = World();
    events = [];
    registerSpriteSystems(
      world,
      loader: _Loader(),
      graphLoader: (_) async => graph,
      timelineLoader: (path) async => _timeline(path),
    );
    world.systems.whereType<TimelineSystem>().single.events.listen(
      (e) => events.add(e.name),
    );
    final animator = AnimatorComponent(graphPath: 'hero.animator.json');
    final sprite = SpriteAnimationComponent(atlasPath: 'hero.json');
    final player = TimelinePlayerComponent();
    final entity = world.createEntityWithComponents([
      TransformComponent(),
      sprite,
      animator,
      player,
    ]);
    return (entity: entity, animator: animator, sprite: sprite, player: player);
  }

  tearDown(() => world.dispose());

  test('the old state\'s timeline gives its clip back before the new '
      'state\'s clip is set', () async {
    final h = hero();
    await settle();
    expect(h.animator.currentState, 'attack');
    world.update(0.1);
    expect(h.sprite.playingClip, 'swing', reason: "the timeline's block");
    for (var i = 0; i < 30 && h.animator.currentState == 'attack'; i++) {
      world.update(0.05);
    }
    expect(h.animator.currentState, 'idle');
    expect(h.sprite.playingClip, 'idle', reason: "the new state's clip");
    await settle();
    world.update(0.1);
    expect(h.sprite.playingClip, 'idle', reason: 'and it stays');
  });

  test('a state with no timeline stops the one before it', () async {
    final h = hero();
    await settle();
    world.update(0.1);
    expect(h.sprite.playingClip, 'swing');
    h.animator.setTrigger('hit');
    world.update(0.05);
    expect(h.animator.currentState, 'hurt');
    expect(h.sprite.playingClip, 'hurt');
    for (var i = 0; i < 10; i++) {
      world.update(0.05);
    }
    expect(events, isNot(contains('blow')), reason: "attack's event is over");
    expect(h.sprite.playingClip, 'hurt', reason: 'nothing gives back attack');
    expect(
      h.player.playingTimelinePath,
      '',
      reason: 'back to what was authored',
    );
  });

  test('a looping state timeline reaches its exit time', () async {
    const graph = AnimatorGraph(
      entry: 'spin',
      states: [
        AnimatorState(
          name: 'spin',
          clip: 'idle',
          timeline: 'spin.timeline.json',
        ),
        AnimatorState(name: 'done', clip: 'hurt'),
      ],
      transitions: [
        AnimatorTransition(from: 'spin', to: 'done', hasExitTime: true),
      ],
    );
    final h = hero(graph: graph);
    await settle();
    expect(h.animator.currentState, 'spin');
    world.update(0.3);
    expect(h.animator.currentState, 'spin', reason: 'not round yet');
    world.update(0.3);
    world.update(0.01);
    expect(h.animator.currentState, 'done', reason: 'once round the loop');
  });

  test('a sprite blend tree plays its heaviest motion at its speed', () async {
    const graph = AnimatorGraph(
      entry: 'move',
      parameters: [AnimatorParameter(name: 'speed')],
      states: [
        AnimatorState(
          name: 'move',
          speed: 2,
          blend: AnimatorBlendTree(
            parameter: 'speed',
            motions: [
              AnimatorBlendMotion(clip: 'walk', threshold: 0),
              AnimatorBlendMotion(clip: 'run', threshold: 10, speed: 1.5),
            ],
          ),
        ),
      ],
    );
    final h = hero(graph: graph);
    await settle();
    expect(h.sprite.playingClip, 'walk');
    expect(h.sprite.playingSpeed, 2);
    h.animator.setFloat('speed', 10);
    world.update(0.05);
    expect(h.sprite.playingClip, 'run');
    expect(
      h.sprite.playingSpeed,
      3,
      reason: "the state's 2 × the motion's 1.5",
    );
  });
}
