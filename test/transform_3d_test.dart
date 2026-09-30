import 'dart:math' as math;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('TransformComponent rotation', () {
    test('a 2-D transform is planar and its angle is a plain value', () {
      final t = TransformComponent(angle: 0.5);
      expect(t.isPlanar, isTrue);
      expect(t.angle, 0.5);
      t.rotate(0.25);
      expect(t.angle, 0.75);
      t.angle = 7.0; // past 2π stays as written
      expect(t.angle, 7.0);

      final q = Quaternion.identity();
      t.rotationInto(q);
      expect(q.sameRotation(Quaternion.identity()..setRotationZ(7.0)), isTrue);
    });

    test('Euler angles follow the one convention', () {
      final t = TransformComponent(euler: Vector3(0.3, -0.4, 1.1));
      expect(t.isPlanar, isFalse);
      final q = Quaternion.identity();
      t.rotationInto(q);
      expect(q.sameRotation(Quaternion.euler(0.3, -0.4, 1.1)), isTrue);
      final e = Vector3.zero();
      t.eulerInto(e);
      expect([e.x, e.y, e.z], [0.3, -0.4, 1.1]);
    });

    test('setRotation keeps counting past 180° instead of jumping', () {
      final t = TransformComponent(angle: 3.0);
      t.setRotation(Quaternion.identity()..setRotationZ(3.3));
      expect(t.angle, closeTo(3.3, 1e-9));
      expect(t.isPlanar, isTrue, reason: 'a Z-only turn stays exactly 2-D');
      expect(t.eulerX, 0.0);
      expect(t.eulerY, 0.0);
    });

    test('setRotation of a 3-D turn round-trips through Euler angles', () {
      final t = TransformComponent();
      final q = Quaternion.euler(0.2, 0.9, -0.4);
      t.setRotation(q);
      expect(t.eulerX, closeTo(0.2, 1e-9));
      expect(t.eulerY, closeTo(0.9, 1e-9));
      expect(t.angle, closeTo(-0.4, 1e-9));
    });

    test('a 2-D physics pose leaves z and the tilts alone', () {
      final t = TransformComponent(
        position: Vector3(1, 2, 30),
        euler: Vector3(0.1, 0.2, 0.3),
      );
      t.capturePrevious();
      t.setPlanarPose(5, 6, 0.9);
      expect([t.position.x, t.position.y, t.position.z], [5, 6, 30]);
      expect([t.eulerX, t.eulerY, t.angle], [0.1, 0.2, 0.9]);
      expect(t.prevAngle, 0.3);
      expect(
        t.prevRotation.sameRotation(Quaternion.euler(0.1, 0.2, 0.3)),
        isTrue,
      );
      expect(t.prevPosition.z, 30);
    });

    test('the matrix is the same on the planar and the general path', () {
      final planar = TransformComponent(
        position: Vector3(3, 4, 5),
        angle: 0.7,
        scale: Vector3(2, 3, 1),
      );
      final m1 = Matrix4.zero();
      planar.localToWorldInto(m1);
      final m2 = Matrix4.zero()
        ..setFromTrs(
          Vector3(3, 4, 5),
          Quaternion.identity()..setRotationZ(0.7),
          Vector3(2, 3, 1),
        );
      for (var i = 0; i < 16; i++) {
        expect(m1.storage[i], closeTo(m2.storage[i], 1e-12));
      }
    });

    test('Canvas.transform with the matrix equals translate/rotate/scale', () {
      final t = TransformComponent(
        position: Vector3(12, -7, 0),
        angle: math.pi / 5,
        scale: Vector3(1.5, 0.5, 1),
      );
      final m = Matrix4.zero();
      t.localToWorldInto(m);

      final a = Canvas(PictureRecorder())..transform(m.storage);
      final b = Canvas(PictureRecorder())
        ..translate(12, -7)
        ..rotate(math.pi / 5)
        ..scale(1.5, 0.5);
      final ma = a.getTransform(), mb = b.getTransform();
      for (var i = 0; i < 16; i++) {
        expect(ma[i], closeTo(mb[i], 1e-6), reason: 'm[$i]');
      }
    });
  });

  group('WorldAxes', () {
    test('down is gravity, up is -Y, forward is into the screen', () {
      expect([WorldAxes.upX, WorldAxes.upY, WorldAxes.upZ], [0, -1, 0]);
      expect(
        [WorldAxes.forwardX, WorldAxes.forwardY, WorldAxes.forwardZ],
        [0, 0, 1],
      );
      // Right-handed: right × down = forward.
      final f = Vector3.zero();
      WorldAxes.right.crossInto(WorldAxes.down, f);
      expect([f.x, f.y, f.z], [0, 0, 1]);
    });
  });

  group('physics keeps the third dimension', () {
    test('a stepped 2-D body keeps its z and tilt', () {
      final physics = PhysicsEngine.pureDart()..initialize();
      addTearDown(physics.dispose);
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(PhysicsSystem(physics));
      final e = world.createEntityWithComponents([
        TransformComponent(
          position: Vector3(0, 0, 42),
          euler: Vector3(0.25, -0.5, 0),
          scale: Vector3(1, 1, 3),
        ),
        PhysicsBodyComponent(shape: CircleShape(4), showDebugOutline: false),
      ]);
      for (var i = 0; i < 30; i++) {
        world.update(1 / 60);
      }
      final t = e.getComponent<TransformComponent>()!;
      expect(t.position.y, greaterThan(0), reason: 'it fell');
      expect(t.position.z, 42);
      expect(t.eulerX, 0.25);
      expect(t.eulerY, -0.5);
      expect(t.scale.z, 3);
    });
  });
}
