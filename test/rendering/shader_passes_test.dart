// Shaders: post-process passes that follow their components, and effects
// that are skipped — not thrown on — where shaders cannot filter layers.
//
// The test runner draws with Skia, where `ImageFilter.shader` throws, just
// as on the web: exactly the case being guarded. The shader used is the
// ink sparkle every Flutter app bundles.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Logged extends Renderable {
  _Logged(this.log);
  final List<String> log;
  @override
  void render(Canvas canvas, Size size) => log.add('drawn');
  @override
  Rect? getBounds() => const Rect.fromLTWH(0, 0, 10, 10);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.FragmentProgram program;
  setUpAll(() async {
    program = await ui.FragmentProgram.fromAsset('shaders/ink_sparkle.frag');
  });
  tearDown(ShaderFilterSupport.debugReset);

  group('ShaderFilterSupport', () {
    test('asks the platform unless told, and logs a skip once', () {
      expect(
        ShaderFilterSupport.isSupported,
        ui.ImageFilter.isShaderFilterSupported,
      );
      final lines = <String?>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message);
      addTearDown(() => debugPrint = saved);

      ShaderFilterSupport.debugSupportedOverride = false;
      expect(ShaderFilterSupport.check('An effect'), isFalse);
      expect(ShaderFilterSupport.check('An effect'), isFalse);
      expect(ShaderFilterSupport.check('Another'), isFalse);
      expect(lines, hasLength(2));
      expect(lines.first, startsWith('An effect skipped'));

      ShaderFilterSupport.debugSupportedOverride = true;
      expect(ShaderFilterSupport.check('An effect'), isTrue);
      expect(lines, hasLength(2));
    });
  });

  group('where shaders cannot filter layers', () {
    setUp(() => ShaderFilterSupport.debugSupportedOverride = false);

    test('an entity with a ShaderComponent is drawn without it', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(RenderSystem(passes: const []));
      final log = <String>[];
      world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Logged(log)),
        ShaderComponent(program: program),
      ]);
      for (var i = 0; i < 3; i++) {
        world.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
      }
      expect(log, ['drawn', 'drawn', 'drawn'], reason: 'it used to throw');
    });

    test('post-process passes are skipped, the scene drawn', () {
      final rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(100, 100));
      rendering.initialize();
      final log = <String>[];
      rendering
        ..addRenderable(_Logged(log))
        ..addPostProcessPass(PostProcessPass(shader: program.fragmentShader()));
      rendering.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
      expect(log, ['drawn']);
    });

    test("a particle emitter's shader is skipped, its particles drawn", () {
      final emitter = ParticleEmitter(
        maxParticles: 3,
        emissionRate: 0,
        shader: program.fragmentShader(),
      )..burst(3);
      final canvas = TestRecordingCanvas();
      emitter.render(canvas, Size.zero);
      final calls = [
        for (final i in canvas.invocations) i.invocation.memberName,
      ];
      expect(calls.where((c) => c == #drawCircle), hasLength(3));
      expect(calls, isNot(contains(#saveLayer)));
    });
  });

  group('PostProcessSystem', () {
    late World world;
    late RenderingEngine rendering;

    setUp(() {
      rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(100, 100));
      rendering.initialize();
      world = World()..initialize();
      world.addSystem(PostProcessSystem(rendering));
    });
    tearDown(() => world.dispose());

    ShaderComponent pass({int order = 0}) => ShaderComponent(
      program: program,
      isPostProcess: true,
      passOrder: order,
    );

    test('a replaced component gets a new pass, with its live shader', () {
      final entity = world.createEntityWithComponents([pass()]);
      world.update(0);
      final first = rendering.postProcessPasses.single;

      entity.removeComponent<ShaderComponent>();
      final replacement = pass();
      entity.addComponent(replacement);
      world.update(0);

      final now = rendering.postProcessPasses.single;
      expect(identical(now.shader, replacement.shader), isTrue);
      expect(now.shader.debugDisposed, isFalse);
      expect(first.shader.debugDisposed, isTrue);
    });

    test('a removed component takes its pass with it', () {
      final entity = world.createEntityWithComponents([pass()]);
      world.update(0);
      expect(rendering.postProcessPasses, hasLength(1));
      entity.removeComponent<ShaderComponent>();
      world.update(0);
      expect(rendering.postProcessPasses, isEmpty);
    });

    test('a changed pass order re-sorts the passes', () {
      final a = pass(order: 0);
      final b = pass(order: 1);
      world
        ..createEntityWithComponents([a])
        ..createEntityWithComponents([b]);
      world.update(0);
      expect(rendering.postProcessPasses.map((p) => p.shader), [
        a.shader,
        b.shader,
      ]);
      a.passOrder = 5;
      world.update(0);
      expect(rendering.postProcessPasses.map((p) => p.shader), [
        b.shader,
        a.shader,
      ]);
    });
  });

  test('a ShaderComponent taken off and put back has a live shader', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final component = ShaderComponent(program: program);
    final entity = world.createEntityWithComponents([component]);
    expect(component.shader.debugDisposed, isFalse);
    entity.removeComponent<ShaderComponent>();
    entity.addComponent(component);
    expect(component.shader.debugDisposed, isFalse);
  });
}
