// The world's structure version: one number that moves on whenever the
// world's shape may have changed — entities made and destroyed, components
// added, removed and replaced, entities switched on and off and
// re-parented — and stays put when only a component's fields change, so
// code walking part of the tree each frame can skip the walk.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class A extends Component {
  int value = 0;
}

class B extends Component {}

void main() {
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  /// Whether the structure version moved since the last look.
  late bool Function() moved;
  setUp(() {
    var seen = world.structureVersion;
    moved = () {
      final now = world.structureVersion;
      final changed = now != seen;
      expect(now, greaterThanOrEqualTo(seen), reason: 'it only goes up');
      seen = now;
      return changed;
    };
  });

  test('moves on as entities come and go and components change', () {
    final bare = world.createEntity(name: 'bare');
    expect(moved(), isTrue, reason: 'an entity made, with no component');
    final e = world.createEntityWithComponents([A()], name: 'e');
    expect(moved(), isTrue, reason: 'an entity made with components');
    e.addComponent(B());
    expect(moved(), isTrue, reason: 'a component added');
    e.addComponent(A());
    expect(moved(), isTrue, reason: 'a component replaced');
    e.removeComponent<B>();
    expect(moved(), isTrue, reason: 'a component removed');
    world.destroyEntity(bare);
    expect(moved(), isTrue, reason: 'a bare entity destroyed');
    world.destroyEntity(e);
    expect(moved(), isTrue, reason: 'an entity destroyed');
    world.createEntityWithComponents([A()]);
    moved();
    world.destroyAllEntities();
    expect(moved(), isTrue, reason: 'the world cleared');
  });

  test('moves on as entities are switched and re-parented', () {
    final parent = world.createEntityWithComponents([A()], name: 'parent');
    final child = world.createEntityWithComponents([A()], name: 'child');
    // With a list of children already, so moving a child to it adds no
    // component: only the link moves.
    final other = world.createEntityWithComponents([
      A(),
      ChildrenComponent(),
    ], name: 'other');
    moved();

    child.addComponent(ParentComponent(parentId: parent.id));
    expect(moved(), isTrue, reason: 'linked under a parent');
    child.getComponent<ParentComponent>()!.parentId = other.id;
    expect(moved(), isTrue, reason: 're-parented by its link');

    parent.isActive = false;
    expect(moved(), isTrue, reason: 'switched off, with no child under it');
    other.isActive = false;
    expect(moved(), isTrue, reason: 'switched off, its child with it');
    child.isActive = false;
    expect(
      moved(),
      isTrue,
      reason: 'its own flag, though its parent had it off already',
    );
    child.isActive = false;
    expect(moved(), isFalse, reason: 'switched to what it was');
  });

  test('moves on when a child is placed again among its siblings', () {
    final parent = world.createEntityWithComponents([A()], name: 'parent');
    final first = world.createEntityWithComponents([
      ParentComponent(parentId: parent.id),
    ]);
    final second = world.createEntityWithComponents([
      ParentComponent(parentId: parent.id),
    ]);
    moved();

    // As an editor reorders: the list in place, then the child settled.
    parent.getComponent<ChildrenComponent>()!.childIds
      ..remove(second.id)
      ..insert(0, second.id);
    world.transformHierarchy.adopt(second);
    expect(moved(), isTrue, reason: 'settled by the hierarchy');
    expect(parent.getComponent<ChildrenComponent>()!.childIds, [
      second.id,
      first.id,
    ]);

    world.markStructureChanged();
    expect(moved(), isTrue, reason: 'told of a change it cannot see');
  });

  test('stays put while only fields change, and while reading', () {
    final e = world.createEntityWithComponents([A()], name: 'e');
    world.query([A]);
    moved();

    e.getComponent<A>()!.value = 5;
    e.name = 'renamed';
    world
      ..query([A])
      ..update(1 / 60)
      ..update(1 / 60);
    e.isActive = true;
    e.addComponent(e.getComponent<A>()!);
    expect(moved(), isFalse);
  });
}
