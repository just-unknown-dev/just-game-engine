// 2-D rendering fixes: a rolled camera's visible area, tint and opacity
// applied once, batching that never reorders, the frame's layers opening
// before the background, the renderable's own layer, y-sorting in place and
// the shader layer of a turned sprite.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/subsystems/rendering/impl/sprite_batching.dart';

Future<ui.Image> _solid(int width, int height, Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

Future<Uint8List> _pixels(void Function(Canvas) draw, int w, int h) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The RGBA bytes of pixel ([x], [y]) in a [w]-wide buffer.
List<int> _at(Uint8List bytes, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return bytes.sublist(i, i + 4);
}

int _mostApart(List<int> a, List<int> b) {
  var most = 0;
  for (var i = 0; i < a.length; i++) {
    most = math.max(most, (a[i] - b[i]).abs());
  }
  return most;
}

class _Logged extends Renderable {
  _Logged(this.name, this.log, {super.layer, super.zOrder, this.bounds});
  final String name;
  final List<String> log;
  final Rect? bounds;

  @override
  void render(Canvas canvas, Size size) => log.add(name);

  @override
  Rect? getBounds() => bounds;
}

/// Logs each sprite it was given when it is flushed, by name of its image.
class _FakeBatch implements SpriteBatchRenderer {
  _FakeBatch(this.name, this.log);
  final String name;
  final List<String> log;
  int _queued = 0;

  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  }) => _queued++;

  @override
  void flush(Canvas canvas) {
    for (var i = 0; i < _queued; i++) {
      log.add(name);
    }
    _queued = 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R1: a rolled camera', () {
    test('at a quarter turn sees the box around its turned view', () {
      final camera = Camera(
        viewportSize: const Size(1600, 900),
        rotation: math.pi / 2,
      );
      final bounds = camera.getVisibleBounds();
      expect(bounds.center.dx, closeTo(0, 1e-9));
      expect(bounds.width, closeTo(900, 1e-6));
      expect(bounds.height, closeTo(1600, 1e-6));

      // Drawn at (100, 450) — on screen — and it used to count as not.
      final shown = camera.worldToScreen(const Offset(0, 700));
      expect(shown.dx, closeTo(100, 1e-6));
      expect(shown.dy, closeTo(450, 1e-6));
      expect(camera.isVisible(const Offset(0, 700)), isTrue);
      expect(
        camera.isRectVisible(
          Rect.fromCenter(center: const Offset(0, 700), width: 4, height: 4),
        ),
        isTrue,
      );
      // Inside the old, unturned box, but off the turned screen.
      expect(camera.isVisible(const Offset(700, 0)), isFalse);
    });

    test('keeps something 10 px in from a corner at 20°', () {
      final camera = Camera(
        viewportSize: const Size(1600, 900),
        rotation: 20 * math.pi / 180,
      );
      final corner = camera.screenToWorld(const Offset(10, 10));
      // Past the unturned box's edge: what was culled.
      expect(corner.dx.abs(), greaterThan(800));
      expect(camera.isVisible(corner), isTrue);
      final rect = Rect.fromCenter(center: corner, width: 4, height: 4);
      expect(camera.isRectVisible(rect), isTrue);
      expect(camera.viewVolume.intersectsAabb(Aabb3.fromRect(rect)), isTrue);

      final view = FrameView()..update(camera, camera.viewportSize);
      expect(view.visibleRect, camera.getVisibleBounds());
      expect(view.visibleRect.contains(corner), isTrue);

      // The legacy engine's culling, and the culling system.
      final rendering = RenderingEngine()..camera = camera;
      rendering.initialize();
      final log = <String>[];
      rendering.addRenderable(_Logged('corner', log, bounds: rect));
      rendering.render(Canvas(ui.PictureRecorder()), camera.viewportSize);
      expect(log, ['corner']);

      final world = World();
      addTearDown(world.dispose);
      world.addSystem(
        ViewCullingSystem(
          camera: camera,
          renderRadiusMultiplier: 1.0,
          hysteresisMargin: 0,
        ),
      );
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3.fromXY(corner.dx, corner.dy)),
        CullStateComponent(),
        RenderableComponent(
          renderable: CircleRenderable(
            radius: 2,
            fillColor: Colors.red,
            position: Vector3.fromXY(corner.dx, corner.dy),
          ),
        ),
      ]);
      world.update(0.016);
      expect(entity.getComponent<CullStateComponent>()!.isVisible, isTrue);
    });

    test('without a roll is the plain viewport over the zoom', () {
      final camera = Camera(
        viewportSize: const Size(800, 600),
        position: const Offset(10, 20),
        zoom: 2,
      );
      expect(
        camera.getVisibleBounds(),
        Rect.fromCenter(center: const Offset(10, 20), width: 400, height: 300),
      );
    });
  });

  group('R2: tint and opacity fade a sprite once', () {
    const tint = Color(0xFF3399CC);
    late ui.Image white;
    setUpAll(() async => white = await _solid(8, 8, Colors.white));

    test('by itself as in a batch', () async {
      final alone = await _pixels(
        (c) => Sprite(
          image: white,
          position: Vector3.fromXY(8, 8),
          tint: tint,
          opacity: 0.5,
        ).render(c, Size.zero),
        16,
        16,
      );
      final batched = await _pixels(
        (c) {
          SpriteBatch(white)
            ..add(
              sourceRect: const Rect.fromLTWH(0, 0, 8, 8),
              position: const Offset(8, 8),
              color: Color(SpriteBatchPlan.spriteColor(tint, 0.5)),
            )
            ..flush(c);
        },
        16,
        16,
      );
      final pixel = _at(alone, 16, 8, 8);
      // Half opacity is half: it used to be a quarter (64).
      expect(pixel[3], closeTo(128, 1));
      expect(_mostApart(alone, batched), lessThanOrEqualTo(1));
    });

    test('the same whether the render system batches it or not', () async {
      Future<Uint8List> drawn({required bool flipped}) {
        final world = World()..initialize();
        world.addSystem(RenderSystem(passes: const []));
        world.createEntityWithComponents([
          TransformComponent(position: Vector3.fromXY(8, 8)),
          RenderableComponent(
            renderable: Sprite(
              image: white,
              tint: tint,
              opacity: 0.5,
              // A flipped sprite is drawn by itself.
              flipX: flipped,
            ),
          ),
        ]);
        return _pixels(
          (c) => world.render(c, const Size(16, 16)),
          16,
          16,
        ).whenComplete(world.dispose);
      }

      final batched = await drawn(flipped: false);
      final alone = await drawn(flipped: true);
      expect(_at(batched, 16, 8, 8)[3], closeTo(128, 1));
      expect(_mostApart(batched, alone), lessThanOrEqualTo(1));
    });

    test("the tint's own alpha fades it, as a shape's does", () async {
      final half = await _pixels(
        (c) => Sprite(
          image: white,
          position: Vector3.fromXY(8, 8),
          tint: tint.withValues(alpha: 0.5),
        ).render(c, Size.zero),
        16,
        16,
      );
      expect(_at(half, 16, 8, 8)[3], closeTo(128, 1));
      expect(
        SpriteBatchPlan.spriteColor(tint.withValues(alpha: 0.5), 1.0) >>> 24,
        128,
      );
    });

    test('a trimmed atlas frame, drawn by itself', () async {
      const region = SpriteRegion(
        name: 'a',
        pageIndex: 0,
        frame: Rect.fromLTWH(0, 0, 4, 4),
        trimmed: true,
        spriteSourceOffset: Offset(2, 2),
        sourceSize: Size(8, 8),
      );
      final bytes = await _pixels(
        (c) => AtlasRegionSprite(
          region: region,
          image: white,
          position: Vector3.fromXY(8, 8),
          tint: tint,
          opacity: 0.5,
        ).render(c, Size.zero),
        16,
        16,
      );
      expect(_at(bytes, 16, 8, 8)[3], closeTo(128, 1));
    });

    test('a parallax layer', () async {
      final bytes = await _pixels(
        (c) => ParallaxBackground(
          layers: [ParallaxLayer(image: white, tint: tint, opacity: 0.5)],
        ).render(c, const Size(16, 16)),
        16,
        16,
      );
      expect(_at(bytes, 16, 8, 8)[3], closeTo(128, 1));
    });
  });

  group('R3: batching keeps the order across images', () {
    late ui.Image one, two;
    setUpAll(() async {
      one = await createTestImage(width: 8, height: 4);
      two = await createTestImage(width: 8, height: 4);
    });

    SpriteBatchRenderer Function(ui.Image) factory(List<String> log) =>
        (atlas) => _FakeBatch(identical(atlas, one) ? 'one' : 'two', log);

    test('in the render system, flipped or not', () {
      final log = <String>[];
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(
        RenderSystem(passes: const [], spriteBatchFactory: factory(log)),
      );
      Entity sprite(ui.Image image) => world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: Sprite(image: image)),
      ]);
      sprite(one);
      sprite(two);
      sprite(one);
      world.render(Canvas(ui.PictureRecorder()), Size.zero);
      // C used to join A's batch and draw under B.
      expect(log, ['one', 'two', 'one']);
    });

    test('in the legacy engine', () {
      final log = <String>[];
      final rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(800, 600))
        ..spriteBatchFactory = factory(log);
      rendering
        ..initialize()
        ..addRenderable(Sprite(image: one))
        ..addRenderable(Sprite(image: two))
        ..addRenderable(Sprite(image: one));
      rendering.render(Canvas(ui.PictureRecorder()), const Size(800, 600));
      expect(log, ['one', 'two', 'one']);
    });
  });

  test('R4: the frame layers open before the background is drawn', () {
    final camera = Camera(viewportSize: const Size(100, 100));
    camera.effectManager.addEffect(
      MotionBlurEffect(velocityFn: () => const Offset(1000, 0)),
    );
    final rendering = RenderingEngine()..camera = camera;
    rendering.initialize();
    rendering.backgroundHooks.add(
      (canvas, size) => canvas.drawCircle(Offset.zero, 1, Paint()),
    );
    final canvas = TestRecordingCanvas();
    rendering.render(canvas, const Size(100, 100));
    final calls = [for (final i in canvas.invocations) i.invocation.memberName];
    final blur = calls.indexOf(#saveLayer);
    expect(blur, greaterThanOrEqualTo(0));
    // The clear and the parallax hook are inside the blur's layer.
    expect(calls.indexOf(#drawRect), greaterThan(blur));
    expect(calls.indexOf(#drawCircle), greaterThan(blur));
    expect(
      calls.lastIndexOf(#restore),
      greaterThan(calls.indexOf(#drawCircle)),
    );
  });

  group('the render system', () {
    late World world;
    late RenderSystem render;
    late List<String> log;

    setUp(() {
      log = [];
      world = World()..initialize();
      render = RenderSystem(passes: const []);
      world.addSystem(render);
    });
    tearDown(() => world.dispose());

    List<String> frame() {
      log.clear();
      world.render(Canvas(ui.PictureRecorder()), const Size(800, 600));
      return List.of(log);
    }

    group('R20: without a LayerComponent the renderable sorts itself', () {
      test('by its own layer and zOrder', () {
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('five', log, layer: 5)),
        ]);
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('zero-b', log, zOrder: 2)),
        ]);
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('zero-a', log)),
        ]);
        // A LayerComponent still wins.
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('one', log, layer: 9)),
          LayerComponent(layer: 1),
        ]);
        expect(frame(), ['zero-a', 'zero-b', 'one', 'five']);
      });

      test('a ray at its default layer draws over layer 0', () {
        final ray = world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(
            renderable: RayRenderable(start: Offset.zero, end: Offset.zero),
          ),
        ]);
        final plain = world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('plain', log)),
        ]);
        expect(render.debugDrawOrder().map((e) => e.$1), [plain, ray]);
      });

      test('the built-in shapes are on layer 0, where they always drew', () {
        expect(RectangleComponent(width: 1, height: 1).renderable.layer, 0);
        expect(CircleComponent(radius: 1).renderable.layer, 0);
        final shape = world.createEntityWithComponents([
          TransformComponent(),
          RectangleComponent(width: 1, height: 1),
        ]);
        final after = world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('after', log)),
        ]);
        expect(render.debugDrawOrder().map((e) => e.$1), [shape, after]);
      });
    });

    group('R21: y-sorted renderables stay on their layer', () {
      Entity at(String name, double y, {int layer = 0, bool ySort = true}) =>
          world.createEntityWithComponents([
            TransformComponent(position: Vector3.fromXY(0, y)),
            RenderableComponent(renderable: _Logged(name, log)..ySort = ySort),
            LayerComponent(layer: layer),
          ]);

      test('after the rest of the layer, by height, under the next layer', () {
        at('front', 50);
        at('top', 1, layer: 1, ySort: false);
        at('back', 10);
        at('ground', 90, ySort: false);
        expect(frame(), ['ground', 'back', 'front', 'top']);
      });

      test('they re-sort as they move', () {
        final a = at('a', 10);
        at('b', 20);
        expect(frame(), ['a', 'b']);
        a.getComponent<TransformComponent>()!.position.y = 30;
        expect(frame(), ['b', 'a']);
      });

      test('with their ShaderComponent', () async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/ink_sparkle.frag',
        );
        addTearDown(ShaderFilterSupport.debugReset);
        ShaderFilterSupport.debugSupportedOverride = false;
        final lines = <String?>[];
        final saved = debugPrint;
        debugPrint = (message, {wrapWidth}) => lines.add(message);
        addTearDown(() => debugPrint = saved);
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(renderable: _Logged('shaded', log)..ySort = true),
          ShaderComponent(program: program),
        ]);
        expect(frame(), ['shaded']);
        // Went through the shader path, which reports the skip here; it
        // used to be drawn plain, past the shader.
        expect(
          lines.where((l) => l!.startsWith('A per-entity ShaderComponent')),
          hasLength(1),
        );
      });
    });
  });

  group('R22: a shaded renderable layer', () {
    late ui.Image image;
    setUpAll(() async => image = await createTestImage(width: 8, height: 4));

    test("holds a turned sprite's corners", () {
      final sprite = Sprite(
        image: image,
        position: Vector3.fromXY(100, 50),
        rotation: math.pi / 2,
      );
      final bounds = RenderSystem.debugShaderBounds(sprite)!;
      expect(bounds.center.dx, closeTo(100, 1e-9));
      expect(bounds.center.dy, closeTo(50, 1e-9));
      expect(bounds.width, closeTo(4, 1e-9));
      expect(bounds.height, closeTo(8, 1e-9));

      sprite.rotation = math.pi / 4;
      final turned = RenderSystem.debugShaderBounds(sprite)!;
      final reach = (8 + 4) / 2 * math.sqrt1_2;
      expect(turned.width, closeTo(2 * reach, 1e-9));
      expect(turned.height, closeTo(2 * reach, 1e-9));
    });

    test('is the bounds as they are when the sprite is not turned', () {
      final sprite = Sprite(image: image, position: Vector3.fromXY(10, 20));
      expect(RenderSystem.debugShaderBounds(sprite), sprite.getBounds());
    });
  });
}
