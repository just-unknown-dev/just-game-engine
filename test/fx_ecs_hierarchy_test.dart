// The transform hierarchy works out a parent's turn once for all its
// children and skips a child nothing has moved. Both must leave every
// transform bit-for-bit what composing every child every frame gave.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
// Internal: the reference below is the hierarchy as it was, pass by pass.
import 'package:just_game_engine/src/ecs/base/transform/hierarchy_math.dart';

/// The hierarchy pass as it was before, composing every child every frame.
void referencePropagate(World world) {
  bool isRoot(Entity e) {
    final parentId = e.getComponent<ParentComponent>()?.parentId;
    if (parentId == null) return true;
    final parent = world.getEntity(parentId);
    return parent == null || !parent.isActive;
  }

  for (final root in world.query(const [ChildrenComponent])) {
    if (!isRoot(root)) continue;
    final stack = [root];
    while (stack.isNotEmpty) {
      final parent = stack.removeLast();
      final children = parent.getComponent<ChildrenComponent>();
      if (children == null) continue;
      final pt = parent.getComponent<TransformComponent>();
      for (final id in children.childIds) {
        final child = world.getEntity(id);
        if (child == null || !child.isActive) continue;
        if (pt != null) {
          final link = child.getComponent<ParentComponent>();
          final t = child.getComponent<TransformComponent>();
          if (link != null &&
              t != null &&
              link.parentId == parent.id &&
              link.inheritTransform) {
            if (link.needsLocal || link.movedSinceSeen(t)) {
              HierarchyMath.localFromWorld(pt, t, link);
              link.needsLocal = false;
            } else {
              HierarchyMath.composeWorld(pt, link, t);
            }
            link.markSeen(t);
          }
        }
        stack.add(child);
      }
    }
  }
}

/// Three levels: 3 roots, 2 children each, 1 grandchild each.
List<Entity> build(World world) {
  final all = <Entity>[];
  Entity make(double x, double y, [Entity? parent]) {
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
    ]);
    if (parent != null) {
      e.addComponent(ParentComponent(parentId: parent.id));
      if (!parent.hasComponent<ChildrenComponent>()) {
        parent.addComponent(ChildrenComponent());
      }
      parent.getComponent<ChildrenComponent>()!.addChild(e.id);
    }
    all.add(e);
    return e;
  }

  for (var r = 0; r < 3; r++) {
    final root = make(r * 100.0, 10.0 * r);
    for (var c = 0; c < 2; c++) {
      final child = make(r * 100.0 + 20 + c, 30.0 + c, root);
      make(r * 100.0 + 25, 45.0 + c, child);
    }
  }
  return all;
}

bool sameBits(double a, double b) =>
    (a.isNaN && b.isNaN) || (a == b && a.isNegative == b.isNegative);

void expectSame(Entity a, Entity b, String when) {
  final ta = a.getComponent<TransformComponent>()!;
  final tb = b.getComponent<TransformComponent>()!;
  final values = [
    (ta.position.x, tb.position.x, 'x'),
    (ta.position.y, tb.position.y, 'y'),
    (ta.position.z, tb.position.z, 'z'),
    (ta.eulerX, tb.eulerX, 'eulerX'),
    (ta.eulerY, tb.eulerY, 'eulerY'),
    (ta.angle, tb.angle, 'angle'),
    (ta.scale.x, tb.scale.x, 'sx'),
    (ta.scale.y, tb.scale.y, 'sy'),
    (ta.scale.z, tb.scale.z, 'sz'),
  ];
  for (final (x, y, what) in values) {
    expect(sameBits(x, y), isTrue, reason: '$when: $a $what $x vs $y');
  }
}

void main() {
  test('matches composing every child every frame, bit for bit (P17)', () {
    final fresh = World();
    final reference = World()..transformHierarchy.enabled = false;
    final a = build(fresh);
    final b = build(reference);
    final random = math.Random(7);

    for (var frame = 0; frame < 400; frame++) {
      // The same edits to both worlds. Many frames change nothing at all,
      // so the skip is taken often.
      final edits = random.nextInt(4);
      for (var k = 0; k < edits; k++) {
        final i = random.nextInt(a.length);
        final op = random.nextInt(9);
        final v = random.nextDouble() * 200 - 100;
        for (final e in [a[i], b[i]]) {
          final t = e.getComponent<TransformComponent>()!;
          final link = e.getComponent<ParentComponent>();
          switch (op) {
            case 0:
              t.position.x = v;
            case 1:
              t.angle = v / 50;
            case 2:
              t.scale.setValues(v / 40, v / 60, 1);
            case 3:
              link?.localPosition.x = v;
            case 4:
              link?.localRotation.z = v / 30;
            case 5:
              link?.localScale.y = v / 70;
            case 6:
              // A turn out of the plane: the 3-D path, never skipped.
              t.eulerX = frame.isEven ? 0.0 : v / 90;
            case 7:
              e.isActive = !e.isActive;
            case 8:
              t.position.y += v;
          }
        }
      }
      fresh.update(1 / 60);
      reference.update(1 / 60);
      referencePropagate(reference);
      for (var i = 0; i < a.length; i++) {
        expectSame(a[i], b[i], 'frame $frame');
      }
    }
  });

  test('a still child is left as composed; any change moves it', () {
    final world = World();
    final parent = world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 0, 0)),
      ChildrenComponent(),
    ]);
    final child = world.createEntityWithComponents([
      TransformComponent(position: Vector3(110, 0, 0)),
      ParentComponent(parentId: parent.id),
    ]);
    parent.getComponent<ChildrenComponent>()!.addChild(child.id);
    final t = child.getComponent<TransformComponent>()!;
    final link = child.getComponent<ParentComponent>()!;

    world.update(0); // local worked out: 10 to the right
    world.update(0); // composed
    expect(t.position.x, 110);

    parent.getComponent<TransformComponent>()!.position.x = 200;
    world.update(0);
    expect(t.position.x, 210);

    link.localPosition.x = 20;
    world.update(0);
    expect(t.position.x, 220);

    parent.getComponent<TransformComponent>()!.angle = math.pi / 2;
    world.update(0);
    expect(t.position.x, closeTo(200, 1e-9));
    expect(t.position.y, closeTo(20, 1e-9));

    // Moved by something else: stays where it was put.
    t.position.setValues(0, 0, 0);
    world.update(0);
    world.update(0);
    expect(t.position.x, closeTo(0, 1e-9));
    expect(t.position.y, closeTo(0, 1e-9));
  });
}
