import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _eps = 1e-9;

void _expectSameTransform(TransformComponent a, TransformComponent b) {
  for (final (x, y) in [
    (a.position.x, b.position.x),
    (a.position.y, b.position.y),
    (a.position.z, b.position.z),
    (a.scale.x, b.scale.x),
    (a.scale.y, b.scale.y),
    (a.scale.z, b.scale.z),
  ]) {
    expect(x, closeTo(y, 1e-9));
  }
  final qa = Quaternion.identity(), qb = Quaternion.identity();
  a.rotationInto(qa);
  b.rotationInto(qb);
  expect(qa.sameRotation(qb, 1e-9), isTrue, reason: '$qa vs $qb');
}

TransformComponent _copy(TransformComponent t) {
  final e = Vector3.zero();
  t.eulerInto(e);
  return TransformComponent(
    position: Vector3.copy(t.position),
    euler: e,
    scale: Vector3.copy(t.scale),
  );
}

/// A parent and child linked both ways, the way the loader leaves them.
({World world, Entity parent, Entity child}) _pair({
  required TransformComponent parent,
  required TransformComponent child,
}) {
  final world = World()..initialize();
  final p = world.createEntityWithComponents([
    parent,
    ChildrenComponent(),
  ], name: 'P');
  final c = world.createEntityWithComponents([
    child,
    ParentComponent(parentId: p.id),
  ], name: 'C');
  p.getComponent<ChildrenComponent>()!.addChild(c.id);
  return (world: world, parent: p, child: c);
}

void main() {
  group('HierarchyMath', () {
    test('compose after inverse gives the child back — planar', () {
      final parent = TransformComponent(
        position: Vector3(100, 50, 3),
        angle: 0.6,
        scale: Vector3(2, 2, 1),
      );
      final child = TransformComponent(
        position: Vector3(130, 90, 7),
        angle: -1.2,
        scale: Vector3(0.5, 1.5, 2),
      );
      final link = ParentComponent();
      HierarchyMath.localFromWorld(parent, child, link);
      final out = TransformComponent();
      HierarchyMath.composeWorld(parent, link, out);
      _expectSameTransform(out, child);
      expect(out.isPlanar, isTrue);
      expect(out.angle, closeTo(-1.2, _eps));
    });

    test('compose after inverse gives the child back — random 3-D', () {
      final rnd = math.Random(3);
      double r() => (rnd.nextDouble() - 0.5) * 4;
      for (var i = 0; i < 100; i++) {
        final k = 0.5 + rnd.nextDouble() * 2; // uniform parent scale
        final parent = TransformComponent(
          position: Vector3(r(), r(), r()),
          euler: Vector3(r(), r(), r()),
          scale: Vector3(k, k, k),
        );
        final child = TransformComponent(
          position: Vector3(r(), r(), r()),
          euler: Vector3(r(), r(), r()),
          scale: Vector3(r() + 3, r() + 3, r() + 3),
        );
        final link = ParentComponent();
        HierarchyMath.localFromWorld(parent, child, link);
        final out = _copy(child); // a hint close to the answer
        out.setEuler(0, 0, 0);
        HierarchyMath.composeWorld(parent, link, out);
        _expectSameTransform(out, child);
      }
    });

    test('a child placed locally sits where the matrices say', () {
      final parent = TransformComponent(
        position: Vector3(10, 20, 30),
        euler: Vector3(0.3, -0.5, 0.9),
        scale: Vector3(2, 2, 2),
      );
      final link = ParentComponent(
        localPosition: Vector3(1, 2, 3),
        localRotation: EulerRotation(0.2, 0.1, -0.4),
        localScale: Vector3(1, 2, 3),
      );
      final child = TransformComponent();
      HierarchyMath.composeWorld(parent, link, child);

      final mp = Matrix4.zero(), ml = Matrix4.zero(), mc = Matrix4.zero();
      parent.localToWorldInto(mp);
      final q = Quaternion.identity();
      link.localRotation.quaternionInto(q);
      ml.setFromTrs(link.localPosition, q, link.localScale);
      final want = Matrix4.zero()..setProduct(mp, ml);
      child.localToWorldInto(mc);
      for (var i = 0; i < 16; i++) {
        expect(mc.storage[i], closeTo(want.storage[i], 1e-9), reason: '$i');
      }
    });

    test('a mirrored parent (facing left) mirrors its child exactly', () {
      final parent = TransformComponent(
        position: Vector3(0, 0, 0),
        scale: Vector3(-1, 1, 1),
      );
      final link = ParentComponent(
        localPosition: Vector3(10, 0, 0),
        localRotation: EulerRotation(0, 0, 0.5),
      );
      final child = TransformComponent();
      HierarchyMath.composeWorld(parent, link, child);
      expect(child.position.x, closeTo(-10, _eps));
      expect(child.angle, closeTo(-0.5, _eps), reason: 'turn is mirrored');
      expect(child.scale.x, -1);

      final back = ParentComponent();
      HierarchyMath.localFromWorld(parent, child, back);
      expect(back.localPosition.x, closeTo(10, _eps));
      expect(back.localRotation.z, closeTo(0.5, _eps));
    });

    test('an uneven parent scale drops the skew but inverts exactly', () {
      final parent = TransformComponent(
        angle: 0.3,
        scale: Vector3(3, 1, 1),
      );
      final child = TransformComponent(
        position: Vector3(5, -2, 0),
        angle: 1.0,
        scale: Vector3(2, 2, 1),
      );
      final link = ParentComponent();
      HierarchyMath.localFromWorld(parent, child, link);
      final out = TransformComponent();
      HierarchyMath.composeWorld(parent, link, out);
      _expectSameTransform(out, child);
    });

    test('a parent with zero scale on an axis is reported, not divided by', () {
      final parent = TransformComponent(scale: Vector3(0, 1, 1));
      final child = TransformComponent(position: Vector3(4, 5, 0));
      final link = ParentComponent();
      expect(HierarchyMath.localFromWorld(parent, child, link), isFalse);
      expect(link.localPosition.x, 0);
      expect(link.localPosition.y, 5);
      expect(link.localPosition.x.isFinite, isTrue);
    });
  });

  group('the world keeps children with their parents', () {
    test('a loaded child stays where the file put it', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(position: Vector3(100, 0, 0), angle: 0.5),
        child: TransformComponent(position: Vector3(130, 40, 2)),
      );
      addTearDown(world.dispose);
      world.update(1 / 60);
      final t = child.getComponent<TransformComponent>()!;
      expect([t.position.x, t.position.y, t.position.z], [130, 40, 2]);
      expect(child.getComponent<ParentComponent>()!.needsLocal, isFalse);
    });

    test('moving, turning and scaling the parent carries the child', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(position: Vector3(0, 0, 0)),
        child: TransformComponent(position: Vector3(10, 0, 0)),
      );
      addTearDown(world.dispose);
      world.update(1 / 60);

      final pt = parent.getComponent<TransformComponent>()!;
      pt
        ..setPositionXY(100, 100)
        ..angle = math.pi / 2;
      pt.scale.setValues(2, 2, 1);
      world.update(1 / 60);

      final t = child.getComponent<TransformComponent>()!;
      // 10 along +X, scaled ×2, turned a quarter (clockwise on screen: +X
      // goes to +Y).
      expect(t.position.x, closeTo(100, 1e-9));
      expect(t.position.y, closeTo(120, 1e-9));
      expect(t.angle, closeTo(math.pi / 2, 1e-9));
      expect(t.scale.x, 2);
    });

    test('a child moved directly stays put, and follows from there', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(position: Vector3(0, 0, 0)),
        child: TransformComponent(position: Vector3(10, 0, 0)),
      );
      addTearDown(world.dispose);
      world.update(1 / 60);

      final t = child.getComponent<TransformComponent>()!;
      t.setPositionXY(50, 5); // gameplay, physics, a timeline…
      world.update(1 / 60);
      expect([t.position.x, t.position.y], [50, 5]);

      parent.getComponent<TransformComponent>()!.setPositionXY(1, 1);
      world.update(1 / 60);
      expect([t.position.x, t.position.y], [51, 6]);
    });

    test('grandchildren follow through a parent without a ParentComponent', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final map = world.createEntityWithComponents([
        TransformComponent(),
        ChildrenComponent(),
      ], name: 'Level Map');
      final mid = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 0, 0)),
        ParentComponent(parentId: map.id),
        ChildrenComponent(),
      ], name: 'Mid');
      final leaf = world.createEntityWithComponents([
        TransformComponent(position: Vector3(20, 0, 0)),
        ParentComponent(parentId: mid.id),
      ], name: 'Leaf');
      map.getComponent<ChildrenComponent>()!.addChild(mid.id);
      mid.getComponent<ChildrenComponent>()!.addChild(leaf.id);
      world.update(0);

      map.getComponent<TransformComponent>()!.setPositionXY(0, 7);
      world.update(0);
      expect(mid.getComponent<TransformComponent>()!.position.y, 7);
      expect(leaf.getComponent<TransformComponent>()!.position.y, 7);
      expect(leaf.getComponent<TransformComponent>()!.position.x, 20);
    });

    test('a link that does not inherit leaves the child alone', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(),
        child: TransformComponent(position: Vector3(10, 0, 0)),
      );
      addTearDown(world.dispose);
      child.getComponent<ParentComponent>()!.inheritTransform = false;
      world.update(0);
      parent.getComponent<TransformComponent>()!.setPositionXY(99, 99);
      world.update(0);
      expect(child.getComponent<TransformComponent>()!.position.x, 10);
    });

    test('clearing the systems keeps the hierarchy', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(),
        child: TransformComponent(position: Vector3(10, 0, 0)),
      );
      addTearDown(world.dispose);
      world
        ..addSystem(MovementSystem())
        ..clearSystems()
        ..update(0);
      parent.getComponent<TransformComponent>()!.setPositionXY(5, 0);
      world.update(0);
      expect(child.getComponent<TransformComponent>()!.position.x, 15);
    });

    test('a dynamic physics child keeps to the physics', () {
      final physics = PhysicsEngine.pureDart()..initialize();
      addTearDown(physics.dispose);
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(),
        child: TransformComponent(position: Vector3(10, 0, 0)),
      );
      addTearDown(world.dispose);
      child.addComponent(
        PhysicsBodyComponent(shape: CircleShape(2), showDebugOutline: false),
      );
      world.addSystem(PhysicsSystem(physics));
      for (var i = 0; i < 30; i++) {
        world.update(1 / 60);
      }
      final t = child.getComponent<TransformComponent>()!;
      expect(t.position.y, greaterThan(0), reason: 'it falls');
      final body = physics.bodies.single;
      expect(t.position.y, closeTo(body.position.y, 1e-9));
    });

    test('adopt keeps the world placement when re-parenting', () {
      final (:world, :parent, :child) = _pair(
        parent: TransformComponent(position: Vector3(50, 0, 0), angle: 1),
        child: TransformComponent(
          position: Vector3(60, 10, 4),
          euler: Vector3(0.2, 0, 0.3),
        ),
      );
      addTearDown(world.dispose);
      world.transformHierarchy.adopt(child);
      final t = child.getComponent<TransformComponent>()!;
      expect([t.position.x, t.position.y, t.position.z], [60, 10, 4]);
      expect(t.eulerX, 0.2);
      world.update(0);
      expect(t.position.x, closeTo(60, 1e-9));
      expect(t.eulerX, closeTo(0.2, 1e-9));
    });
  });
}
