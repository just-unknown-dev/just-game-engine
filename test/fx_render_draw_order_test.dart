// The render system's draw list: its order, and keeping it between frames.
//
// Layer and zOrder used to be packed into one number with `layer << 20`. On
// the web `<<` gives an unsigned 32-bit result, so every negative layer —
// the template's backgrounds are at -200 — sorted after all the others and
// drew on top. The list was also rebuilt, looked up and sorted from scratch
// every frame; it is now kept, and rebuilt only when the world changes.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Logged extends Renderable {
  _Logged(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  void render(Canvas canvas, Size size) => log.add(name);

  @override
  Rect? getBounds() => null;
}

class _Item extends RenderItem {
  _Item(this.name, this.log, this.layer);
  final String name;
  final List<String> log;
  @override
  int layer;

  @override
  void render(Canvas canvas, RenderContext context, Entity owner) =>
      log.add(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Entity drawn(String name, {int? layer, int zOrder = 0}) =>
      world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Logged(name, log)),
        if (layer != null) LayerComponent(layer: layer, zOrder: zOrder),
      ]);

  group('negative layers', () {
    test('sort below the others, zOrder within each', () {
      drawn('five', layer: 5);
      drawn('zero-b', layer: 0, zOrder: 2);
      drawn('minus-one', layer: -1, zOrder: 900000);
      drawn('background', layer: LevelLayers.background, zOrder: 3);
      drawn('zero-a', layer: 0, zOrder: -7);
      drawn('background-back', layer: LevelLayers.background, zOrder: -3);

      expect(frame(), [
        'background-back',
        'background',
        'minus-one',
        'zero-a',
        'zero-b',
        'five',
      ]);
    });

    test('a render item at a negative layer sorts the same way', () {
      drawn('player', layer: 0);
      world.createEntityWithComponents([
        TransformComponent(),
        RenderItemsComponent([
          _Item('far', log, LevelLayers.background),
          _Item('near', log, LevelLayers.backgroundNear),
          _Item('front', log, LevelLayers.foreground),
        ]),
      ]);
      expect(frame(), ['far', 'near', 'player', 'front']);
    });

    test('the key is not packed with a shift', () {
      // Whatever sorts has to agree with the web, where `-200 << 20` is
      // 4085252096. The source must not rely on shifting the layer.
      final source = File(
        'lib/src/ecs/systems/rendering/render_system.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('layer << 20')));
      expect(source, isNot(contains('.layer <<')));
      expect(-200 << 20 < 0, isTrue, reason: 'on the VM the shift is signed');
    });
  });

  group('the list is kept between frames', () {
    test('a changed layer re-sorts it', () {
      final a = drawn('a', layer: 0);
      drawn('b', layer: 1);
      expect(frame(), ['a', 'b']);
      a.getComponent<LayerComponent>()!.layer = 2;
      expect(frame(), ['b', 'a']);
      a.getComponent<LayerComponent>()!
        ..layer = 1
        ..zOrder = -1;
      expect(frame(), ['a', 'b']);
    });

    test('ties keep the order the entities were found in, frame after '
        'frame', () {
      for (var i = 0; i < 40; i++) {
        drawn('e$i', layer: i.isEven ? 1 : 0);
      }
      final first = frame();
      for (var i = 0; i < 3; i++) {
        expect(frame(), first);
      }
      expect(first.take(20), [for (var i = 1; i < 40; i += 2) 'e$i']);
    });

    test('an entity created, destroyed or switched off is seen', () {
      drawn('a');
      expect(frame(), ['a']);
      final b = drawn('b');
      expect(frame(), ['a', 'b']);
      b.isActive = false;
      expect(frame(), ['a']);
      b.isActive = true;
      expect(frame(), ['a', 'b']);
      world.destroyEntity(b);
      expect(frame(), ['a']);
    });

    test('render items replaced in place — same count — are seen', () {
      final items = RenderItemsComponent([_Item('old', log, 0)]);
      world.createEntityWithComponents([TransformComponent(), items]);
      expect(frame(), ['old']);
      items.items
        ..clear()
        ..add(_Item('new', log, 0));
      expect(frame(), ['new']);
      items.items.add(_Item('more', log, -1));
      expect(frame(), ['more', 'new']);
    });

    test('a render item whose layer changes moves', () {
      final back = _Item('back', log, 0);
      world.createEntityWithComponents([
        TransformComponent(),
        RenderItemsComponent([back, _Item('mid', log, 1)]),
      ]);
      expect(frame(), ['back', 'mid']);
      back.layer = 2;
      expect(frame(), ['mid', 'back']);
    });
  });

  group('each frame', () {
    test('the transform is synced; interpolated only when its previous '
        'pose was captured in the last update', () {
      final sprite = _Logged('s', log);
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 20, 0), angle: 0.5),
        RenderableComponent(renderable: sprite),
      ]);
      render.interpolation = 0.0;
      frame();
      expect(sprite.position, Vector3(10, 20, 0));
      expect(sprite.rotation, 0.5);

      // A previous pose left behind, never captured: drawn where it is.
      final t = entity.getComponent<TransformComponent>()!
        ..prevPosition.setValues(0, 0, 0)
        ..position.setValues(100, 0, 0);
      render.interpolation = 0.25;
      world.update(1 / 60);
      frame();
      expect(sprite.position.x, 100);

      // Captured in an update, as a physics step does: drawn between.
      t
        ..position.setValues(0, 0, 0)
        ..capturePrevious()
        ..position.setValues(100, 0, 0);
      world.update(1 / 60);
      frame();
      expect(sprite.position.x, closeTo(25, 1e-9));
      expect(t.position.x, 100);

      // An update that captures nothing: where it is again.
      world.update(1 / 60);
      frame();
      expect(sprite.position.x, 100);
    });

    test('a particle emitter on an entity is drawn, in layer order', () {
      final emitter = ParticleEmitter(
        maxParticles: 4,
        emissionRate: 0,
        startColor: const Color(0xFFFF0000),
        endColor: const Color(0xFFFF0000),
      );
      final recorder = _CallCounter(log);
      drawn('front', layer: 5);
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(40, 40, 0)),
        ParticleEmitterComponent(emitter: emitter),
        LayerComponent(layer: 1),
      ]);
      world.addSystem(ParticleSystemECS());
      world.update(0);
      emitter.burst(3);

      world.render(recorder, const Size(800, 600));
      expect(
        recorder.circles,
        3,
        reason: 'the ECS emitter used to be updated but never drawn',
      );
      expect(log, [
        'circle',
        'circle',
        'circle',
        'front',
      ], reason: 'layer 1 draws before layer 5');
    });

    test('an emitter already shown as the renderable is drawn once', () {
      final emitter = ParticleEmitter(maxParticles: 2, emissionRate: 0);
      world.createEntityWithComponents([
        TransformComponent(),
        ParticleEmitterComponent(emitter: emitter),
        RenderableComponent(renderable: emitter),
      ]);
      emitter.burst(2);
      final recorder = _CallCounter(log);
      world.render(recorder, const Size(800, 600));
      expect(recorder.circles, 2);
    });

    test('the emitter takes a copy of the transform position', () {
      final emitter = ParticleEmitter(maxParticles: 2, emissionRate: 0);
      world.addSystem(ParticleSystemECS());
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(5, 6, 0)),
        ParticleEmitterComponent(emitter: emitter),
      ]);
      world.update(0);
      final transform = entity.getComponent<TransformComponent>()!;
      expect(identical(emitter.position, transform.position), isFalse);
      emitter.position.x = 99;
      expect(
        transform.position.x,
        5,
        reason:
            'moving the emitter left the '
            'entity where it was',
      );
    });
  });
}

/// Counts circles, and logs each as 'circle'.
class _CallCounter extends TestRecordingCanvas {
  _CallCounter(this.log);
  final List<String> log;
  int circles = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles++;
    log.add('circle');
    super.drawCircle(c, radius, paint);
  }
}
