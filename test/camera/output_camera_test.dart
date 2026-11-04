// The output camera's limits and culling: zoom limits typed the wrong way
// round do not throw; moving and zooming add up, and reset undoes them;
// what a camera in space sees of the world plane is what its four corner
// rays hit; and an inside-out rectangle (the bounds of something flipped)
// is culled as the box it spans.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('zoom limits the wrong way round', () {
    test('do not throw, and keep the zoom between them', () {
      final camera = Camera(minZoom: 5, maxZoom: 2);
      expect(() => camera.setZoom(3), returnsNormally);
      expect(camera.zoom, 3);
      camera.setZoom(10);
      expect(camera.zoom, 5);
      camera.apply(const CameraState(position: Offset.zero, zoom: 1));
      expect(camera.zoom, 2);
      camera.zoomToPoint(Offset.zero, 4);
      expect(camera.zoom, 4);
    });
  });

  test('moving and zooming add to the pose, and reset undoes them', () {
    final camera = Camera(minZoom: 0.5, maxZoom: 4);
    camera.moveBy(const Offset(100, 50));
    camera.moveBy(const Offset(-20, 10));
    expect(camera.position, const Offset(80, 60));
    camera.zoomBy(2);
    expect(camera.zoom, 2);
    camera.zoomBy(3);
    expect(camera.zoom, 4, reason: 'held at maxZoom');
    camera.rotation = 0.5;

    camera.reset();
    expect(camera.position, Offset.zero);
    expect(camera.zoom, 1);
    expect(camera.rotation, 0);
    expect(camera.maxZoom, 4, reason: 'the limits are kept');
  });

  test('a camera in space sees what its corner rays hit on the plane', () {
    final camera = Camera(
      position: const Offset(40, -300),
      viewportSize: const Size(800, 600),
      z: -500,
      pitch: -0.4,
      yaw: 0.3,
      lens: const CameraLens(projection: CameraProjection.perspective),
    );
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    for (final corner in const [
      Offset.zero,
      Offset(800, 0),
      Offset(0, 600),
      Offset(800, 600),
    ]) {
      final ray = camera.screenToWorldRay(corner);
      final p = Vector3.zero();
      ray.atInto(ray.intersectZ()!, p);
      l = math.min(l, p.x);
      t = math.min(t, p.y);
      r = math.max(r, p.x);
      b = math.max(b, p.y);
    }
    final seen = camera.visibleBounds;
    expect(seen.left, closeTo(l, 1e-6));
    expect(seen.top, closeTo(t, 1e-6));
    expect(seen.right, closeTo(r, 1e-6));
    expect(seen.bottom, closeTo(b, 1e-6));

    // Turned away from the plane, a corner misses it: everything.
    camera.yaw = math.pi;
    expect(camera.visibleBounds.width, 1e9);
  });

  test('an inside-out rectangle is culled as the box it spans', () {
    final camera = Camera(viewportSize: const Size(800, 600));
    // A flipped sprite half off the left edge: right before left.
    const flipped = Rect.fromLTRB(-380, -10, -420, 10);
    expect(camera.isRectVisible(flipped), isTrue);
    const away = Rect.fromLTRB(-900, -10, -1000, 10);
    expect(camera.isRectVisible(away), isFalse);
  });
}
