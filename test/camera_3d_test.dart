import 'dart:math' as math;
import 'dart:ui' show Canvas, Offset, PictureRecorder, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Camera _flat() => Camera(
  position: const Offset(120, -40),
  zoom: 1.75,
  rotation: 0.4,
  viewportSize: const Size(800, 600),
);

void main() {
  group('a 2-D camera', () {
    test('its canvas matrix is exactly applyTransform', () {
      final camera = _flat();
      final m = Matrix4.zero();
      camera.canvasMatrixInto(m);
      final a = Canvas(PictureRecorder())..transform(m.storage);
      final b = Canvas(PictureRecorder());
      camera.applyTransform(b, camera.viewportSize);
      final ma = a.getTransform(), mb = b.getTransform();
      for (var i = 0; i < 16; i++) {
        // The canvas keeps 32-bit floats.
        expect(ma[i], closeTo(mb[i], 1e-3), reason: 'm[$i]');
      }
    });

    test('a ray through a pixel meets the world plane at screenToWorld', () {
      final camera = _flat();
      for (final screen in const [
        Offset(0, 0),
        Offset(400, 300),
        Offset(799, 17),
        Offset(123, 456),
      ]) {
        final ray = camera.screenToWorldRay(screen);
        final t = ray.intersectZ()!;
        final hit = Vector3.zero();
        ray.atInto(t, hit);
        final want = camera.screenToWorld(screen);
        expect(hit.x, closeTo(want.dx, 1e-6));
        expect(hit.y, closeTo(want.dy, 1e-6));
        // Straight ahead, into the screen.
        expect(ray.direction.z, closeTo(1, 1e-9));
      }
    });

    test('the view-projection puts what it looks at in the middle', () {
      final camera = _flat();
      final vp = Matrix4.zero();
      camera.viewProjectionInto(vp);
      final p = Vector3(120, -40, 0);
      vp.transformPointInto(p, p);
      expect(p.x, closeTo(0, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
      expect(p.z, closeTo(0.5, 1e-9), reason: 'mid-depth of ±10000');
      final s = Vector3.zero();
      camera.worldToScreen3(Vector3(120, -40, 0), s);
      expect([s.x, s.y], [closeTo(400, 1e-9), closeTo(300, 1e-9)]);
    });

    test('is planar, and its state round-trips the new fields', () {
      final camera = _flat();
      expect(camera.isPlanar, isTrue);
      final state = camera.state.copyWith(z: 5, pitch: 0.2);
      camera.apply(state);
      expect([camera.z, camera.pitch], [5, 0.2]);
      expect(camera.isPlanar, isFalse);
    });
  });

  group('a camera in space', () {
    Camera perspective() => Camera(
      viewportSize: const Size(100, 100),
      z: -10,
      lens: const CameraLens.perspective(fieldOfView: math.pi / 2, near: 1),
    );

    test('projects with perspective, y down', () {
      final camera = perspective();
      expect(camera.isPlanar, isFalse);
      final s = Vector3.zero();
      camera.worldToScreen3(Vector3(0, 0, 0), s);
      expect([s.x, s.y], [closeTo(50, 1e-9), closeTo(50, 1e-9)]);
      // 10 to the right at distance 10, with a 90° field: the right edge.
      camera.worldToScreen3(Vector3(10, 0, 0), s);
      expect(s.x, closeTo(100, 1e-9));
      // 10 down (+Y): the bottom edge.
      camera.worldToScreen3(Vector3(0, 10, 0), s);
      expect(s.y, closeTo(100, 1e-9));
      // Twice as far looks half as far from the middle.
      camera.worldToScreen3(Vector3(10, 0, 10), s);
      expect(s.x, closeTo(75, 1e-9));
    });

    test('a ray from the camera through a pixel', () {
      final camera = perspective();
      final ray = camera.screenToWorldRay(const Offset(100, 50));
      final t = ray.intersectZ()!;
      final hit = Vector3.zero();
      ray.atInto(t, hit);
      expect(hit.x, closeTo(10, 1e-6));
      expect(hit.y, closeTo(0, 1e-6));
      expect(camera.screenToWorld(const Offset(50, 50)).dx, closeTo(0, 1e-6));
    });

    test('pitched down, it sees the plane in front of it', () {
      final camera = Camera(
        viewportSize: const Size(100, 100),
        position: const Offset(0, -10),
        z: -10,
        pitch: -math.pi / 4, // tilts +Z (forward) towards +Y (down)
        lens: const CameraLens.perspective(near: 1),
      );
      final hit = camera.screenToWorld(const Offset(50, 50));
      expect(hit.dx, closeTo(0, 1e-6));
      expect(hit.dy, closeTo(0, 1e-6), reason: 'straight down its axis');
      final bounds = camera.getVisibleBounds();
      expect(bounds.contains(Offset.zero), isTrue);
    });
  });

  group('camera states and lenses', () {
    test('a 2-D blend is unchanged; depth and tilt blend too', () {
      const a = CameraState(position: Offset(0, 0), zoom: 1, rotation: 0.1);
      const b = CameraState(position: Offset(10, 20), zoom: 4, rotation: 0.3);
      final mid = CameraState.lerp(a, b, 0.5);
      expect(mid.position, const Offset(5, 10));
      expect(mid.zoom, closeTo(2, 1e-9));
      expect(mid.rotation, closeTo(0.2, 1e-9));
      expect(mid.isPlanar, isTrue);

      const c = CameraState(z: 0, pitch: 0, yaw: 3.0);
      const d = CameraState(z: 10, pitch: 0.4, yaw: -3.0);
      final half = CameraState.lerp(c, d, 0.5);
      expect(half.z, 5);
      expect(half.pitch, closeTo(0.2, 1e-9));
      // The short way round: through π, not through 0.
      expect(half.yaw.abs(), closeTo(math.pi, 1e-9));
    });

    test('lenses blend within a projection and switch across', () {
      const a = CameraLens.perspective(fieldOfView: 1.0);
      const b = CameraLens.perspective(fieldOfView: 2.0);
      expect(CameraLens.lerp(a, b, 0.5).fieldOfView, closeTo(1.5, 1e-9));
      const o = CameraLens.orthographic();
      expect(CameraLens.lerp(o, a, 0.4), o);
      expect(CameraLens.lerp(o, a, 0.6), a);
    });

    test('a virtual camera\'s lens, and a perspective near plane', () {
      final vcam = VirtualCameraComponent();
      expect(vcam.lens, const CameraLens.orthographic());
      vcam
        ..projection = CameraProjection.perspective
        ..fieldOfView = 1.2;
      expect(vcam.lens.isOrthographic, isFalse);
      expect(vcam.lens.fieldOfView, 1.2);
      expect(vcam.lens.near, 1, reason: 'an ortho near is behind the camera');
    });

    test('the lens is saved, and hidden in 2-D scenes', () {
      registerCoreCodecs();
      final def = ComponentDefinitionRegistry.instance.definitionByType(
        'VirtualCameraComponent',
      )!;
      final json = ComponentCodecRegistry.instance.encode(
        VirtualCameraComponent(projection: CameraProjection.perspective),
      )!;
      expect(json['fields']['projection'], 'perspective');
      final back =
          ComponentCodecRegistry.instance.decode(json)!
              as VirtualCameraComponent;
      expect(back.projection, CameraProjection.perspective);
      for (final f in ['projection', 'fieldOfView', 'nearClip', 'farClip']) {
        expect(def.hints.fields[f]!.dimensions, Dimensions.threeD, reason: f);
      }
    });
  });
}
