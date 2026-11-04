// RenderingEngine's frame and what it lets go of; text bounds; world-space
// bounds; what a renderable lets go of when it leaves its entity.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A world-space box of 10 × 10 at its position.
class _Box extends Renderable {
  int disposed = 0;

  @override
  bool get boundsAreWorldSpace => true;

  @override
  void render(Canvas canvas, Size size) {}

  @override
  Rect? get bounds =>
      Rect.fromCenter(center: position.toOffset(), width: 10, height: 10);

  @override
  void dispose() => disposed++;
}

/// Draws the frame image it is handed, and keeps it.
class _Keeping implements ScreenPass {
  final List<ui.Image> frames = [];

  @override
  bool get active => true;

  @override
  ui.ImageFilter? filter(ui.Size size, double pixelRatio) => null;

  @override
  void paint(ui.Canvas canvas, ui.Image frame, ui.Size size, double ratio) {
    frames.add(frame);
    canvas.drawImage(frame, Offset.zero, Paint());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RenderingEngine rendering;

  setUp(() {
    rendering = RenderingEngine()
      ..camera = OutputCamera(viewportSize: const Size(800, 600))
      ..pixelRatio = 1;
    rendering.initialize();
  });

  void frame() =>
      rendering.render(Canvas(ui.PictureRecorder()), const Size(800, 600));

  group('the frame', () {
    test('runs the background, then the overlay hooks, in screen space', () {
      final log = <String>[];
      rendering
        ..backgroundHooks.add((_, _) => log.add('background'))
        ..overlayHooks.add((_, _) => log.add('world'))
        ..overlayHooks.add((_, _) => log.add('editor'), order: 100);
      frame();
      expect(log, ['background', 'world', 'editor']);
    });

    test('counts what the world reported, and keeps no legacy numbers', () {
      rendering.overlayHooks.add(
        (_, _) => rendering.addFrameStats(
          drawCalls: 3,
          renderedObjects: 4,
          culledObjects: 1,
          batchedSprites: 2,
        ),
      );
      frame();
      final stats = rendering.stats;
      expect(stats['drawCalls'], 4, reason: 'the clear, and the world\'s 3');
      expect(stats['renderedObjects'], 4);
      expect(stats['culledObjects'], 1);
      expect(stats['batchedSprites'], 2);
      expect(
        stats.keys,
        isNot(contains(anyOf('renderables', 'layers', 'usedSpatialIndex'))),
      );
    });
  });

  test('disposing lets go of the frame images the screen passes drew from', () {
    final pass = _Keeping();
    rendering.screenPasses.add(pass);
    frame();
    frame();
    expect(pass.frames, hasLength(2));
    expect(
      pass.frames.first.debugDisposed,
      isFalse,
      reason: 'a frame image is let go one frame later',
    );
    rendering.dispose();
    expect(
      pass.frames.map((f) => f.debugDisposed),
      everyElement(isTrue),
      reason: 'they used to wait for the garbage collector',
    );
  });

  group('text', () {
    Future<List<int>> pixels(TextRenderable text) async {
      final recorder = ui.PictureRecorder();
      text.render(Canvas(recorder), Size.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 60);
      final data = await image.toByteData();
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    }

    TextRenderable make(String text) => TextRenderable(
      text: text,
      textStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 20),
      opacity: 0.5,
      position: Vector3(100, 30, 0),
    );

    test('laid out for its bounds keeps its faded colour', () async {
      final text = make('Hi');
      await pixels(text);
      text.text = 'Hello';
      text.bounds;
      final after = await pixels(text);

      final fresh = await pixels(make('Hello'));
      expect(after.any((b) => b != 0), isTrue);
      expect(
        after,
        fresh,
        reason: 'bounds used to lay it out at full opacity and mark it current',
      );
    });

    test('its bounds are never inside out', () {
      final text = make('Hello')..scale = Vector3(-2, -1, 1);
      final bounds = text.bounds!;
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
      expect(bounds.center, const Offset(100, 30));
      final unflipped = (make('Hello')..scale = Vector3(2, 1, 1)).bounds!;
      expect(bounds, unflipped);
    });

    test('disposed, it is laid out again when drawn after', () async {
      final text = make('Hello');
      final before = await pixels(text);
      text.dispose();
      text.dispose();
      expect(await pixels(text), before);
    });
  });

  group('world-space bounds', () {
    test('every built-in renderable but the custom one says so', () {
      for (final r in <Renderable>[
        Sprite(),
        TextRenderable(text: 'x'),
        RayRenderable(start: Offset.zero, end: const Offset(5, 0)),
        ParticleEmitter(maxParticles: 1),
      ]) {
        expect(r.boundsAreWorldSpace, isTrue, reason: '${r.runtimeType}');
      }
      expect(
        CustomRenderable(onRender: (_, _) {}).boundsAreWorldSpace,
        isFalse,
      );
    });

    test('a synced world-space box on screen is not culled', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final camera = OutputCamera(position: Offset.zero, zoom: 1.0)
        ..viewportSize = const Size(800, 600);
      world
        ..addSystem(ViewCullingSystem(camera: camera))
        ..addSystem(RenderSystem(passes: []));
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3.fromXY(300, 0)),
        CullStateComponent(),
        RenderableComponent(renderable: _Box()),
      ]);
      // A frame draws it — putting it at its entity — then the next update
      // culls.
      world.render(Canvas(ui.PictureRecorder()), const Size(800, 600));
      world.update(0.016);
      expect(
        entity.getComponent<CullStateComponent>()!.isVisible,
        isTrue,
        reason: 'its bounds used to be shifted by its position a second time',
      );
    });
  });

  group('a renderable leaving its entity', () {
    test('is disposed when its component is removed', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final box = _Box();
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: box),
      ]);
      expect(box.disposed, 0);
      entity.removeComponent<RenderableComponent>();
      expect(box.disposed, 1);
    });

    test('is disposed when its entity is destroyed', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final box = _Box();
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: box),
      ]);
      world.destroyEntity(entity);
      expect(box.disposed, 1);
    });

    test('a sprite given its image leaves the image alone', () async {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.red);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      picture.dispose();
      addTearDown(image.dispose);
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: Sprite(image: image)),
      ]);
      world.destroyEntity(entity);
      expect(image.debugDisposed, isFalse);
    });
  });
}
