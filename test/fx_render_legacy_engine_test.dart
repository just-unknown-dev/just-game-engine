// RenderingEngine's own renderables: removal, culling, text bounds.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Counted extends Renderable {
  _Counted(this.log, {this.bounds});
  final List<Renderable> log;
  Rect? bounds;

  @override
  void render(Canvas canvas, Size size) => log.add(this);

  @override
  Rect? getBounds() => bounds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RenderingEngine rendering;
  late List<Renderable> drawn;

  setUp(() {
    drawn = [];
    rendering = RenderingEngine()
      ..camera = Camera(viewportSize: const Size(800, 600));
    rendering.initialize();
  });

  void frame() =>
      rendering.render(Canvas(ui.PictureRecorder()), const Size(800, 600));

  test('a renderable moved to another layer, then removed, is gone', () {
    final r = _Counted(drawn);
    rendering.addRenderable(r);
    frame();
    expect(drawn, [r]);
    r.layer = 5;
    rendering.removeRenderable(r);
    drawn.clear();
    frame();
    expect(drawn, isEmpty, reason: 'it used to stay in its old layer');
    expect(rendering.renderableCount, 0);
  });

  group('more than 200 renderables', () {
    late List<_Counted> all;

    setUp(() {
      all = [
        for (var i = 0; i < 250; i++)
          _Counted(drawn, bounds: Rect.fromLTWH(i * 10.0 - 1250, 0, 4, 4)),
      ];
      for (final r in all) {
        rendering.addRenderable(r);
      }
    });

    test('one without bounds is always drawn', () {
      final unbounded = _Counted(drawn);
      rendering.addRenderable(unbounded);
      frame();
      expect(rendering.stats['usedSpatialIndex'], isTrue);
      expect(drawn, contains(unbounded), reason: 'the tree dropped it');
    });

    test('while things move the tree is not rebuilt, and culling holds', () {
      frame();
      final rebuilds = rendering.stats['spatialRebuilds'] as int;
      for (var f = 0; f < 5; f++) {
        for (final r in all) {
          r.bounds = r.bounds!.shift(const Offset(1, 0));
        }
        drawn.clear();
        frame();
        expect(rendering.stats['usedSpatialIndex'], isFalse);
        final visible = rendering.camera.getVisibleBounds();
        expect(drawn.toSet(), {
          for (final r in all)
            if (visible.overlaps(r.bounds!)) r,
        });
      }
      expect(rendering.stats['spatialRebuilds'], rebuilds);

      // Still again: the tree comes back.
      frame();
      expect(rendering.stats['usedSpatialIndex'], isTrue);
      expect(rendering.stats['spatialRebuilds'], rebuilds + 1);
    });
  });

  test('text laid out for its bounds keeps its faded colour', () async {
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

    final text = make('Hi');
    await pixels(text);
    text.text = 'Hello';
    text.getBounds();
    final after = await pixels(text);

    final fresh = await pixels(make('Hello'));
    expect(after.any((b) => b != 0), isTrue);
    expect(
      after,
      fresh,
      reason: 'bounds used to lay it out at full opacity and mark it current',
    );
  });

  group('world-space bounds', () {
    test('every built-in renderable but the custom one says so', () {
      for (final r in <Renderable>[
        RectangleRenderable(size: const Size(4, 4), fillColor: Colors.red),
        CircleRenderable(radius: 2, fillColor: Colors.red),
        LineRenderable(endPoint: const Offset(3, 0), color: Colors.red),
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

    test('a synced plain rectangle on screen is not culled', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final camera = Camera(position: Offset.zero, zoom: 1.0)
        ..viewportSize = const Size(800, 600);
      world
        ..addSystem(ViewCullingSystem(camera: camera))
        ..addSystem(RenderSystem(passes: []));
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3.fromXY(300, 0)),
        CullStateComponent(),
        RenderableComponent(
          renderable: RectangleRenderable(
            size: const Size(10, 10),
            fillColor: Colors.red,
          ),
        ),
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
}
