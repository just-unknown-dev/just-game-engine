// Particles over time and on the canvas: emission held back by the cap is
// dropped rather than saved up, a burst shorter than the first frame still
// bursts, an emitter is complete only once its sub-emitters are, and
// circles take their colour as a number — or draw all at once, batched.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

ParticleEmitter _emitter({
  int maxParticles = 10,
  double emissionRate = 100,
  double lifetime = 10,
  double? duration,
  List<SubEmitterConfig> subEmitters = const [],
  ParticleRenderer? renderer,
}) => ParticleEmitter(
  maxParticles: maxParticles,
  emissionRate: emissionRate,
  particleLifetime: lifetime,
  lifetimeVariation: 0,
  duration: duration,
  subEmitters: subEmitters,
  renderer: renderer,
  forces: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('emission', () {
    test('what the cap holds back is dropped, not poured out later', () {
      final emitter = _emitter(maxParticles: 10, emissionRate: 100, lifetime: 0.5);
      // Ten seconds at the cap: a thousand particles' worth held back.
      for (var i = 0; i < 100; i++) {
        emitter.update(0.1);
      }
      emitter.emissionRate = 0;
      // Every particle dies; none come back.
      for (var i = 0; i < 20; i++) {
        emitter.update(0.1);
      }
      expect(emitter.particleCount, 0);
    });

    test('a burst shorter than the first frame still bursts', () {
      final dust = ParticleEffects.dustKick(position: Vector3.zero());
      dust.update(0.05);
      expect(dust.particleCount, 25);
      expect(dust.isEmitting, isFalse);

      // Only the part of a frame inside the duration emits.
      final short = _emitter(maxParticles: 100, emissionRate: 100, duration: 0.05);
      short.update(0.5);
      expect(short.particleCount, 5);
    });
  });

  test('an emitter is complete only once its sub-emitters are', () {
    final emitter = _emitter(
      maxParticles: 1,
      emissionRate: 0,
      lifetime: 0.05,
      duration: 0.01,
      subEmitters: [
        SubEmitterConfig(
          trigger: SubEmitterTrigger.onDeath,
          factory: (position) => _emitter(maxParticles: 5, emissionRate: 0, lifetime: 0.2, duration: 0.01)..burst(5),
        ),
      ],
    )..burst(1);
    emitter.update(0.1); // the shell dies, its sparks fly
    expect(emitter.particleCount, 0);
    expect(emitter.isComplete, isFalse, reason: 'the sparks are still alive');
    for (var i = 0; i < 5; i++) {
      emitter.update(0.1);
    }
    expect(emitter.isComplete, isTrue);
  });

  group('circles', () {
    Particle particle(double age) => Particle(
      position: const Offset(4, 4),
      velocity: Offset.zero,
      lifetime: 2,
      startSize: 4,
      endSize: 4,
      startColor: const Color(0xFF2040C0),
      endColor: const Color(0x10F08010),
    )..age = age;

    test('take their colour as a number: the lerped colour', () {
      final renderer = CircleParticleRenderer();
      for (final age in const [0.0, 0.3, 1.0, 1.7]) {
        final p = particle(age);
        final canvas = TestRecordingCanvas();
        renderer.render(canvas, p);
        final paint = canvas.invocations.single.invocation.positionalArguments[2] as Paint;
        expect(paint.color.toARGB32(), p.currentColor.toARGB32());
      }
    });

    test('batched, every particle is one atlas draw', () {
      final renderer = CircleParticleRenderer(batched: true);
      addTearDown(renderer.dispose);
      final particles = [for (var i = 0; i < 6; i++) particle(i * 0.3)];
      final canvas = TestRecordingCanvas();
      renderer.renderBatch(canvas, particles);
      final call = canvas.invocations.single.invocation;
      expect(call.memberName, #drawRawAtlas);
      final colors = call.positionalArguments[3] as Int32List;
      expect([for (final c in colors) c & 0xFFFFFFFF], [for (final p in particles) p.currentColorArgb]);
      final transforms = call.positionalArguments[1] as Float32List;
      // A 64-pixel disc scaled to the particle's size, centred on it.
      expect(transforms.sublist(0, 4), [4 / 64, 0, 2, 2]);
    });

    test('batched circles draw where unbatched ones do', () async {
      Future<Uint8List> pixels(void Function(Canvas) draw) async {
        final recorder = ui.PictureRecorder();
        draw(Canvas(recorder));
        final picture = recorder.endRecording();
        final out = await picture.toImage(16, 16);
        final data = await out.toByteData();
        picture.dispose();
        out.dispose();
        return data!.buffer.asUint8List();
      }

      final p = Particle(
        position: const Offset(8, 8),
        velocity: Offset.zero,
        lifetime: 1,
        startSize: 10,
        endSize: 10,
        startColor: Colors.white,
        endColor: Colors.white,
      );
      final batched = CircleParticleRenderer(batched: true);
      addTearDown(batched.dispose);
      final a = await pixels((c) => CircleParticleRenderer().render(c, p));
      final b = await pixels((c) => batched.renderBatch(c, [p]));
      // The centre is lit and the corners are not, either way.
      int alpha(Uint8List px, int x, int y) => px[(y * 16 + x) * 4 + 3];
      for (final px in [a, b]) {
        expect(alpha(px, 8, 8), 255);
        expect(alpha(px, 0, 0), 0);
      }
    });
  });
}
