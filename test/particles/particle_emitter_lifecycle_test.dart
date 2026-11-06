// An emitter's life: one that only bursts finishes once its particles are
// gone, its bounds cover its sub-emitters' particles, its opacity and tint
// reach the canvas, and the images its renderer made are released when
// it goes.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts how often it is told to release what it holds.
class _DisposeCounter extends ParticleRenderer {
  int disposed = 0;

  @override
  void render(Canvas canvas, Particle particle) {}

  @override
  void dispose() => disposed++;
}

ParticleEmitter _burstOnly({
  double lifetime = 0.1,
  ParticleRenderer? renderer,
  List<SubEmitterConfig> subEmitters = const [],
  bool ownsRenderer = true,
}) => ParticleEmitter(
  maxParticles: 5,
  emissionRate: 0,
  particleLifetime: lifetime,
  lifetimeVariation: 0,
  speed: 0,
  speedVariation: 0,
  forces: const [],
  renderer: renderer,
  ownsRenderer: ownsRenderer,
  subEmitters: subEmitters,
);

Future<Uint8List> _pixels(ParticleEmitter emitter) async {
  final recorder = ui.PictureRecorder();
  emitter.render(Canvas(recorder), const Size(16, 16));
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The RGBA of pixel ([x], [y]) of a 16-wide image.
List<int> _at(Uint8List rgba, int x, int y) {
  final i = (y * 16 + x) * 4;
  return rgba.sublist(i, i + 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an emitter that only bursts', () {
    test('is complete once its particles are gone', () {
      final emitter = _burstOnly()..burst(5);
      expect(emitter.isComplete, isFalse);
      emitter.update(0.2);
      expect(emitter.particleCount, 0);
      expect(emitter.isComplete, isTrue, reason: 'it emitted forever');
    });

    test('is removed with its entity once done', () {
      final world = World()..addSystem(ParticleSystem());
      addTearDown(world.dispose);
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        ParticleEmitterComponent(
          emitter: _burstOnly()..burst(3),
          removeEntityWhenComplete: true,
        ),
      ]);
      for (var i = 0; i < 20; i++) {
        world.update(0.016);
      }
      expect(world.isEntityAlive(entity), isFalse);
    });

    test('as a sub-emitter, lets its parent finish', () {
      final parent = _burstOnly(
        lifetime: 0.05,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (_) => _burstOnly(lifetime: 0.1)..burst(3),
          ),
        ],
      )..burst(2);
      for (var i = 0; i < 20; i++) {
        parent.update(0.016);
      }
      expect(parent.isComplete, isTrue);
    });
  });

  group('bounds', () {
    test('cover the sub-emitters\' particles, once its own are gone', () {
      final parent = _burstOnly(
        lifetime: 0.05,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (at) => ParticleEmitter(
              maxParticles: 1,
              emissionRate: 0,
              particleLifetime: 10,
              lifetimeVariation: 0,
              startSize: 4,
              sizeVariation: 0,
              speed: 0,
              speedVariation: 0,
              forces: const [],
              position: Vector3(at.dx + 100, at.dy, 0),
            )..burst(1),
          ),
        ],
      );
      parent.position.setValues(10, 10, 0);
      parent
        ..burst(1)
        ..update(0.1);
      expect(parent.particleCount, 0);
      final bounds = parent.bounds;
      expect(bounds, isNotNull, reason: 'only its own particles counted');
      expect(bounds!.contains(const Offset(110, 10)), isTrue);
    });

    test('hold the own and the sub-emitters\' particles together', () {
      final parent = _burstOnly(
        lifetime: 1,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onLifetimeFraction,
            lifetimeFraction: 0,
            factory: (at) => ParticleEmitter(
              maxParticles: 1,
              emissionRate: 0,
              particleLifetime: 10,
              lifetimeVariation: 0,
              speed: 0,
              speedVariation: 0,
              forces: const [],
              position: Vector3(at.dx + 200, at.dy + 50, 0),
            )..burst(1),
          ),
        ],
      )..burst(1);
      parent.update(0.01);
      final bounds = parent.bounds!;
      expect(bounds.contains(Offset.zero), isTrue);
      expect(bounds.contains(const Offset(200, 50)), isTrue);
    });
  });

  group('opacity and tint', () {
    ParticleEmitter whiteDot() => ParticleEmitter(
      maxParticles: 1,
      emissionRate: 0,
      startSize: 8,
      endSize: 8,
      sizeVariation: 0,
      startColor: Colors.white,
      endColor: Colors.white,
      speed: 0,
      speedVariation: 0,
      forces: const [],
      position: Vector3(8, 8, 0),
    )..burst(1);

    test('the defaults draw with no layer', () {
      final canvas = TestRecordingCanvas();
      whiteDot().render(canvas, Size.zero);
      expect(
        canvas.invocations.map((i) => i.invocation.memberName),
        isNot(contains(#saveLayer)),
      );
    });

    test('opacity fades every particle', () async {
      final emitter = whiteDot()..opacity = 0.5;
      final centre = _at(await _pixels(emitter), 8, 8);
      expect(centre[3], inInclusiveRange(120, 135));
    });

    test('a tint colours every particle', () async {
      final emitter = whiteDot()..tint = const Color(0xFFFF0000);
      final centre = _at(await _pixels(emitter), 8, 8);
      expect(centre, [255, 0, 0, 255]);
    });
  });

  group('disposing', () {
    test('removing its component releases the renderer', () {
      final world = World()..addSystem(ParticleSystem());
      addTearDown(world.dispose);
      final renderer = _DisposeCounter();
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        ParticleEmitterComponent(emitter: _burstOnly(renderer: renderer)),
      ]);
      world.update(0.016);
      expect(renderer.disposed, 0);
      entity.removeComponent<ParticleEmitterComponent>();
      expect(renderer.disposed, 1);
    });

    test('destroying its entity releases the renderer', () {
      final world = World()..addSystem(ParticleSystem());
      addTearDown(world.dispose);
      final renderer = _DisposeCounter();
      final entity = world.createEntityWithComponents([
        ParticleEmitterComponent(emitter: _burstOnly(renderer: renderer)),
      ]);
      world.destroyEntity(entity);
      expect(renderer.disposed, 1);
    });

    test('a renderer it does not own is left alone', () {
      final renderer = _DisposeCounter();
      _burstOnly(renderer: renderer, ownsRenderer: false).dispose();
      expect(renderer.disposed, 0);
    });

    test('a finished sub-emitter releases its renderer', () {
      final renderers = <_DisposeCounter>[];
      final parent = _burstOnly(
        lifetime: 0.05,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (_) {
              final r = _DisposeCounter();
              renderers.add(r);
              return _burstOnly(lifetime: 0.15, renderer: r)..burst(1);
            },
          ),
        ],
      )..burst(2);
      // The parent's particles die: two children, a frame into their 0.15 s.
      parent.update(0.1);
      expect(renderers, hasLength(2));
      expect(renderers.map((r) => r.disposed), [0, 0]);
      parent.update(0.1); // the children's die: they are done
      expect(renderers.map((r) => r.disposed), [1, 1]);
    });

    test('dispose releases running sub-emitters\' renderers too', () {
      final child = _DisposeCounter();
      final parent = _burstOnly(
        lifetime: 0.05,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onDeath,
            factory: (_) => _burstOnly(lifetime: 10, renderer: child)..burst(1),
          ),
        ],
      )..burst(1);
      parent.update(0.1);
      parent.dispose();
      expect(child.disposed, 1);
    });

    test('a batched circle renderer draws again after being released', () {
      final renderer = CircleParticleRenderer(batched: true);
      final emitter = _burstOnly(renderer: renderer)..burst(2);
      final first = TestRecordingCanvas();
      emitter.render(first, Size.zero);
      final disc =
          first.invocations.single.invocation.positionalArguments[0]
              as ui.Image;
      emitter.dispose();
      expect(disc.debugDisposed, isTrue);
      final again = TestRecordingCanvas();
      emitter.render(again, Size.zero);
      final remade =
          again.invocations.single.invocation.positionalArguments[0]
              as ui.Image;
      expect(remade.debugDisposed, isFalse);
      emitter.dispose();
    });
  });
}
