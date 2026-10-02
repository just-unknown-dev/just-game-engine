// Particles: the same noise everywhere, sub-emitters that fire, and
// renderers that draw without making objects per particle.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The 32-bit hash, computed with exact arithmetic — what every platform
/// must agree with.
int _reference32(int x) {
  final mask = BigInt.from(0xFFFFFFFF);
  final k = BigInt.from(0x45d9f3b);
  var v = BigInt.from(x) & mask;
  v = (((v >> 16) ^ v) * k) & mask;
  v = (((v >> 16) ^ v) * k) & mask;
  return (((v >> 16) ^ v) & mask).toInt();
}

double _referenceHash3(int x, int y, int t) {
  final mask = BigInt.from(0xFFFFFFFF);
  final v =
      (BigInt.from(x) & mask) ^
      ((BigInt.from(y) * BigInt.from(57)) & mask) ^
      ((BigInt.from(t) * BigInt.from(131)) & mask);
  return (_reference32(v.toInt()) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

Particle _particle({Offset position = Offset.zero}) => Particle(
  position: position,
  velocity: Offset.zero,
  lifetime: 1,
  startSize: 4,
  endSize: 4,
  startColor: Colors.white,
  endColor: Colors.white,
);

/// An image with something in it: [createTestImage]'s are transparent.
Future<ui.Image> _patterned(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()
          ..color = Color.fromARGB(
            255 - 20 * ((x + y) % 4),
            40 * x % 256,
            60 * y % 256,
            (x * y * 30) % 256,
          ),
      );
    }
  }
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

class _Nudge extends ParticleForce {
  // A force of the old kind, written against the offsets.
  @override
  void apply(Particle particle, double dt) {
    particle.velocity = Offset(particle.velocity.dx + 10, particle.velocity.dy);
  }
}

class _CountingBounds extends ParticleEmitter {
  _CountingBounds() : super(maxParticles: 4, emissionRate: 0);
  int boundsAsked = 0;

  @override
  Rect? getBounds() {
    boundsAsked++;
    return super.getBounds();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('noise', () {
    test('hashes as 32-bit arithmetic does, for any lattice point', () {
      const points = [
        (0, 0, 0),
        (-3, 7, 11),
        (123456, -654321, 99),
        (0x7FFFFFFF, -0x80000000, 1 << 40),
        (-987654321, 55555, -3),
      ];
      for (final (x, y, t) in points) {
        expect(NoiseForce.hash3(x, y, t), _referenceHash3(x, y, t));
      }
      for (final n in const [-1, 0, 70000, 0x7FFFFFFF, -123456789]) {
        expect(
          WindForce.hash1D(n),
          (_reference32(n) & 0x7FFFFFFF) / 0x7FFFFFFF,
        );
      }
    });

    test('pushes particles the same on every platform', () {
      // Pinned: native ints used to wrap at 64 bits and the web's lost bits
      // past 2^53, so these came out different on the web.
      const pinned = [
        (Offset(-37.5, 12.25), 4.36110406773765913, -0.184875966704124428),
        (Offset(1234.5, -987.25), -1.37726763732947788, -2.25467137686565477),
        (Offset(0.5, 0.5), 3.85961048786243843, -4.52672950974144506),
      ];
      for (final (position, vx, vy) in pinned) {
        final p = _particle(position: position);
        // A frame: the force's clock moves on, then it pushes the particle.
        NoiseForce(strength: 100, scale: 0.05, speed: 0.5)
          ..advance(0.1)
          ..apply(p, 0.1);
        expect(p.vx, closeTo(vx, 1e-12));
        expect(p.vy, closeTo(vy, 1e-12));
      }
      final p = _particle();
      final wind = WindForce(turbulence: 40, frequency: 3.7);
      for (var i = 0; i < 5; i++) {
        wind
          ..advance(0.25)
          ..apply(p, 0.25);
      }
      expect(p.vx, closeTo(62.5, 1e-12));
      expect(p.vy, closeTo(4.23941575262391801, 1e-12));
    });
  });

  group('Particle', () {
    test('numbers and offsets are one position', () {
      final p = _particle(position: const Offset(1, 2))
        ..velocity = const Offset(3, 4);
      expect((p.x, p.y, p.vx, p.vy), (1.0, 2.0, 3.0, 4.0));
      p.update(0.5, [_Nudge()]);
      expect(p.previousPosition, const Offset(1, 2));
      expect(p.velocity, const Offset(13, 4));
      expect(p.position, const Offset(7.5, 4));
    });

    test('its colour as a number is the lerped colour', () {
      final p = Particle(
        position: Offset.zero,
        velocity: Offset.zero,
        lifetime: 2,
        startSize: 1,
        endSize: 1,
        startColor: const Color(0xFF2040C0),
        endColor: const Color(0x10F08010),
      );
      for (final age in const [0.0, 0.3, 1.0, 1.7, 2.5]) {
        p.age = age;
        expect(p.currentColorArgb, p.currentColor.toARGB32());
      }
    });
  });

  group('lifetime-fraction sub-emitters', () {
    test('fire once for every particle, however the list shifts', () {
      var spawned = 0;
      final emitter = ParticleEmitter(
        maxParticles: 10,
        emissionRate: 0,
        particleLifetime: 1.0,
        lifetimeVariation: 0,
        subEmitters: [
          SubEmitterConfig(
            trigger: SubEmitterTrigger.onLifetimeFraction,
            lifetimeFraction: 0.5,
            factory: (position) {
              spawned++;
              return ParticleEmitter(
                maxParticles: 1,
                emissionRate: 0,
                duration: 0,
              );
            },
          ),
        ],
      );
      emitter
        ..burst(2)
        ..update(0.6);
      expect(spawned, 2);
      emitter.update(0.5); // Both die.
      emitter
        ..burst(2)
        ..update(0.6);
      expect(
        spawned,
        4,
        reason:
            'fired flags were keyed by list index and '
            'never cleared',
      );
    });
  });

  group('rendering', () {
    test('bounds are worked out only for a shader', () {
      final emitter = _CountingBounds()..burst(3);
      emitter.render(TestRecordingCanvas(), Size.zero);
      expect(emitter.boundsAsked, 0);
    });

    test('sprite particles: one raw atlas draw, the same pixels', () async {
      final image = await _patterned(8, 8);
      final particles = [
        for (var i = 0; i < 3; i++)
          Particle(
            position: Offset(8.0 + i * 10, 12),
            velocity: Offset.zero,
            lifetime: 1,
            startSize: 6.0 + i * 3,
            endSize: 2,
            startColor: const Color(0xFFFF8040),
            endColor: const Color(0x2000FF00),
            rotation: i * 0.4,
          )..age = i * 0.3,
      ];
      final renderer = SpriteParticleRenderer(image: image, maxParticles: 8);

      final canvas = TestRecordingCanvas();
      renderer.renderBatch(canvas, particles);
      expect(canvas.invocations.single.invocation.memberName, #drawRawAtlas);

      Future<Uint8List> pixels(void Function(Canvas) draw) async {
        final recorder = ui.PictureRecorder();
        draw(Canvas(recorder));
        final picture = recorder.endRecording();
        final out = await picture.toImage(40, 24);
        final data = await out.toByteData();
        picture.dispose();
        out.dispose();
        return data!.buffer.asUint8List();
      }

      final now = await pixels((c) => renderer.renderBatch(c, particles));
      final before = await pixels((c) {
        c.drawAtlas(
          image,
          [
            for (final p in particles)
              RSTransform.fromComponents(
                rotation: p.rotation,
                scale: p.currentSize / 8,
                anchorX: 4,
                anchorY: 4,
                translateX: p.position.dx,
                translateY: p.position.dy,
              ),
          ],
          [for (final _ in particles) const Rect.fromLTWH(0, 0, 8, 8)],
          [for (final p in particles) p.currentColor],
          BlendMode.modulate,
          null,
          Paint()..filterQuality = FilterQuality.medium,
        );
      });
      expect(now.any((b) => b != 0), isTrue);
      expect(now, before);
    });

    test('text particles: the glyph drawn once, every particle one draw', () {
      final renderer = TextParticleRenderer(glyph: 'A');
      addTearDown(renderer.dispose);
      final particles = [
        for (var i = 0; i < 5; i++) _particle(position: Offset(i * 4.0, 0)),
      ];
      final images = <Object?>{};
      for (var frame = 0; frame < 3; frame++) {
        final canvas = TestRecordingCanvas();
        renderer.renderBatch(canvas, particles);
        final call = canvas.invocations.single.invocation;
        expect(call.memberName, #drawRawAtlas);
        expect((call.positionalArguments[3] as Int32List).length, 5);
        images.add(call.positionalArguments.first);
      }
      expect(images, hasLength(1), reason: 'laid out once, not per particle');
    });
  });
}
