// Parallax on entities: a ParallaxComponent is scrolled and drawn behind the
// world by ParallaxRenderSystem, one of the default systems — and the
// deprecated engine.parallax list stands aside for a background a component
// already draws.

// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<ui.Image> _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

/// Where each image was drawn, in order.
class _Draws extends TestRecordingCanvas {
  final List<(ui.Image, Rect)> images = [];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    images.add((image, dst));
    super.drawImageRect(image, src, dst, paint);
  }
}

/// One non-repeating layer, so each draw is one `drawImageRect`.
ParallaxBackground _background(
  ui.Image image, {
  double scrollFactorX = 0.5,
  double velocityX = 0,
}) => ParallaxBackground(
  layers: [
    ParallaxLayer(
      image: image,
      scrollFactorX: scrollFactorX,
      scrollFactorY: 0,
      velocityX: velocityX,
      repeat: false,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(320, 180);

  late World world;
  late RenderHookChain hooks;
  late Camera camera;
  late ParallaxRenderSystem system;
  late ui.Image sky;
  late ui.Image hills;

  setUp(() async {
    world = World();
    hooks = RenderHookChain();
    camera = Camera();
    system = ParallaxRenderSystem(backgroundHooks: hooks, camera: camera);
    world.addSystem(system);
    sky = await _image(8, 4);
    hills = await _image(6, 3);
  });

  tearDown(() {
    world.dispose();
    sky.dispose();
    hills.dispose();
  });

  test('draws through the background hooks, against the camera', () {
    final bg = _background(sky, scrollFactorX: 0.5);
    world.createEntityWithComponents([ParallaxComponent(background: bg)]);
    camera.position = const Offset(40, 0);
    world.update(0);

    final canvas = _Draws();
    hooks(canvas, size);
    expect(bg.cameraPosition, const Offset(40, 0));
    expect(canvas.images, hasLength(1));
    // Half the camera's 40 px: the layer moved 20 px left.
    expect(canvas.images.single.$2.left, -20);
  });

  test('auto-scroll advances with each update', () {
    final bg = _background(sky, scrollFactorX: 0, velocityX: 10);
    world.createEntityWithComponents([ParallaxComponent(background: bg)]);
    world.update(0.5);
    world.update(0.5);

    final canvas = _Draws();
    hooks(canvas, size);
    expect(canvas.images.single.$2.left, -10);
  });

  test('backgrounds draw by LayerComponent, then creation order', () {
    world.createEntityWithComponents([
      ParallaxComponent(background: _background(hills)),
      LayerComponent(layer: 2),
    ]);
    world.createEntityWithComponents([
      ParallaxComponent(background: _background(sky)),
      LayerComponent(layer: 1),
    ]);
    world.update(0);

    final canvas = _Draws();
    hooks(canvas, size);
    expect([for (final d in canvas.images) d.$1], [sky, hills]);
  });

  test('a switched-off entity or system draws nothing', () {
    final entity = world.createEntityWithComponents([
      ParallaxComponent(background: _background(sky)),
    ]);
    world.update(0);

    system.isActive = false;
    final off = _Draws();
    hooks(off, size);
    expect(off.images, isEmpty);

    system.isActive = true;
    entity.isActive = false;
    world.update(0);
    final hidden = _Draws();
    hooks(hidden, size);
    expect(hidden.images, isEmpty);
  });

  test('removed from the world, it leaves the hooks', () {
    expect(hooks.isEmpty, isFalse);
    world.removeSystem(system);
    expect(hooks.isEmpty, isTrue);
  });

  test('the deprecated list skips a background a component draws', () {
    final bg = _background(sky);
    final legacy = ParallaxSystem()..addBackground(bg);
    final entity = world.createEntityWithComponents([
      ParallaxComponent(background: bg),
    ]);
    world.update(0);

    final both = _Draws();
    legacy.render(both, size);
    hooks(both, size);
    expect(both.images, hasLength(1), reason: 'drawn once, not twice');

    // Once no component holds it, the list draws it again.
    world.destroyEntity(entity);
    world.update(0);
    final listOnly = _Draws();
    legacy.render(listOnly, size);
    hooks(listOnly, size);
    expect(listOnly.images, hasLength(1));
  });

  test('a default system, on the engine\'s background hooks', () async {
    final engine = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.all),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    final parallax = engine.world.getSystem<ParallaxRenderSystem>();
    expect(parallax, isNotNull);
    expect(parallax!.backgroundHooks, same(engine.rendering.backgroundHooks));
    expect(parallax.camera, same(engine.cameraSystem.mainCamera));

    final headless = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.headless),
    );
    addTearDown(headless.dispose);
    await headless.initialize();
    expect(headless.world.hasSystem<ParallaxRenderSystem>(), isFalse);
  });
}
