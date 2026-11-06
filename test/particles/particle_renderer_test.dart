// Each particle renderer, drawing one particle onto a recording canvas:
// what it draws, where, and from which frame.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Particle _particle({
  Offset position = const Offset(20, 30),
  double rotation = 0,
  double startSize = 10,
  double endSize = 10,
  double age = 0,
}) => Particle(
  position: position,
  velocity: Offset.zero,
  lifetime: 2,
  startSize: startSize,
  endSize: endSize,
  startColor: const Color(0xFF336699),
  endColor: const Color(0xFF336699),
  rotation: rotation,
)..age = age;

/// What [renderer] asks of the canvas for [particle], by member name.
List<Invocation> _draw(ParticleRenderer renderer, Particle particle) {
  final canvas = TestRecordingCanvas();
  renderer.render(canvas, particle);
  return [for (final i in canvas.invocations) i.invocation];
}

Invocation _only(List<Invocation> calls, Symbol name) =>
    calls.singleWhere((i) => i.memberName == name);

ui.Image _sheet() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 32, 8),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(32, 8);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SquareParticleRenderer', () {
    test('an unturned square is one rect around the particle', () {
      final calls = _draw(SquareParticleRenderer(), _particle());
      expect(calls.map((c) => c.memberName), [#drawRect]);
      expect(
        calls.single.positionalArguments[0],
        const Rect.fromLTRB(15, 25, 25, 35),
      );
      final paint = calls.single.positionalArguments[1] as Paint;
      expect(paint.color.toARGB32(), 0xFF336699);
    });

    test('a turned square is a path, turned about the particle', () {
      final calls = _draw(SquareParticleRenderer(), _particle(rotation: 0.5));
      expect(calls.map((c) => c.memberName), [
        #save,
        #translate,
        #rotate,
        #drawPath,
        #restore,
      ]);
      expect(_only(calls, #translate).positionalArguments, [20.0, 30.0]);
      expect(_only(calls, #rotate).positionalArguments, [0.5]);
      final path = _only(calls, #drawPath).positionalArguments[0] as Path;
      expect(path.getBounds(), const Rect.fromLTRB(-5, -5, 5, 5));
    });
  });

  test('TriangleParticleRenderer draws a triangle pointing up', () {
    final calls = _draw(TriangleParticleRenderer(), _particle(rotation: 0.3));
    expect(_only(calls, #translate).positionalArguments, [20.0, 30.0]);
    expect(_only(calls, #rotate).positionalArguments, [0.3]);
    final path = _only(calls, #drawPath).positionalArguments[0] as Path;
    expect(path.getBounds(), const Rect.fromLTRB(-5, -5, 5, 5));
    expect(path.contains(const Offset(0, -4)), isTrue, reason: 'the apex');
    expect(path.contains(const Offset(0, 4)), isTrue, reason: 'the base');
    expect(path.contains(const Offset(-4.5, -4.5)), isFalse);
    expect(path.contains(const Offset(4.5, -4.5)), isFalse);
  });

  test('StarParticleRenderer draws a five-pointed star', () {
    final calls = _draw(StarParticleRenderer(), _particle());
    expect(_only(calls, #translate).positionalArguments, [20.0, 30.0]);
    final path = _only(calls, #drawPath).positionalArguments[0] as Path;
    // Points at radius 5, the notches between them at 2.5.
    expect(path.getBounds().top, closeTo(-5, 1e-6));
    expect(path.contains(Offset.zero), isTrue);
    expect(path.contains(const Offset(0, -4.5)), isTrue, reason: 'a point');
    const between = -math.pi / 2 + math.pi / 5;
    expect(
      path.contains(Offset(4.5 * math.cos(between), 4.5 * math.sin(between))),
      isFalse,
      reason: 'between two points',
    );
  });

  test('AnimatedSpriteParticleRenderer steps through its frames', () {
    final sheet = _sheet();
    addTearDown(sheet.dispose);
    final frames = [
      for (var i = 0; i < 4; i++) Rect.fromLTWH(i * 8.0, 0, 8, 8),
    ];
    final renderer = AnimatedSpriteParticleRenderer(
      sheet: sheet,
      frames: frames,
    );
    Rect sourceAt(double age) {
      final call = _only(_draw(renderer, _particle(age: age)), #drawImageRect);
      return call.positionalArguments[1] as Rect;
    }

    expect(sourceAt(0), frames[0]);
    expect(sourceAt(1.0), frames[2], reason: 'half its life');
    expect(sourceAt(1.9), frames[3]);
    expect(sourceAt(2.0), frames[3], reason: 'clamped at the end');
    final call = _only(_draw(renderer, _particle(age: 1)), #drawImageRect);
    expect(
      call.positionalArguments[2],
      Rect.fromCenter(center: Offset.zero, width: 10, height: 10),
    );
  });

  test('LineParticleRenderer streaks from where it was to where it is', () {
    final p = _particle(startSize: 4, endSize: 0, age: 1)
      ..previousPosition = const Offset(10, 12);
    final calls = _draw(LineParticleRenderer(strokeWidth: 3), p);
    final line = _only(calls, #drawLine);
    expect(line.positionalArguments[0], const Offset(10, 12));
    expect(line.positionalArguments[1], const Offset(20, 30));
    final paint = line.positionalArguments[2] as Paint;
    expect(paint.strokeWidth, 1.5, reason: 'half its start size, half width');
  });

  test('CustomPathParticleRenderer scales its path by the size', () {
    final path = Path()..addRect(const Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5));
    final calls = _draw(
      CustomPathParticleRenderer(path: path),
      _particle(rotation: 0.2),
    );
    expect(calls.map((c) => c.memberName), [
      #save,
      #translate,
      #rotate,
      #scale,
      #drawPath,
      #restore,
    ]);
    expect(_only(calls, #scale).positionalArguments.first, 10.0);
    expect(_only(calls, #drawPath).positionalArguments[0], same(path));
  });

  test('CircleParticleRenderer draws a circle of half the size', () {
    final calls = _draw(CircleParticleRenderer(), _particle());
    final circle = _only(calls, #drawCircle);
    expect(circle.positionalArguments[0], const Offset(20, 30));
    expect(circle.positionalArguments[1], 5.0);
  });

  test('every renderer can be released, and the base does nothing', () {
    final ParticleRenderer square = SquareParticleRenderer();
    square.dispose();
    expect(_draw(square, _particle()).map((c) => c.memberName), [#drawRect]);
  });
}
