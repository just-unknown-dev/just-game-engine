// Sprite and animator regressions: bool values in number parameters,
// trimmed and rotated atlas frames, frame events at time zero, clips played
// backwards, Aseprite tags written as doubles, loads that failed silently,
// and the per-frame caches.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Frames `f0`–`f3` of an 8×8 box. `f1` is trimmed to 4×6 at (2, 1); `f2`
/// is trimmed the same way and stored turned. `idle` is f0 (100 ms) then
/// f3 (300 ms); `land` is f0 then f3 and does not loop.
Map<String, dynamic> _atlasJson() => {
  'frames': {
    'f0': _frame(0, 0, 8, 8),
    'f1': _frame(8, 0, 4, 6, trimmed: true, offset: const Offset(2, 1)),
    'f2': _frame(
      12,
      0,
      4,
      6,
      trimmed: true,
      offset: const Offset(2, 1),
      rotated: true,
    ),
    'f3': _frame(20, 0, 8, 8, duration: 300),
  },
  'meta': {
    'app': 'https://www.aseprite.org/',
    'image': 'hero.png',
    'size': {'w': 32, 'h': 8},
    'frameTags': [
      // Whole numbers written as doubles, as some writers do.
      {'name': 'idle', 'from': 0.0, 'to': 3.0, 'direction': 'forward'},
      // A range written backwards.
      {'name': 'land', 'from': 3, 'to': 0, 'direction': 'forward'},
    ],
    'just': {
      'clips': {
        'land': {'loop': false},
      },
      'events': {
        'idle': [
          {'time': 0.0, 'name': 'start'},
          {'time': 0.25, 'name': 'blink'},
          // No time at all: the start.
          {'name': 'untimed'},
        ],
        'land': [
          {'time': 0.0, 'name': 'touch'},
        ],
      },
    },
  },
};

Map<String, dynamic> _frame(
  double x,
  double y,
  double w,
  double h, {
  bool trimmed = false,
  bool rotated = false,
  Offset offset = Offset.zero,
  int duration = 100,
}) => {
  'frame': {'x': x, 'y': y, 'w': w, 'h': h},
  'rotated': rotated,
  'trimmed': trimmed,
  'spriteSourceSize': {'x': offset.dx, 'y': offset.dy, 'w': w, 'h': h},
  'sourceSize': {'w': 8, 'h': 8},
  'duration': duration,
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
  int atlasLoads = 0;

  @override
  Future<ui.Image> loadImage(String path) async {
    if (path.contains('missing')) throw StateError('no such image');
    return _image(16, 16);
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) {
    atlasLoads++;
    if (path.contains('missing')) {
      return Future.error(StateError('no such atlas'));
    }
    return SpriteAtlas.fromJson(
      _atlasJson(),
      basePath: 'assets/sprites/',
      loadImage: (_) async => _image(32, 8),
    );
  }
}

/// Remembers the image draws and turns it is asked for; ignores the rest.
class _DrawLog implements Canvas {
  final List<(Rect, Rect)> draws = [];
  final List<double> turns = [];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      draws.add((src, dst));

  @override
  void rotate(double radians) => turns.add(radians);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late _Loader loader;
  late SpriteAnimationSystem animations;

  setUp(() {
    world = World();
    loader = _Loader();
    registerSpriteSystems(world, loader: loader);
    animations = world.systems.whereType<SpriteAnimationSystem>().single;
  });
  tearDown(() => world.dispose());

  Future<void> settle() async {
    world.update(0);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    world.update(0);
  }

  Entity hero(SpriteAnimationComponent animation) =>
      world.createEntityWithComponents([TransformComponent(), animation]);

  Sprite spriteOf(Entity e) =>
      e.getComponent<RenderableComponent>()!.renderable as Sprite;

  List<String> say() {
    final said = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => said.add('$message');
    addTearDown(() => debugPrint = previous);
    return said;
  }

  group('animator parameters (C11)', () {
    test('a number parameter holding a bool reads as 1 or 0', () {
      const condition = AnimatorCondition(
        parameter: 'grounded',
        op: AnimatorOp.greater,
        value: 0.5,
      );
      expect(condition.holds(true, AnimatorParameterType.float), isTrue);
      expect(condition.holds(false, AnimatorParameterType.float), isFalse);
      expect(condition.holds('text', AnimatorParameterType.int), isFalse);
      expect(
        const AnimatorParameter(name: 'g', defaultValue: true).initialValue,
        1.0,
      );
    });

    test('a float bound to a bool source does not stop the world', () async {
      final graph = AnimatorGraph.fromJson({
        'entry': 'air',
        'parameters': [
          {'name': 'g', 'type': 'float', 'binding': 'fx_anim_grounded'},
        ],
        'states': [
          {'name': 'air', 'clip': 'idle'},
          {'name': 'ground', 'clip': 'idle'},
        ],
        'transitions': [
          {
            'from': 'air',
            'to': 'ground',
            'conditions': [
              {'param': 'g', 'op': '>=', 'value': 1},
            ],
          },
        ],
      });
      final w = World();
      addTearDown(w.dispose);
      w.context.animatorBindings.register('fx_anim_grounded', (_) => true);
      registerSpriteSystems(w, loader: loader, graphLoader: (_) async => graph);
      final animator = AnimatorComponent(graphPath: 'hero.animator.json');
      w.createEntityWithComponents([
        TransformComponent(),
        SpriteAnimationComponent(atlasPath: 'a.json'),
        animator,
      ]);
      w.update(0);
      await Future<void>.delayed(Duration.zero);
      w.update(0.1);
      expect(() => w.update(0.1), returnsNormally);
      expect(animator.currentState, 'ground');
    });
  });

  group('trimmed and rotated frames (C35)', () {
    Future<Sprite> showing(String region) async {
      final e = world.createEntityWithComponents([
        TransformComponent(),
        SpriteComponent(spritePath: '', atlasPath: 'a.json', region: region),
      ]);
      await settle();
      return spriteOf(e);
    }

    test(
      'a trimmed frame is drawn at its size, at its place in the box',
      () async {
        final sprite = await showing('f1');
        expect(sprite.getBounds()!.size, const Size(8, 8));
        expect(
          (sprite as BatchableSprite).batchImage,
          isNull,
          reason: 'a batch cannot move a frame inside its box',
        );
        final log = _DrawLog();
        sprite.render(log, const Size(100, 100));
        expect(log.draws.single, (
          const Rect.fromLTWH(8, 0, 4, 6),
          const Rect.fromLTWH(-2, -3, 4, 6),
        ));
      },
    );

    test('a rotated frame is turned back upright', () async {
      final sprite = await showing('f2');
      final log = _DrawLog();
      sprite.render(log, const Size(100, 100));
      expect(log.turns, contains(-math.pi / 2));
      final (src, dst) = log.draws.single;
      expect(src, const Rect.fromLTWH(12, 0, 6, 4));
      expect(dst.size, const Size(6, 4));
    });

    test('a whole frame is drawn and batched as before', () async {
      final sprite = await showing('f0');
      final log = _DrawLog();
      sprite.render(log, const Size(100, 100));
      expect(log.draws.single, (
        const Rect.fromLTWH(0, 0, 8, 8),
        const Rect.fromLTWH(-4, -4, 8, 8),
      ));
    });
  });

  group('frame events and speed (C35, C37)', () {
    test('an event at time zero fires as a clip that does not loop '
        'begins', () async {
      final heard = <String>[];
      animations.signals.listen((s) => heard.add(s.name));
      hero(SpriteAnimationComponent(atlasPath: 'a.json', clip: 'land'));
      await settle();
      world.update(0.05);
      expect(heard, ['touch']);
    });

    test('an event with no time fires at the start, and the frame goes '
        'on', () async {
      final heard = <String>[];
      animations.signals.listen((s) => heard.add(s.name));
      hero(SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle'));
      await settle();
      expect(() => world.update(0.3), returnsNormally);
      expect(heard, containsAll(['start', 'untimed', 'blink']));
    });

    test('a negative speed plays the clip backwards from its end', () async {
      final heard = <String>[];
      animations.signals.listen((s) => heard.add(s.name));
      final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle')
        ..speed = -1;
      hero(c);
      await settle();
      final idle = animations.clipOf(
        animations.atlasOf(world.entities.last)!,
        c,
      );
      // 0.6 s long; frames end at 0.1, 0.2, 0.3 and 0.6.
      world.update(0.05); // 0.55
      expect(c.frameIndex, idle.frames.length - 1);
      world.update(0.35); // 0.2: back past the blink at 0.25
      expect(heard, contains('blink'));
      world.update(0.15); // 0.05: into the first frame
      expect(c.frameIndex, 0);
      world.update(0.1); // round to the end again: it loops
      expect(c.frameIndex, idle.frames.length - 1);
      expect(c.isPlaying, isTrue);
    });
  });

  group('atlas files (C37)', () {
    test(
      'Aseprite tags written as doubles, or backwards, still read',
      () async {
        final atlas = await loader.loadAtlas('a.json');
        expect(atlas.getClip('idle')!.frames, hasLength(4));
        expect(atlas.getClip('land')!.frames, hasLength(4));
      },
    );

    test('an animation event with no time is at the start', () {
      final event = AnimationEvent.fromJson({'name': 'x'});
      expect(event.time, 0);
      expect(AnimationEvent.fromJson({'time': 'soon'}).name, '');
    });

    test('a clip finds its frame by time', () {
      const clip = AtlasAnimationClip(
        name: 'c',
        frames: [
          AtlasFrame(regionName: 'a', duration: 0.1),
          AtlasFrame(regionName: 'b', duration: 0),
          AtlasFrame(regionName: 'c', duration: 0.3),
        ],
      );
      expect(clip.totalDuration, closeTo(0.4, 1e-12));
      expect(clip.frameEnds, [0.1, 0.1, closeTo(0.4, 1e-12)]);
      expect(clip.frameIndexAt(-1), 0);
      expect(clip.frameIndexAt(0.05), 0);
      expect(
        clip.frameIndexAt(0.1),
        2,
        reason: 'a frame of no length is skipped',
      );
      expect(clip.frameIndexAt(0.39), 2);
      expect(clip.frameIndexAt(5), 2);
    });
  });

  group('loads that fail are said once', () {
    test('an image that cannot be loaded', () async {
      final said = say();
      for (var i = 0; i < 2; i++) {
        world.createEntityWithComponents([
          TransformComponent(),
          SpriteComponent(spritePath: 'missing.png'),
        ]);
      }
      await settle();
      world.update(0.1);
      expect(said.where((m) => m.contains('missing.png')), hasLength(1));
    });

    test('an atlas that cannot be loaded', () async {
      final said = say();
      hero(SpriteAnimationComponent(atlasPath: 'missing.json'));
      hero(SpriteAnimationComponent(atlasPath: 'missing.json'));
      await settle();
      world.update(0.1);
      expect(said.where((m) => m.contains('missing.json')), hasLength(1));
    });

    test('an animator graph that cannot be loaded', () async {
      final said = say();
      final w = World();
      addTearDown(w.dispose);
      registerSpriteSystems(
        w,
        loader: loader,
        graphLoader: (path) async => throw StateError('no graph'),
      );
      for (var i = 0; i < 2; i++) {
        w.createEntityWithComponents([
          TransformComponent(),
          SpriteAnimationComponent(atlasPath: 'a.json'),
          AnimatorComponent(graphPath: 'gone.animator.json'),
        ]);
      }
      w.update(0);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      w.update(0.1);
      expect(said.where((m) => m.contains('gone.animator.json')), hasLength(1));
    });
  });

  group('per-frame work (P18, P20)', () {
    test('a sprite switched off and on keeps playing without loading its '
        'atlas again', () async {
      final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle');
      final e = hero(c);
      await settle();
      final loads = loader.atlasLoads;
      final sprite = spriteOf(e);
      e.isActive = false;
      world.createEntity(); // the world's structure changes meanwhile
      world.update(0.1);
      e.isActive = true;
      world.createEntity();
      world.update(0.05);
      expect(loader.atlasLoads, loads);
      expect(spriteOf(e), same(sprite));
      expect(c.elapsed, closeTo(0.05, 1e-9));
    });

    test(
      'an animator switched off and on starts again from its entry',
      () async {
        final graph = AnimatorGraph.fromJson({
          'entry': 'a',
          'parameters': [
            {'name': 'go', 'type': 'trigger'},
          ],
          'states': [
            {'name': 'a', 'clip': 'idle'},
            {'name': 'b', 'clip': 'idle'},
          ],
          'transitions': [
            {
              'from': 'a',
              'to': 'b',
              'conditions': [
                {'param': 'go', 'op': '==', 'value': true},
              ],
            },
          ],
        });
        final w = World();
        addTearDown(w.dispose);
        registerSpriteSystems(
          w,
          loader: loader,
          graphLoader: (_) async => graph,
        );
        final animator = AnimatorComponent(graphPath: 'g.animator.json');
        final e = w.createEntityWithComponents([
          TransformComponent(),
          SpriteAnimationComponent(atlasPath: 'a.json'),
          animator,
        ]);
        w.update(0);
        await Future<void>.delayed(Duration.zero);
        w.update(0);
        animator.setTrigger('go');
        w.update(0.1);
        expect(animator.currentState, 'b');
        e.isActive = false;
        w.createEntity(); // the world's structure changes meanwhile
        w.update(0.1);
        e.isActive = true;
        w.createEntity();
        w.update(0);
        await Future<void>.delayed(Duration.zero);
        w.update(0);
        expect(animator.currentState, 'a');
      },
    );

    test('a graph tries Any State first, then by priority, then in order', () {
      final graph = AnimatorGraph.fromJson({
        'states': [
          {'name': 'idle'},
          {'name': 'run'},
          {'name': 'hurt'},
          {'name': 'idle'},
        ],
        'transitions': [
          {'from': 'idle', 'to': 'run'},
          {'from': 'idle', 'to': 'hurt', 'priority': 2},
          {'from': '*', 'to': 'hurt'},
          {'from': '*', 'to': 'idle'},
          {'from': 'idle', 'to': 'nowhere'},
          {'from': 'idle', 'to': 'run', 'priority': 2},
        ],
      });
      final order = graph.transitionsFrom('idle');
      expect(
        [for (final t in order) '${t.from}>${t.to}:${t.priority}'],
        ['*>hurt:0', 'idle>hurt:2', 'idle>run:2', 'idle>run:0'],
      );
      expect(identical(graph.transitionsFrom('idle'), order), isTrue);
      expect(
        identical(graph.stateNamed('idle'), graph.states.first),
        isTrue,
        reason: 'the first of two by one name',
      );
    });
  });
}
