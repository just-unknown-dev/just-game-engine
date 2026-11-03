// A sprite's own image is disposed once nothing shows it — replaced,
// cleared, or its entity gone — and an image the loader keeps is never
// disposed by the sprite system.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Hands out a new 1×1 image per load, and remembers them.
final class _Loader extends SpriteAssetLoader {
  _Loader({required this.callerDisposesImages});

  @override
  final bool callerDisposesImages;

  final List<ui.Image> images = [];

  @override
  Future<ui.Image> loadImage(String path) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    images.add(image);
    return image;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnsupportedError(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  Future<void> frame() async {
    world.update(1 / 60);
    await pumpEventQueue();
    world.update(1 / 60);
  }

  test('its own images are disposed once nothing shows them', () async {
    final loader = _Loader(callerDisposesImages: true);
    world.addSystem(SpriteLoadSystem(loader: loader));
    final sprite = SpriteComponent(spritePath: 'a.png');
    final e = world.createEntityWithComponents([TransformComponent(), sprite]);
    await frame();
    expect(loader.images, hasLength(1));
    expect(e.hasComponent<RenderableComponent>(), isTrue);

    sprite.spritePath = 'b.png';
    await frame();
    expect(loader.images, hasLength(2));
    expect(loader.images[0].debugDisposed, isTrue, reason: 'replaced');
    expect(loader.images[1].debugDisposed, isFalse, reason: 'shown');

    sprite.spritePath = '';
    await frame();
    expect(e.hasComponent<RenderableComponent>(), isFalse);
    expect(loader.images[1].debugDisposed, isTrue, reason: 'cleared');

    final other = world.createEntityWithComponents([TransformComponent(), SpriteComponent(spritePath: 'c.png')]);
    await frame();
    world.destroyEntity(other);
    await frame();
    expect(loader.images.last.debugDisposed, isTrue, reason: 'its entity gone');
  });

  test('images the loader keeps are left alone', () async {
    final loader = _Loader(callerDisposesImages: false);
    world.addSystem(SpriteLoadSystem(loader: loader));
    final sprite = SpriteComponent(spritePath: 'a.png');
    world.createEntityWithComponents([TransformComponent(), sprite]);
    await frame();
    sprite.spritePath = 'b.png';
    await frame();
    expect(loader.images.map((i) => i.debugDisposed), [false, false]);
  });
}
