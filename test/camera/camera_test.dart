// The output camera's maths: what is drawn and what is hit-tested must agree.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  const view = Size(800, 600);

  test('screen ↔ world round-trips under zoom and roll', () {
    final camera = Camera(
      position: const Offset(120, -40),
      zoom: 2.5,
      rotation: 0.7,
      viewportSize: view,
    );
    for (final p in const [Offset.zero, Offset(800, 600), Offset(123, 456)]) {
      final back = camera.worldToScreen(camera.screenToWorld(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    }
    final centre = camera.screenToWorld(const Offset(400, 300));
    expect(centre.dx, closeTo(120, 1e-9));
    expect(centre.dy, closeTo(-40, 1e-9));
  });

  test('applyTransform draws where worldToScreen says', () {
    final camera = Camera(
      position: const Offset(50, 80),
      zoom: 1.5,
      rotation: -0.3,
      viewportSize: view,
    );
    final canvas = ui.Canvas(ui.PictureRecorder());
    camera.applyTransform(canvas, view);
    final m = canvas.getTransform();
    const world = Offset(200, -100);
    final drawn = Offset(
      m[0] * world.dx + m[4] * world.dy + m[12],
      m[1] * world.dx + m[5] * world.dy + m[13],
    );
    final expected = camera.worldToScreen(world);
    // The canvas keeps a float32 matrix, so agreement is to a thousandth of
    // a pixel rather than to double precision.
    expect(drawn.dx, closeTo(expected.dx, 1e-3));
    expect(drawn.dy, closeTo(expected.dy, 1e-3));
  });

  test('visible bounds shrink with zoom and centre on the position', () {
    final camera = Camera(
      position: const Offset(1000, 500),
      zoom: 2,
      viewportSize: view,
    );
    expect(
      camera.getVisibleBounds(),
      Rect.fromCenter(center: const Offset(1000, 500), width: 400, height: 300),
    );
    expect(camera.isVisible(const Offset(1199, 500)), isTrue);
    expect(camera.isVisible(const Offset(1201, 500)), isFalse);
  });

  test('zoomToPoint keeps the point under the cursor', () {
    final camera = Camera(position: const Offset(10, 20), viewportSize: view);
    const cursor = Offset(650, 120);
    final world = camera.screenToWorld(cursor);
    camera.zoomToPoint(world, 3);
    final after = camera.worldToScreen(world);
    expect(after.dx, closeTo(cursor.dx, 1e-9));
    expect(after.dy, closeTo(cursor.dy, 1e-9));
    expect(camera.zoom, 3);
  });

  test('state and apply are inverses, within the zoom limits', () {
    final camera = Camera(viewportSize: view, maxZoom: 4);
    const state = CameraState(
      position: Offset(3, 4),
      zoom: 2,
      rotation: math.pi / 6,
    );
    camera.apply(state);
    expect(camera.state, state);
    camera.apply(state.copyWith(zoom: 99));
    expect(camera.zoom, 4);
  });

  test('a blended rotation takes the short way round', () {
    const a = CameraState(rotation: 0.1);
    const b = CameraState(rotation: 2 * math.pi - 0.1);
    expect(CameraState.lerp(a, b, 0.5).rotation, closeTo(0, 1e-9));
  });
}
