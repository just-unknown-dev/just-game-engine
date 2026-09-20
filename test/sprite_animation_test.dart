// Sprites that play in the game itself, not only in an editor: an atlas, a
// clip, each frame for as long as the artist said.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Four 8×8 frames in a row. Frames 0–1 are `idle` (100 ms, 300 ms), 1–3 are
/// `swing` played ping-pong, and 2–3 are `land`, which does not loop.
Map<String, dynamic> _atlasJson() => {
  'frames': {
    for (var i = 0; i < 4; i++)
      'hero $i': {
        'frame': {'x': i * 8, 'y': 0, 'w': 8, 'h': 8},
        'rotated': false,
        'trimmed': false,
        'spriteSourceSize': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
        'sourceSize': {'w': 8, 'h': 8},
        'duration': i == 1 ? 300 : 100,
      },
  },
  'meta': {
    'app': 'https://www.aseprite.org/',
    'image': 'hero.png',
    'size': {'w': 32, 'h': 8},
    'frameTags': [
      {'name': 'idle', 'from': 0, 'to': 1, 'direction': 'forward'},
      {'name': 'swing', 'from': 1, 'to': 3, 'direction': 'pingpong'},
      {'name': 'land', 'from': 2, 'to': 3, 'direction': 'forward'},
    ],
    'just': {
      'clips': {
        'land': {'loop': false},
      },
      'events': {
        'idle': [
          {'time': 0.0, 'name': 'breathe'},
          {'time': 0.25, 'name': 'blink'},
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

class _FakeLoader extends SpriteAssetLoader {
  int atlasLoads = 0;
  final List<String> evicted = [];

  @override
  Future<ui.Image> loadImage(String path) async {
    if (path.contains('missing')) throw StateError('no such image');
    return _image(16, 16);
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) {
    atlasLoads++;
    return SpriteAtlas.fromJson(
      _atlasJson(),
      basePath: 'assets/sprites/',
      loadImage: (_) async => _image(32, 8),
    );
  }

  @override
  void evict(String path) => evicted.add(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late _FakeLoader loader;
  late SpriteAnimationSystem animations;

  setUp(() {
    world = World();
    loader = _FakeLoader();
    registerSpriteSystems(world, loader: loader);
    animations = world.systems.whereType<SpriteAnimationSystem>().single;
  });
  tearDown(() => world.dispose());

  /// Lets a pending load finish, then runs a frame of no time.
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

  test('a world with no editor shows and plays a sprite', () async {
    final e = hero(
      SpriteAnimationComponent(
        atlasPath: 'assets/sprites/hero.json',
        clip: 'idle',
      ),
    );
    expect(e.getComponent<RenderableComponent>(), isNull);
    await settle();

    final sprite = spriteOf(e);
    expect(sprite.image, isNotNull);
    expect(sprite.sourceRect, const Rect.fromLTWH(0, 0, 8, 8));
    expect(sprite.renderSize, const Size(8, 8));
    expect(e.getComponent<SpriteAnimationComponent>()!.isPlaying, isTrue);
  });

  test('each frame lasts as long as the atlas says', () async {
    final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle');
    final e = hero(c);
    await settle();

    world.update(0.09);
    expect(c.frameIndex, 0);
    world.update(0.02); // 0.11: into the 300 ms frame
    expect(c.frameIndex, 1);
    expect(spriteOf(e).sourceRect!.left, 8);
    world.update(0.28); // 0.39: still there
    expect(c.frameIndex, 1);
    world.update(0.02); // 0.41: looped
    expect(c.frameIndex, 0);
    expect(c.elapsed, closeTo(0.01, 1e-9));
  });

  test('ping-pong plays there and back without repeating the ends', () async {
    final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'swing');
    final e = hero(c);
    await settle();
    final clip = animations.clipOf(animations.atlasOf(e)!, c);
    expect(
      [for (final f in clip.frames) f.regionName],
      ['hero 1', 'hero 2', 'hero 3', 'hero 2'],
    );
  });

  test('speed scales time; zero holds the frame', () async {
    final c = SpriteAnimationComponent(
      atlasPath: 'a.json',
      clip: 'idle',
      speed: 2,
    );
    hero(c);
    await settle();
    world.update(0.06);
    expect(c.frameIndex, 1);
    c.speed = 0;
    world.update(10);
    expect(c.frameIndex, 1);
  });

  test(
    'a clip that does not loop ends on its last frame and says so',
    () async {
      final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'land');
      final e = hero(c);
      final heard = <String>[];
      animations.signals.listen((s) => heard.add('${s.clip}:${s.name}'));
      await settle();

      world.update(5);
      expect(c.isComplete, isTrue);
      expect(c.isPlaying, isFalse);
      expect(c.frameIndex, 1);
      expect(spriteOf(e).sourceRect!.left, 24);
      expect(heard, ['land:completed']);

      world.update(5);
      expect(heard, hasLength(1), reason: 'once');
      c.play();
      expect(c.isComplete, isFalse, reason: 'play again starts over');
    },
  );

  test('events fire once per crossing, and again each loop', () async {
    final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle');
    hero(c);
    final heard = <String>[];
    animations.signals.listen((s) => heard.add(s.name));
    await settle();

    world.update(0.2);
    expect(heard, isEmpty, reason: 'time zero belongs to the wrap');
    world.update(0.1); // 0.3: crossed 0.25
    expect(heard, ['blink']);
    world.update(0.01);
    expect(heard, ['blink']);
    world.update(0.15); // wraps past 0.4
    expect(heard, ['blink', 'breathe']);
  });

  test('switchClip restarts; the same clip again does not', () async {
    final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'idle');
    hero(c);
    await settle();
    world.update(0.2);
    c.switchClip('idle');
    expect(c.elapsed, closeTo(0.2, 1e-9));
    c.switchClip('swing');
    expect(c.elapsed, 0);
    expect(c.frameIndex, 0);
  });

  test(
    'a clip the atlas lacks plays every frame; no atlas shows nothing',
    () async {
      final c = SpriteAnimationComponent(atlasPath: 'a.json', clip: 'nope');
      final e = hero(c);
      final blank = hero(SpriteAnimationComponent());
      await settle();
      expect(animations.clipOf(animations.atlasOf(e)!, c).frames, hasLength(4));
      expect(blank.getComponent<RenderableComponent>(), isNull);
    },
  );

  test(
    'pixel art is not smoothed, and so is not batched with sprites that are',
    () async {
      final c = SpriteAnimationComponent(atlasPath: 'a.json');
      final e = hero(c);
      await settle();
      expect(spriteOf(e).filterQuality, ui.FilterQuality.none);
      expect(spriteOf(e).batchImage, isNull);
      c.pixelArt = false;
      world.update(0);
      expect(spriteOf(e).batchImage, isNotNull);
    },
  );

  test('reload reads the atlas again', () async {
    hero(SpriteAnimationComponent(atlasPath: 'a.json'));
    await settle();
    expect(loader.atlasLoads, 1);
    animations.reload('a.json');
    await settle();
    expect(loader.evicted, ['a.json']);
    expect(loader.atlasLoads, 2);
  });

  test('an old grid-sheet JSON still loads, as an atlas', () async {
    final atlas = await SpriteAtlas.fromJson(
      {
        'meta': {'frameWidth': 16, 'frameHeight': 8, 'columns': 2, 'rows': 2},
        'clips': {
          'run': {
            'frames': [0, 1, 3],
            'fps': 10,
          },
          'idle': {'row': 1, 'start': 0, 'end': 1, 'loop': false},
        },
      },
      basePath: 'assets/sprites/',
      jsonPath: 'assets/sprites/coin.json',
      loadImage: (path) async {
        expect(path, 'assets/sprites/coin.png', reason: 'beside the JSON');
        return _image(32, 16);
      },
    );
    expect(atlas.regionCount, 4);
    expect(atlas.getRegion('3')!.frame, const Rect.fromLTWH(16, 8, 16, 8));
    final run = atlas.requireClip('run');
    expect([for (final f in run.frames) f.regionName], ['0', '1', '3']);
    expect(run.frames.first.duration, closeTo(0.1, 1e-9));
    expect(atlas.requireClip('idle').loop, isFalse);
    expect(atlas.requireClip('idle').frames, hasLength(2));
  });

  group('still sprites', () {
    test('an image, and a region of an atlas', () async {
      final whole = world.createEntityWithComponents([
        TransformComponent(),
        SpriteComponent(spritePath: 'assets/tree.png'),
      ]);
      final part = world.createEntityWithComponents([
        TransformComponent(),
        SpriteComponent(spritePath: '', atlasPath: 'a.json', region: 'hero 2'),
      ]);
      await settle();
      expect(spriteOf(whole).sourceRect, isNull);
      expect(spriteOf(part).sourceRect, const Rect.fromLTWH(16, 0, 8, 8));

      part.getComponent<SpriteComponent>()!.flipX = true;
      world.update(0);
      expect(spriteOf(part).flipX, isTrue, reason: 'options stay current');
    });

    test('a wrong path is retried once it is corrected', () async {
      final c = SpriteComponent(spritePath: 'assets/missing.png');
      final e = world.createEntityWithComponents([TransformComponent(), c]);
      await settle();
      expect(e.getComponent<RenderableComponent>(), isNull);
      c.spritePath = 'assets/found.png';
      await settle();
      expect(e.getComponent<RenderableComponent>(), isNotNull);
    });
  });

  group('scene format v2 → v3', () {
    Map<String, dynamic> scene(List<Map<String, dynamic>> components) => {
      'version': 2,
      'entities': [
        {'name': 'Hero', 'components': components},
      ],
    };

    List<dynamic> migrated(List<Map<String, dynamic>> components) =>
        ((SceneFormat.migrate(scene(components))['entities'] as List).single
                as Map)['components']
            as List;

    test('an animated sprite becomes a sprite animation', () {
      final out = migrated([
        {
          'type': 'AnimatedSpriteComponent',
          'fields': {
            'spritePath': 'assets/sprites/hero.png',
            'jsonPath': 'assets/sprites/hero_anim.json',
            'activeClip': 'run',
            'playOnStart': false,
            'columns': 4,
            'clips': <String, dynamic>{},
          },
        },
      ]);
      expect(out.single, {
        'type': 'SpriteAnimationComponent',
        'fields': {
          'atlasPath': 'assets/sprites/hero_anim.json',
          'clip': 'run',
          'playOnStart': false,
          'speed': 1.0,
          'flipX': false,
          'flipY': false,
          'tint': null,
          'pixelArt': false,
        },
      });
      expect(V2ToV3.needsAtlas, isEmpty);
    });

    test('one with only a grid is pointed beside its sheet, and listed', () {
      final out = migrated([
        {
          'type': 'AnimatedSpriteComponent',
          'fields': {'spritePath': 'assets/sprites/coin.png', 'jsonPath': ''},
        },
      ]);
      expect(
        ((out.single as Map)['fields'] as Map)['atlasPath'],
        'assets/sprites/coin.json',
      );
      expect(V2ToV3.needsAtlas, ['Hero']);
    });

    test('animation state goes; a sprite loses its frame number', () {
      final out = migrated([
        {
          'type': 'AnimationStateComponent',
          'fields': {'animName': 'idle'},
        },
        {
          'type': 'SpriteComponent',
          'fields': {'spritePath': 'a.png', 'frame': 3, 'flipX': true},
        },
      ]);
      expect(out.single, {
        'type': 'SpriteComponent',
        'fields': {'spritePath': 'a.png', 'flipX': true},
      });
    });

    test('what it writes loads', () {
      registerCoreCodecs();
      final out = migrated([
        {
          'type': 'AnimatedSpriteComponent',
          'fields': {'jsonPath': 'a.json', 'activeClip': 'idle'},
        },
      ]);
      final c = ComponentCodecRegistry.instance.decode(
        (out.single as Map).cast<String, dynamic>(),
      );
      expect(c, isA<SpriteAnimationComponent>());
      expect((c! as SpriteAnimationComponent).clip, 'idle');
    });
  });
}
