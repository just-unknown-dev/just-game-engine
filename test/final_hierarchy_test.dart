// Hierarchy fixes from the 2.0.0 final pass: a link made with local values
// places its child (F41), and the world keeps a parent's ChildrenComponent
// in step with its children's ParentComponents (F44).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;

  setUp(() => world = World()..initialize());
  tearDown(() => world.dispose());

  Entity at(double x, double y, {double angle = 0, String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, y, 0), angle: angle),
      ], name: name);

  List<EntityId> childrenOf(Entity parent) =>
      List.of(parent.getComponent<ChildrenComponent>()?.childIds ?? const []);

  group('F41 a link made with local values', () {
    test('places the child at them on the first pass', () {
      final base = at(100, 50, angle: math.pi / 2, name: 'Base');
      final turret = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: base.id, localPosition: Vector3(10, 0, 0)),
      ], name: 'Turret');

      world.transformHierarchy.propagate();

      final t = turret.getComponent<TransformComponent>()!;
      expect(t.position.x, closeTo(100, 1e-9));
      expect(t.position.y, closeTo(60, 1e-9));
      expect(t.angle, closeTo(math.pi / 2, 1e-9));
      final link = turret.getComponent<ParentComponent>()!;
      expect(link.localPosition.x, 10, reason: 'the locals were kept');
      expect(link.placesByLocal, isFalse, reason: 'settled now');
    });

    test('then follows the parent from those locals', () {
      final base = at(100, 50, angle: math.pi / 2);
      final turret = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: base.id, localPosition: Vector3(10, 0, 0)),
      ]);
      world.transformHierarchy.propagate();
      base.getComponent<TransformComponent>()!.position.x = 200;
      world.transformHierarchy.propagate();
      final p = turret.getComponent<TransformComponent>()!.position;
      expect(p.x, closeTo(200, 1e-9));
      expect(p.y, closeTo(60, 1e-9));
    });

    test('propagateFrom places it too', () {
      final base = at(100, 50, angle: math.pi / 2);
      final turret = world.createEntityWithComponents([
        TransformComponent(position: Vector3(-5, -5, 0)),
        ParentComponent(parentId: base.id, localPosition: Vector3(10, 0, 0)),
      ]);
      world.transformHierarchy.propagateFrom(turret);
      final p = turret.getComponent<TransformComponent>()!.position;
      expect(p.x, closeTo(100, 1e-9));
      expect(p.y, closeTo(60, 1e-9));
    });

    test('a link without locals keeps the child where it is', () {
      final base = at(100, 50, angle: math.pi / 2);
      final child = world.createEntityWithComponents([
        TransformComponent(position: Vector3(7, 8, 0)),
        ParentComponent(parentId: base.id),
      ]);
      world.transformHierarchy.propagate();
      final p = child.getComponent<TransformComponent>()!.position;
      expect((p.x, p.y), (7, 8));
      expect(child.getComponent<ParentComponent>()!.needsLocal, isFalse);
    });
  });

  group('F44 the parent lists its children', () {
    test('a ParentComponent alone makes the parent list the child', () {
      final parent = at(10, 0);
      expect(parent.hasComponent<ChildrenComponent>(), isFalse);
      final child = world.createEntityWithComponents([
        TransformComponent(position: Vector3(15, 0, 0)),
        ParentComponent(parentId: parent.id),
      ]);
      expect(childrenOf(parent), [child.id]);

      // And so the child follows its parent.
      world.transformHierarchy.propagate();
      parent.getComponent<TransformComponent>()!.position.x = 30;
      world.transformHierarchy.propagate();
      expect(child.getComponent<TransformComponent>()!.position.x, 35);
    });

    test('added later, a link is listed once, in order', () {
      final parent = at(0, 0);
      final a = at(1, 0);
      final b = at(2, 0);
      b.addComponent(ParentComponent(parentId: parent.id));
      a.addComponent(ParentComponent(parentId: parent.id));
      parent.getComponent<ChildrenComponent>()!.addChild(a.id);
      expect(childrenOf(parent), [b.id, a.id]);
    });

    test('changing parentId moves the child between lists', () {
      final first = at(0, 0);
      final second = at(50, 0);
      final child = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: first.id),
      ]);
      child.getComponent<ParentComponent>()!.parentId = second.id;
      expect(childrenOf(first), isEmpty);
      expect(childrenOf(second), [child.id]);

      child.getComponent<ParentComponent>()!.parentId = null;
      expect(childrenOf(second), isEmpty);
    });

    test('removing the link or destroying the child takes it off', () {
      final parent = at(0, 0);
      final a = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
      ]);
      final b = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
      ]);
      a.removeComponent<ParentComponent>();
      expect(childrenOf(parent), [b.id]);
      world.destroyEntity(b);
      expect(childrenOf(parent), isEmpty);
    });

    test('a new link to the same parent keeps the child in its place', () {
      final parent = at(0, 0);
      final a = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
      ]);
      final b = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
      ]);
      a.addComponent(ParentComponent(parentId: parent.id));
      expect(childrenOf(parent), [a.id, b.id]);
    });

    test('a link to nobody, or to itself, lists nothing', () {
      final lonely = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: 999),
      ]);
      expect(world.getEntity(999), isNull);
      lonely.getComponent<ParentComponent>()!.parentId = lonely.id;
      expect(lonely.hasComponent<ChildrenComponent>(), isFalse);
    });

    test('a scene still loads its hierarchy in file order', () {
      final defs = world.context.definitions;
      Map<String, dynamic> transform() =>
          defs.encode(TransformComponent(position: Vector3(1, 2, 0)))!;
      final created = SceneLoader.load(world, {
        'formatVersion': SceneFormat.current,
        'entities': [
          {
            'name': 'Root',
            'components': [transform()],
          },
          for (final name in ['B', 'A', 'C'])
            {
              'name': name,
              'parentName': 'Root',
              'components': [
                transform(),
                defs.encode(ParentComponent(parentId: 12345))!,
              ],
            },
        ],
      });
      final root = created.first;
      expect(childrenOf(root), [for (final e in created.skip(1)) e.id]);
      for (final child in created.skip(1)) {
        expect(child.getComponent<ParentComponent>()!.parentId, root.id);
      }
    });
  });
}
