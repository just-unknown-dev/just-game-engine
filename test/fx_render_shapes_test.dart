// The shape components' drawing: kept paints, the same pixels.
//
// Each shape used to build two paints (and a gradient shader, and a
// rounded-rect buffer) every frame, turn and scale the canvas by nothing,
// draw an invisible outline, and fade through an offscreen layer. What it
// draws must not change: every test here compares with the old recipe,
// pixel for pixel.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _size = 64;

Future<Uint8List> _pixels(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size, _size);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The largest difference between two images, per channel.
int _maxDiff(Uint8List a, Uint8List b) {
  var most = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > most) most = d;
  }
  return most;
}

/// How the shapes were drawn before 2.0.0.
abstract final class _OldRecipe {
  static void transformed(Canvas canvas, Renderable r, void Function() draw) {
    canvas
      ..save()
      ..translate(r.position.x, r.position.y)
      ..rotate(r.rotation)
      ..scale(r.scale.x, r.scale.y);
    final layer = r.opacity < 1.0 || r.tint != null;
    if (layer) {
      final t = r.tint;
      canvas.saveLayer(
        null,
        Paint()
          ..colorFilter = ColorFilter.mode(
            t != null
                ? t.withValues(alpha: t.a * r.opacity)
                : Color.fromRGBO(255, 255, 255, r.opacity),
            BlendMode.modulate,
          ),
      );
    }
    draw();
    if (layer) canvas.restore();
    canvas.restore();
  }

  static Paint paint(ShapePaintStyle style, Rect rect, {double? stroke}) {
    final paint = Paint();
    if (stroke != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
    }
    paint
      ..shader = null
      ..colorFilter = null
      ..color = style.color;
    final g = style.gradient;
    if (g != null) {
      paint
        ..shader = g.createShader(rect)
        ..colorFilter = ColorFilter.mode(style.color, style.blendMode);
    }
    return paint;
  }

  static void rect(Canvas canvas, RectangleComponent c) {
    transformed(canvas, c.renderable, () {
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: c.width,
        height: c.height,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(c.cornerRadius),
      );
      if (c.filled) canvas.drawRRect(rrect, paint(c.fillStyle, rect));
      canvas.drawRRect(
        rrect,
        paint(c.strokeStyle, rect, stroke: c.strokeWidth),
      );
    });
  }

  static void circle(Canvas canvas, CircleComponent c) {
    transformed(canvas, c.renderable, () {
      final rect = Rect.fromCircle(center: Offset.zero, radius: c.radius);
      if (c.filled) {
        canvas.drawCircle(Offset.zero, c.radius, paint(c.fillStyle, rect));
      }
      canvas.drawCircle(
        Offset.zero,
        c.radius,
        paint(c.strokeStyle, rect, stroke: c.strokeWidth),
      );
    });
  }

  static void polygon(Canvas canvas, PolygonComponent c) {
    transformed(canvas, c.renderable, () {
      final points = c.vertices;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      final rect = ShapePainting.boundsOf(points);
      if (c.filled) canvas.drawPath(path, paint(c.fillStyle, rect));
      canvas.drawPath(path, paint(c.strokeStyle, rect, stroke: c.strokeWidth));
    });
  }

  static void capsule(Canvas canvas, CapsuleComponent c) {
    transformed(canvas, c.renderable, () {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: c.width, height: c.height),
        Radius.circular(c.capRadius),
      );
      final rect = rrect.outerRect;
      if (c.filled) canvas.drawRRect(rrect, paint(c.fillStyle, rect));
      canvas.drawRRect(
        rrect,
        paint(c.strokeStyle, rect, stroke: c.strokeWidth),
      );
    });
  }

  static void line(Canvas canvas, LineComponent c) {
    transformed(canvas, c.renderable, () {
      final rect = Rect.fromPoints(c.start, c.end).inflate(c.strokeWidth);
      final p = Paint();
      c.strokeStyle.applyTo(p, rect);
      p
        ..strokeWidth = c.strokeWidth
        ..strokeCap = c.roundCaps ? StrokeCap.round : StrokeCap.butt;
      canvas.drawLine(c.start, c.end, p);
    });
  }
}

const _gradient = ShapePaintStyle(
  color: Color(0xFFFFEE88),
  gradient: ShapeGradient.linear(
    colors: [Color(0xFF2266FF), Color(0xFFFF3322)],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() {
    world = World()..initialize();
    world.addSystem(RenderSystem(passes: const []));
  });
  tearDown(() => world.dispose());

  Entity place(
    RenderableComponent shape, {
    double x = 32,
    double y = 32,
    double angle = 0,
    Vector3? scale,
  }) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(x, y, 0), angle: angle, scale: scale),
    shape,
  ]);

  Future<Uint8List> drawn() =>
      _pixels((canvas) => world.render(canvas, const Size(64, 64)));

  Future<void> expectSame(
    RenderableComponent shape,
    void Function(Canvas) old, {
    int tolerance = 0,
  }) async {
    // A frame first, so the renderable holds the entity's transform.
    await drawn();
    final now = await drawn();
    final before = await _pixels(old);
    expect(now.any((b) => b != 0), isTrue, reason: 'something is drawn');
    expect(
      _maxDiff(now, before),
      lessThanOrEqualTo(tolerance),
      reason: '$shape',
    );
  }

  group('the same pixels as before', () {
    test('a plain rectangle, with its default outline', () async {
      final c = RectangleComponent(width: 20, height: 12);
      place(c, x: 30.5, y: 31.25);
      await expectSame(c, (canvas) => _OldRecipe.rect(canvas, c));
    });

    test('a turned, scaled, rounded rectangle with a gradient', () async {
      final c = RectangleComponent(
        width: 24,
        height: 14,
        cornerRadius: 4,
        fillStyle: _gradient,
        strokeWidth: 2,
      );
      place(c, angle: 0.4, scale: Vector3(1.5, 0.75, 1));
      await expectSame(c, (canvas) => _OldRecipe.rect(canvas, c));
    });

    test('a circle whose outline is transparent', () async {
      final c = CircleComponent(
        radius: 13,
        strokeStyle: const ShapePaintStyle(color: Color(0x00FFFFFF)),
      );
      place(c);
      await expectSame(c, (canvas) => _OldRecipe.circle(canvas, c));
    });

    test('an outlined polygon, a capsule and a gradient line', () async {
      final polygon = PolygonComponent(
        vertices: const [Offset(-10, -8), Offset(12, -4), Offset(2, 12)],
        filled: false,
        strokeWidth: 3,
      );
      place(polygon, x: 20, y: 20);
      final capsule = CapsuleComponent(width: 30, height: 10);
      place(capsule, x: 32, y: 44, angle: -0.3);
      final line = LineComponent(
        start: const Offset(-10, 0),
        end: const Offset(14, 6),
        strokeStyle: _gradient,
        strokeWidth: 4,
        roundCaps: true,
      );
      place(line, x: 40, y: 16);
      await expectSame(polygon, (canvas) {
        _OldRecipe.polygon(canvas, polygon);
        _OldRecipe.capsule(canvas, capsule);
        _OldRecipe.line(canvas, line);
      });
    });

    test('faded with an outline: through a layer, as before', () async {
      final c = RectangleComponent(width: 30, height: 20);
      place(c);
      c.renderable.opacity = 0.5;
      await expectSame(c, (canvas) => _OldRecipe.rect(canvas, c));
    });

    test('faded and tinted with one draw: folded into the paint', () async {
      final fill = CircleComponent(
        radius: 12,
        fillStyle: const ShapePaintStyle(color: Color(0xFF66CCFF)),
        strokeStyle: const ShapePaintStyle(color: Color(0x00000000)),
      );
      place(fill, x: 20, y: 20);
      fill.renderable
        ..opacity = 0.6
        ..tint = const Color(0xCCFF8844);
      final line = LineComponent(
        start: const Offset(-12, -6),
        end: const Offset(12, 6),
        strokeWidth: 3,
      );
      place(line, x: 40, y: 44);
      line.renderable.opacity = 0.3;
      // A layer rounds to 8 bits before it multiplies; the paint does not.
      await expectSame(fill, (canvas) {
        _OldRecipe.circle(canvas, fill);
        _OldRecipe.line(canvas, line);
      }, tolerance: 2);
    });

    test('a polygon edited in place is drawn as edited', () async {
      final c = PolygonComponent(
        vertices: [const Offset(-10, -10), const Offset(10, -10), Offset.zero],
      );
      place(c);
      await drawn();
      c.vertices[2] = const Offset(0, 14);
      await expectSame(c, (canvas) => _OldRecipe.polygon(canvas, c));
    });
  });

  group('fewer canvas calls', () {
    test('an unturned, unscaled, opaque rectangle is two plain draws, '
        'placed without the canvas transform', () {
      place(RectangleComponent(width: 10, height: 10), x: 20, y: 30);
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(64, 64));
      final calls = [for (final i in canvas.invocations) i.invocation];
      expect([for (final c in calls) c.memberName], [#drawRect, #drawRect]);
      expect(
        calls.first.positionalArguments.first,
        const Rect.fromLTRB(15, 25, 25, 35),
      );
    });

    test('turned, it is transformed — but not scaled by nothing', () {
      place(
        PolygonComponent(
          vertices: const [Offset.zero, Offset(4, 0), Offset(0, 4)],
        ),
        angle: 0.5,
      );
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(64, 64));
      final calls = [
        for (final i in canvas.invocations) i.invocation.memberName,
      ];
      expect(calls, [
        #save,
        #translate,
        #rotate,
        #drawPath,
        #drawPath,
        #restore,
      ]);
    });

    test('moved draws land on the same pixels', () async {
      final rect = RectangleComponent(width: 13.3, height: 7.1);
      place(rect, x: 31.123456789, y: 17.987654321);
      final circle = CircleComponent(radius: 6.4);
      place(circle, x: 12.3456, y: 44.4444);
      await expectSame(rect, (canvas) {
        _OldRecipe.rect(canvas, rect);
        _OldRecipe.circle(canvas, circle);
      }, tolerance: 1);
    });

    test('an invisible outline is not drawn', () {
      place(
        CircleComponent(
          radius: 4,
          strokeStyle: const ShapePaintStyle(color: Color(0x00FFFFFF)),
        ),
      );
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(64, 64));
      expect(
        canvas.invocations.where((i) => i.invocation.memberName == #drawCircle),
        hasLength(1),
      );
    });

    test('a zero-wide outline is still drawn: it is a hairline', () {
      place(RectangleComponent(width: 10, height: 10, strokeWidth: 0));
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(64, 64));
      expect(
        canvas.invocations.where((i) => i.invocation.memberName == #drawRect),
        hasLength(2),
      );
    });
  });

  group('batchShapes', () {
    late World batched;
    late List<String> log;
    setUp(() {
      log = [];
      batched = World()..initialize();
      batched.addSystem(RenderSystem(passes: const [], batchShapes: true));
    });
    tearDown(() => batched.dispose());

    Entity add(RenderableComponent c, {int layer = 0, double x = 10}) =>
        batched.createEntityWithComponents([
          TransformComponent(position: Vector3(x, 10, 0)),
          c,
          LayerComponent(layer: layer),
        ]);

    List<String> calls() {
      final canvas = _Calls(log);
      batched.render(canvas, const Size(64, 64));
      return log;
    }

    test('a run of plain shapes is one draw, in its place in the order', () {
      add(RectangleComponent(width: 4, height: 4));
      add(CircleComponent(radius: 3));
      add(RenderableComponent(renderable: _Plain(log)), layer: 1);
      add(RectangleComponent(width: 4, height: 4), layer: 2);
      add(RectangleComponent(width: 4, height: 4), layer: 2);
      expect(calls(), ['vertices', 'plain', 'vertices']);
    });

    test('what triangles cannot draw exactly is drawn by itself', () {
      add(RectangleComponent(width: 4, height: 4, cornerRadius: 1));
      add(RectangleComponent(width: 4, height: 4, fillStyle: _gradient));
      add(RectangleComponent(width: 4, height: 4, strokeWidth: 0));
      final faded = RectangleComponent(width: 4, height: 4);
      add(faded);
      faded.renderable.opacity = 0.5;
      expect(calls().where((c) => c == 'vertices'), isEmpty);
    });

    test('a solid, square rectangle on whole pixels looks the same', () async {
      final c = RectangleComponent(
        width: 20,
        height: 10,
        fillStyle: const ShapePaintStyle(color: Color(0xFF3388FF)),
        strokeStyle: const ShapePaintStyle(color: Color(0x00000000)),
      );
      batched.createEntityWithComponents([
        TransformComponent(position: Vector3(30, 30, 0)),
        c,
      ]);
      await _pixels((canvas) => batched.render(canvas, const Size(64, 64)));
      final triangles = await _pixels(
        (canvas) => batched.render(canvas, const Size(64, 64)),
      );
      final plain = await _pixels((canvas) => _OldRecipe.rect(canvas, c));
      expect(triangles.any((b) => b != 0), isTrue);
      expect(_maxDiff(triangles, plain), 0);
    });
  });

  group('cullOffscreen', () {
    late World culled;
    setUp(() {
      culled = World()..initialize();
      culled.addSystem(RenderSystem(passes: const [], cullOffscreen: true));
    });
    tearDown(() => culled.dispose());

    int rectsDrawn() {
      final canvas = _Clipped(const Rect.fromLTWH(0, 0, 100, 100));
      culled.render(canvas, const Size(100, 100));
      return canvas.invocations
          .where((i) => i.invocation.memberName == #drawRect)
          .length;
    }

    void rect(double x, double y, {double width = 10, double angle = 0}) {
      culled.createEntityWithComponents([
        TransformComponent(position: Vector3(x, y, 0), angle: angle),
        RectangleComponent(
          width: width,
          height: 2,
          strokeStyle: const ShapePaintStyle(color: Color(0x00000000)),
        ),
      ]);
    }

    test('skips what is wholly off screen, keeps what reaches in', () {
      rect(50, 50);
      rect(500, 50);
      rect(-40, 50, width: 100); // Centre off screen, reaching in.
      rect(50, -30, width: 100, angle: 1.4); // Turned into view.
      expect(rectsDrawn(), 3);
    });

    test('is off unless asked for', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(RenderSystem(passes: const []));
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(5000, 0, 0)),
        RectangleComponent(width: 1, height: 1),
      ]);
      final canvas = _Clipped(const Rect.fromLTWH(0, 0, 100, 100));
      world.render(canvas, const Size(100, 100));
      expect(
        canvas.invocations.where((i) => i.invocation.memberName == #drawRect),
        hasLength(2),
      );
    });
  });
}

class _Plain extends Renderable {
  _Plain(this.log);
  final List<String> log;
  @override
  void render(Canvas canvas, Size size) => log.add('plain');
  @override
  Rect? getBounds() => null;
}

/// Logs each drawVertices as 'vertices'.
class _Calls extends TestRecordingCanvas {
  _Calls(this.log);
  final List<String> log;

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    log.add('vertices');
  }
}

/// A recording canvas that reports [clip] as what it shows.
class _Clipped extends TestRecordingCanvas {
  _Clipped(this.clip);
  final Rect clip;

  @override
  Rect getLocalClipBounds() => clip;
}
