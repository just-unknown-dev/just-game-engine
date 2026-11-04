// What the sprite systems hold, and give back: an atlas or image they show
// is counted in the asset manager while they show it, so another user's
// release does not take it away; once nothing shows it — its component, its
// entity or the system gone — the renderable they added comes off and the
// asset is let go. An atlas unloaded under them is loaded again, and an
// atlas whose later page cannot be read lets go of the pages it read.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Bundle extends CachingAssetBundle {
  final Map<String, ByteData> data = {};

  @override
  Future<ByteData> load(String key) async =>
      data[key] ?? (throw FlutterError('No asset $key'));
}

Future<ByteData> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF00FF00),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!;
}

ByteData _json(Object value) =>
    ByteData.sublistView(utf8.encode(jsonEncode(value)));

const _atlas = 'assets/h/hero.json';
const _page = 'assets/h/hero.png';
const _solo = 'assets/h/solo.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Bundle bundle;
  setUpAll(() async {
    bundle = _Bundle()
      ..data[_page] = await _png(16, 8)
      ..data[_solo] = await _png(4, 4)
      ..data['assets/h/p0.png'] = await _png(8, 8)
      ..data[_atlas] = _json({
        'frames': {
          'a.png': {
            'frame': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
            'sourceSize': {'w': 8, 'h': 8},
          },
          'b.png': {
            'frame': {'x': 8, 'y': 0, 'w': 8, 'h': 8},
            'sourceSize': {'w': 8, 'h': 8},
          },
        },
        'meta': {
          'image': 'hero.png',
          'size': {'w': 16, 'h': 8},
        },
      })
      ..data['assets/h/two.json'] = _json({
        'textures': [
          for (final page in ['p0.png', 'p1.png'])
            {
              'image': page,
              'size': {'w': 8, 'h': 8},
              'frames': {
                '$page-a': {
                  'frame': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
                },
              },
            },
        ],
        'meta': {'app': 'https://www.codeandweb.com/texturepacker'},
      });
  });

  late AssetManager assets;
  late World world;
  late SpriteLoadSystem stills;
  late SpriteAnimationSystem animations;

  setUp(() {
    assets = AssetManager(bundle: bundle);
    final loader = BundleSpriteAssetLoader(assets);
    world = World()
      ..addSystem(stills = SpriteLoadSystem(loader: loader))
      ..addSystem(animations = SpriteAnimationSystem(loader: loader));
  });
  tearDown(() => world.dispose());

  /// Runs frames until [done] — images decode off the Dart thread.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      world.update(1 / 60);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    world.update(1 / 60);
    expect(done(), isTrue, reason: 'never settled');
  }

  Sprite? spriteOf(Entity e) =>
      e.getComponent<RenderableComponent>()?.renderable as Sprite?;

  bool shows(Entity e) => spriteOf(e)?.image != null;

  test('a sprite holds the atlas it shows', () async {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      SpriteComponent(spritePath: '', atlasPath: _atlas, region: 'a'),
    ]);
    await until(() => shows(e));
    final image = spriteOf(e)!.image!;
    expect(assets.refCount(_atlas, AssetType.atlas), 1);

    // Another user done with it does not take it away.
    await assets.acquire(_atlas, AssetType.atlas);
    assets.release(_atlas, AssetType.atlas);
    expect(assets.isLoaded(_atlas), isTrue);
    expect(image.debugDisposed, isFalse);

    // Its component gone: the renderable comes off, the atlas is let go.
    e.removeComponent<SpriteComponent>();
    world.update(0);
    expect(e.hasComponent<RenderableComponent>(), isFalse);
    expect(assets.refCount(_atlas, AssetType.atlas), 0);
    expect(assets.isLoaded(_atlas), isFalse);
    await pumpEventQueue();
    expect(assets.isLoaded(_page), isFalse, reason: 'its page goes too');
    expect(image.debugDisposed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a playing sprite holds its atlas, and lets go with its '
      'component', () async {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      SpriteAnimationComponent(atlasPath: _atlas),
    ]);
    await until(() => shows(e));
    expect(assets.refCount(_atlas, AssetType.atlas), 1);

    e.removeComponent<SpriteAnimationComponent>();
    world.update(0);
    expect(
      e.hasComponent<RenderableComponent>(),
      isFalse,
      reason: 'its last frame used to stay drawn',
    );
    expect(assets.isLoaded(_atlas), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an image of its own is disposed once its component goes', () async {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      SpriteComponent(spritePath: _solo),
    ]);
    await until(() => shows(e));
    final image = spriteOf(e)!.image!;
    expect(assets.refCount(_solo, AssetType.image), 1);

    e.removeComponent<SpriteComponent>();
    world.update(0);
    expect(e.hasComponent<RenderableComponent>(), isFalse);
    expect(image.debugDisposed, isTrue);
    expect(assets.isLoaded(_solo), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a system removed takes off what it added and lets go', () async {
    final still = world.createEntityWithComponents([
      TransformComponent(),
      SpriteComponent(spritePath: _solo),
    ]);
    final playing = world.createEntityWithComponents([
      TransformComponent(),
      SpriteAnimationComponent(atlasPath: _atlas),
    ]);
    await until(() => shows(still) && shows(playing));
    final image = spriteOf(still)!.image!;

    world
      ..removeSystem(stills)
      ..removeSystem(animations);
    expect(still.hasComponent<RenderableComponent>(), isFalse);
    expect(playing.hasComponent<RenderableComponent>(), isFalse);
    expect(image.debugDisposed, isTrue);
    expect(assets.refCount(_solo, AssetType.image), 0);
    expect(assets.refCount(_atlas, AssetType.atlas), 0);
    expect(assets.isLoaded(_atlas), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an atlas unloaded under its sprites is loaded again', () async {
    final still = world.createEntityWithComponents([
      TransformComponent(),
      SpriteComponent(spritePath: '', atlasPath: _atlas, region: 'b'),
    ]);
    final playing = world.createEntityWithComponents([
      TransformComponent(),
      SpriteAnimationComponent(atlasPath: _atlas),
    ]);
    await until(() => shows(still) && shows(playing));
    final before = spriteOf(playing)!.image!;

    assets.unload(_atlas);
    expect(before.debugDisposed, isTrue);
    world.update(0);
    // Nothing draws the disposed page meanwhile.
    for (final e in [still, playing]) {
      final image = spriteOf(e)?.image;
      expect(image == null || !image.debugDisposed, isTrue);
    }

    await until(() => shows(still) && shows(playing));
    expect(spriteOf(still)!.image!.debugDisposed, isFalse);
    expect(spriteOf(playing)!.image!.debugDisposed, isFalse);
    expect(assets.refCount(_atlas, AssetType.atlas), 2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an atlas whose second page cannot be read lets go of the '
      'first', () async {
    await expectLater(
      SpriteAtlas.fromAsset('assets/h/two.json', assets: assets),
      throwsA(anything),
    );
    await pumpEventQueue();
    expect(assets.isLoaded('assets/h/p0.png'), isFalse);
    expect(assets.refCount('assets/h/p0.png', AssetType.image), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a sprite from an asset holds its image until disposed', () async {
    final sprite = await Sprite.fromAsset(_solo, assets: assets);
    expect(assets.refCount(_solo, AssetType.image), 1);
    sprite.dispose();
    expect(assets.refCount(_solo, AssetType.image), 0);
    expect(assets.isLoaded(_solo), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the bundle loader forgets only what nothing holds', () async {
    final loader = BundleSpriteAssetLoader(assets);
    final image = await loader.loadImage(_solo);
    await loader.acquireAtlas(_atlas);
    loader
      ..evict(_solo)
      ..evict(_atlas);
    expect(assets.isLoaded(_solo), isFalse, reason: 'its clone was handed out');
    expect(image.debugDisposed, isFalse);
    expect(assets.isLoaded(_atlas), isTrue, reason: 'it is held');
    loader.releaseAtlas(_atlas);
    expect(assets.isLoaded(_atlas), isFalse);
    image.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a plain fromAsset atlas keeps its pages held while it is '
      'loaded', () async {
    final atlas = await SpriteAtlas.fromAsset(_atlas, assets: assets);
    expect(assets.refCount(_page, AssetType.image), 1);
    final page = atlas.pages.single.image!;
    assets.unload(_atlas);
    expect(page.debugDisposed, isTrue);
    await pumpEventQueue();
    expect(assets.refCount(_page, AssetType.image), 0);
    expect(assets.isLoaded(_page), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
