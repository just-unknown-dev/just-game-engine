// What an animator chooses is runtime state: a scene saved while it runs —
// as an editor's systems run while the scene is edited, ticking at 0 — is
// the scene as it was authored, while what plays still follows the graph.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// idle (0.2 s) · jump (0.2 s, once).
Map<String, dynamic> _atlasJson() => {
  'frames': {
    for (var i = 0; i < 4; i++)
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
    'size': {'w': 16, 'h': 4},
    'frameTags': [
      {'name': 'idle', 'from': 0, 'to': 1, 'direction': 'forward'},
      {'name': 'jump', 'from': 2, 'to': 3, 'direction': 'forward'},
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
    return recorder.endRecording().toImageSync(16, 4);
  }
}

/// Starts mid-jump — as a character whose "grounded" reads false before
/// anything has moved it does — at its own speed, playing once, with a
/// timeline of its own.
const _graph = AnimatorGraph(
  entry: 'jump',
  parameters: [
    AnimatorParameter(name: 'grounded', type: AnimatorParameterType.bool),
  ],
  states: [
    AnimatorState(name: 'idle'),
    AnimatorState(
      name: 'jump',
      speed: 1.5,
      loop: false,
      timeline: 'jump.timeline.json',
    ),
  ],
  transitions: [
    AnimatorTransition(
      from: 'jump',
      to: 'idle',
      conditions: [AnimatorCondition(parameter: 'grounded')],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() {
    world = World();
    registerSpriteSystems(
      world,
      loader: _Loader(),
      graphLoader: (_) async => _graph,
      timelineLoader: (_) async => TimelineAsset(duration: 0.5),
    );
  });
  tearDown(() => world.dispose());

  /// [components] as a scene file would hold them.
  String saved(List<Component> components) => jsonEncode([
    for (final c in components) world.context.definitions.encode(c),
  ]);

  test('a sprite saved while its animator runs is as authored', () async {
    final sprite = SpriteAnimationComponent(
      atlasPath: 'hero.json',
      clip: 'idle',
      speed: 0.5,
    );
    final animator = AnimatorComponent(
      graphPath: 'hero.animator.json',
      faceVelocity: true,
    );
    final timeline = TimelinePlayerComponent();
    final velocity = VelocityComponent();
    final hero = world.createEntityWithComponents([
      TransformComponent(),
      velocity,
      sprite,
      animator,
      timeline,
    ]);
    velocity.velocity.x = -40; // moving left: the animator faces it so
    final authored = saved([sprite, animator, timeline]);

    // As an editor ticks while the scene is edited.
    world.update(0);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    world.update(0);
    world.update(0);
    expect(animator.currentState, 'jump', reason: 'the graph runs');
    expect(
      (sprite.playingClip, sprite.playingSpeed, sprite.playingFlipX),
      ('jump', 1.5, true),
      reason: 'and the sprite plays what it chose',
    );
    expect(sprite.loopOverride, isFalse);
    expect(timeline.playingTimelinePath, 'jump.timeline.json');
    expect(saved([sprite, animator, timeline]), authored, reason: 'at dt 0');

    // As a game runs.
    for (var i = 0; i < 30; i++) {
      world.update(1 / 60);
    }
    expect(sprite.playingClip, 'jump');
    expect(saved([sprite, animator, timeline]), authored, reason: 'at dt > 0');
    expect(
      (sprite.clip, sprite.speed, sprite.flipX, timeline.timelinePath),
      ('idle', 0.5, false, ''),
    );

    // The animator gone, the sprite plays what was authored again.
    hero.removeComponent<AnimatorComponent>();
    world.update(1 / 60);
    expect(sprite.isDriven, isFalse);
    expect(
      (sprite.playingClip, sprite.playingSpeed, sprite.playingFlipX),
      ('idle', 0.5, false),
    );
  });

  test('a timeline turned round at run time keeps its authored speed', () {
    final player = TimelinePlayerComponent(speed: 2);
    final owner = world.createEntityWithComponents([player]);
    player.playback = TimelinePlayback(
      TimelineAsset(duration: 1),
      world: world,
      owner: owner,
    );
    player.reverse();
    expect((player.speed, player.playingSpeed), (2.0, -2.0));
    expect(player.playback!.speed, -2.0);
    player.forwards();
    expect((player.speed, player.playingSpeed), (2.0, 2.0));
    expect(
      jsonEncode(world.context.definitions.encode(player)),
      jsonEncode(
        world.context.definitions.encode(TimelinePlayerComponent(speed: 2)),
      ),
    );
    player.playback!.dispose();
  });

  test('another graph, or none, hands the sprite back', () async {
    final sprite = SpriteAnimationComponent(atlasPath: 'hero.json');
    final animator = AnimatorComponent(graphPath: 'hero.animator.json');
    world.createEntityWithComponents([TransformComponent(), sprite, animator]);
    world.update(0);
    await Future<void>.delayed(Duration.zero);
    world.update(0);
    expect(sprite.isDriven, isTrue);
    animator.graphPath = '';
    world.update(0);
    expect(sprite.isDriven, isFalse);
    expect(sprite.playingClip, '');
  });
}
