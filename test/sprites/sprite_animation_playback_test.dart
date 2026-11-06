// How SpriteAnimationSystem plays a clip when something else steps in: a
// clip played backwards and started again, a listener that switches clips
// from a signal, and a step long enough to go round a clip several times.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Frames f0–f2, each 8×8. `once` is f0–f1 (100 ms each) and does not loop;
/// `idle` is f1–f2 (100 ms each) and loops; `tick` is f0 alone for 125 ms,
/// looping, with a `step` event half way.
Map<String, dynamic> _atlasJson() => {
  'frames': {
    for (var i = 0; i < 3; i++)
      'f$i': {
        'frame': {'x': i * 8, 'y': 0, 'w': 8, 'h': 8},
        'sourceSize': {'w': 8, 'h': 8},
        'duration': 100,
      },
    'tick': {
      'frame': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
      'sourceSize': {'w': 8, 'h': 8},
      'duration': 125,
    },
  },
  'meta': {
    'app': 'https://www.aseprite.org/',
    'image': 'hero.png',
    'size': {'w': 24, 'h': 8},
    'frameTags': [
      {'name': 'once', 'from': 0, 'to': 1, 'direction': 'forward'},
      {'name': 'idle', 'from': 1, 'to': 2, 'direction': 'forward'},
      {'name': 'tick', 'from': 3, 'to': 3, 'direction': 'forward'},
    ],
    'just': {
      'clips': {
        'once': {'loop': false},
      },
      'events': {
        'idle': [
          {'time': 0.0, 'name': 'idle-start'},
        ],
        'tick': [
          {'time': 0.0625, 'name': 'step'},
        ],
      },
    },
  },
};

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImageSync(width, height);
}

class _Loader extends SpriteAssetLoader {
  @override
  Future<ui.Image> loadImage(String path) async => _image(24, 8);

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      SpriteAtlas.fromJson(_atlasJson(), loadImage: (_) async => _image(24, 8));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late SpriteAnimationSystem animations;
  late List<String> heard;

  setUp(() {
    world = World();
    final loader = _Loader();
    world.addSystem(animations = SpriteAnimationSystem(loader: loader));
    heard = [];
  });
  tearDown(() => world.dispose());

  /// Lets the atlas load, then runs a frame of no time.
  Future<void> settle() async {
    world.update(0);
    await pumpEventQueue();
    world.update(0);
  }

  Future<SpriteAnimationComponent> playing(
    String clip, {
    double speed = 1,
    void Function(SpriteAnimationComponent c, SpriteAnimationSignal s)?
    onSignal,
  }) async {
    final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: clip)
      ..playingSpeed = speed;
    animations.signals.listen((s) {
      heard.add('${s.clip}:${s.name}');
      onSignal?.call(c, s);
    });
    world.createEntityWithComponents([TransformComponent(), c]);
    await settle();
    return c;
  }

  group('a clip played backwards', () {
    test('started again once it finished plays from its end', () async {
      final c = await playing('once', speed: -1);
      world.update(0.15); // 0.2 → 0.05
      world.update(0.1); // past the start: done
      expect(c.isComplete, isTrue);

      c.play();
      world.update(0.05);
      expect(c.isComplete, isFalse, reason: 'it used to finish at once');
      expect(c.elapsed, closeTo(0.15, 1e-9));
      expect(c.frameIndex, 1);
      expect(heard.where((s) => s.endsWith(':completed')), hasLength(1));
    });

    test('stopped, then played, starts from its end too', () async {
      final c = await playing('once', speed: -1);
      world.update(0.3);
      expect(c.isComplete, isTrue);
      c
        ..stop()
        ..play();
      world.update(0.02);
      expect(c.elapsed, closeTo(0.18, 1e-9));
    });
  });

  group('a listener that switches the clip', () {
    test('on completion starts the new clip from its start', () async {
      final c = await playing(
        'once',
        onSignal: (c, s) {
          if (s.name == SpriteAnimationSignal.completed) c.switchClip('idle');
        },
      );
      world.update(0.25);
      expect(c.playingClip, 'idle');
      expect(c.elapsed, 0, reason: 'used to be the old clip\'s end, 0.2');
      expect(c.frameIndex, 0);

      world.update(0.05);
      expect(c.elapsed, closeTo(0.05, 1e-9));
      expect(heard, ['once:completed', 'idle:idle-start']);
    });

    test('on a frame event drops the rest of the step', () async {
      final c = await playing(
        'tick',
        onSignal: (c, s) {
          if (s.name == 'step') c.switchClip('idle');
        },
      );
      // Round the loop: the step fires, the listener switches; the wrap
      // used to fire the new clip's events with the old clip's times.
      world.update(0.13);
      expect(heard, ['tick:step']);
      expect(c.playingClip, 'idle');
      expect(c.elapsed, 0);

      world.update(0.01);
      expect(heard, ['tick:step', 'idle:idle-start']);
    });

    test('a restart from a listener stands', () async {
      final c = await playing(
        'tick',
        onSignal: (c, s) {
          if (s.name == 'step' && heard.length == 1) c.restart();
        },
      );
      world.update(0.1);
      expect(c.elapsed, 0);
      world.update(0.07);
      expect(c.elapsed, closeTo(0.07, 1e-9));
      expect(heard, ['tick:step', 'tick:step']);
    });
  });

  group('a step longer than the clip', () {
    test('fires the events of every pass it went round', () async {
      final c = await playing('tick', speed: 4);
      world.update(0.125); // 0.5 s of a 0.125 s clip: four passes
      expect(heard, List.filled(4, 'tick:step'));
      expect(c.elapsed, 0);
    });

    test('backwards too', () async {
      await playing('tick', speed: -4);
      world.update(0.125);
      expect(heard, List.filled(4, 'tick:step'));
    });

    test('up to a limit, after a long hitch', () async {
      await playing('tick');
      world.update(10);
      expect(heard, hasLength(1 + SpriteAnimationSystem.maxPassesPerStep));
    });
  });
}
