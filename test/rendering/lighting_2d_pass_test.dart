// Lighting2DPass: lights drawn where the render system draws what they are
// on (between two fixed steps), and what a lit frame held let go of while
// lighting is off.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Lighting2DPass pass;
  late RenderSystem render;

  setUp(() async {
    engine = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.all),
    );
    await engine.initialize();
    engine.rendering
      ..pixelRatio = 1
      ..overlayHooks.add(engine.world.render);
    engine.rendering.camera.position = const Offset(20, 15);
    final library = engine.context.material2DLibrary;
    for (var i = 0; i < 300; i++) {
      if (library.lightingProgram != null &&
          library.normalsProgram != null &&
          library.shadowsProgram != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(library.lightingProgram, isNotNull);
    pass = engine.rendering.screenPasses.whereType<Lighting2DPass>().single;
    render = engine.world.getSystem<RenderSystem>()!;
  });
  tearDown(() => engine.dispose());

  void frame() {
    final recorder = ui.PictureRecorder();
    engine.rendering.render(Canvas(recorder), const Size(40, 30));
    recorder.endRecording().dispose();
  }

  Lighting2DComponent lighting() {
    final on = Lighting2DComponent(ambient: const Color(0xFF000000));
    engine.world.createEntityWithComponents([on]);
    return on;
  }

  Entity light(Offset at) => engine.world.createEntityWithComponents([
    TransformComponent(position: Vector3(at.dx, at.dy, 0)),
    Light2DComponent(color: const Color(0xFFFF0000), radius: 30),
  ]);

  group('a light on something a fixed step moved', () {
    test('is drawn between its last two poses, as its body is', () {
      lighting();
      final l = light(const Offset(10, 15));
      frame();
      expect(pass.debugLightPositions, [const Offset(10, 15)]);

      // Captured in an update, as a physics step does, then moved.
      l.getComponent<TransformComponent>()!
        ..capturePrevious()
        ..position.setValues(30, 15, 0);
      engine.world.update(1 / 60);
      render.interpolation = 0.5;
      frame();
      expect(pass.debugLightPositions, [
        const Offset(20, 15),
      ], reason: 'it used to be drawn a step ahead of what it is on');

      // An update that captures nothing: where it is.
      engine.world.update(1 / 60);
      frame();
      expect(pass.debugLightPositions, [const Offset(30, 15)]);
    });

    test('moved by gameplay, with no capture, is drawn where it is', () {
      lighting();
      final l = light(const Offset(10, 15));
      frame();
      l.getComponent<TransformComponent>()!.position.setValues(30, 15, 0);
      engine.world.update(1 / 60);
      render.interpolation = 0.5;
      frame();
      expect(pass.debugLightPositions, [const Offset(30, 15)]);
    });
  });

  test(
    'switched off, it lets go of the lit frames within two frames',
    () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final picture = recorder.endRecording();
      final wall = await picture.toImage(8, 8);
      picture.dispose();
      addTearDown(wall.dispose);
      final on = lighting();
      light(const Offset(20, 15));
      // Something casting shadows: the frame's mask and shadow map are made.
      engine.world.createEntityWithComponents([
        TransformComponent(position: Vector3(28, 15, 0)),
        RenderableComponent(renderable: Sprite(image: wall)),
        ShadowCaster2DComponent(),
      ]);
      frame();
      frame();
      expect(pass.debugImageCount, greaterThan(0));
      expect(pass.lastLights, hasLength(1));

      on.enabled = false;
      frame();
      frame();
      expect(
        pass.debugImageCount,
        0,
        reason: 'the images were kept for as long as lighting stayed off',
      );
      expect(pass.lastLights, isEmpty);

      // And it lights again when switched back on.
      on.enabled = true;
      frame();
      expect(pass.lastLights, hasLength(1));
    },
  );
}
