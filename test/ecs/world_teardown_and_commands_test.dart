// World: deferred commands belong to the world they were queued in (a clear
// drops them) and are applied even with no systems; a system added from
// another's initialize is initialized; removal and disposal carry on past a
// callback that throws; removing a parent's ChildrenComponent leaves no
// child linked to it; re-adding a component the entity already has changes
// nothing; the event bus says whether anything listens.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Ping extends GameEvent {}

class _Counted extends System {
  int inits = 0;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void initialize() => inits++;
}

class _Adder extends System {
  _Adder(this.child);
  final System child;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void initialize() => world.addSystem(child);
}

/// Records its removal and disposal into [log]; throws from them when told.
class _Fragile extends System {
  _Fragile(this.name, this.log, {this.throwsOnRemove = false});
  final String name;
  final List<String> log;
  final bool throwsOnRemove;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void onRemovedFromWorld() {
    log.add('$name removed');
    if (throwsOnRemove) throw StateError('$name failed');
  }

  @override
  void dispose() => log.add('$name disposed');
}

/// Counts attach and detach calls.
class _Tracked extends Component {
  int attached = 0;
  int detached = 0;
  @override
  void onAttach(EntityId entityId) => attached++;
  @override
  void onDetach(EntityId entityId) => detached++;
}

/// Throws when detached.
class _Sticky extends Component {
  @override
  void onDetach(EntityId entityId) => throw StateError('sticky');
}

void main() {
  group('deferred commands', () {
    test('queued before destroyAllEntities never reach the next scene', () {
      final world = World()..addSystem(_Counted());
      world.commands.create([TransformComponent()], name: 'stale');
      world.destroyAllEntities();
      world.createEntity(name: 'next scene');
      world.update(1 / 60);
      expect(world.findEntityByName('stale'), isNull);
      expect(world.entityCount, 1);
    });

    test('are applied in a world with no systems', () {
      final world = World();
      world.commands.create([TransformComponent()], name: 'made');
      world.update(1 / 60);
      expect(world.findEntityByName('made'), isNotNull);
    });

    test('queued between updates are seen by the first system', () {
      final world = World();
      final seen = <int>[];
      world.addSystem(_Probe(() => seen.add(world.entityCount)));
      world.commands.create([TransformComponent()]);
      world.update(1 / 60);
      expect(seen, [1]);
    });

    test('a clear during a flush drops the rest of it', () {
      final world = World()..addSystem(_Counted());
      world.commands
        ..create([_ClearOnAttach(world)], name: 'clearer')
        ..create([TransformComponent()], name: 'after');
      world.update(1 / 60);
      expect(world.findEntityByName('after'), isNull);
    });

    test('dispose drops them too', () {
      final world = World();
      world.commands.create([TransformComponent()]);
      world.dispose();
      expect(world.commands.isNotEmpty, isFalse);
    });

    test('clearCount counts the clears', () {
      final world = World();
      expect(world.clearCount, 0);
      world.destroyAllEntities();
      world.destroyAllEntities();
      expect(world.clearCount, 2);
    });
  });

  test('a system added by another system\'s initialize is initialized', () {
    final world = World();
    final child = _Counted();
    world.addSystem(_Adder(child));
    world.initialize();
    expect(child.inits, 1);
    world.initialize(); // twice does nothing more
    expect(child.inits, 1);
  });

  group('teardown that throws', () {
    test('removeSystem takes the system out and still disposes it', () {
      final world = World();
      final log = <String>[];
      final system = _Fragile('a', log, throwsOnRemove: true);
      world.addSystem(system);
      expect(() => world.removeSystem(system), throwsStateError);
      expect(log, ['a removed', 'a disposed']);
      expect(world.systems, isEmpty);
      expect(world.hasSystem<_Fragile>(), isFalse);
    });

    test('clearSystems removes and disposes every system', () {
      final world = World();
      final log = <String>[];
      world
        ..addSystem(_Fragile('a', log, throwsOnRemove: true))
        ..addSystem(_Fragile('b', log));
      expect(world.clearSystems, throwsStateError);
      expect(log, ['a removed', 'a disposed', 'b removed', 'b disposed']);
      expect(world.systems, isEmpty);
    });

    test('dispose still detaches every entity after a system throws', () {
      final world = World();
      final log = <String>[];
      world.addSystem(_Fragile('a', log, throwsOnRemove: true));
      final tracked = _Tracked();
      world.createEntityWithComponents([tracked]);
      expect(world.dispose, throwsStateError);
      expect(tracked.detached, 1);
      expect(world.entityCount, 0);
    });

    test('a component that throws on detach does not stop the clear', () {
      final world = World();
      final tracked = _Tracked();
      world
        ..createEntityWithComponents([_Sticky()])
        ..createEntityWithComponents([tracked]);
      expect(world.destroyAllEntities, throwsStateError);
      expect(tracked.detached, 1);
      expect(world.entityCount, 0);
    });
  });

  group("a parent's ChildrenComponent", () {
    late World world;
    late Entity parent, child;
    setUp(() {
      world = World();
      parent = world.createEntityWithComponents([TransformComponent()]);
      child = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
      ]);
    });

    test('removed: its children are cut loose, not left dangling', () {
      parent.removeComponent<ChildrenComponent>();
      expect(child.getComponent<ParentComponent>()!.parentId, isNull);
      parent.isActive = false;
      expect(child.isActiveInHierarchy, isTrue);
      world.destroyEntity(parent);
      expect(child.isAlive, isTrue);
    });

    test('replaced: the new one lists the children', () {
      parent.addComponent(ChildrenComponent());
      expect(parent.getComponent<ChildrenComponent>()!.childIds, [child.id]);
      parent.isActive = false;
      expect(child.isActiveInHierarchy, isFalse);
      world.destroyEntity(parent);
      expect(child.isAlive, isFalse);
    });

    test('cannot be removed in the inspector', () {
      final defs = world.context.definitions;
      expect(
        defs.definitionByType('ChildrenComponent')!.hints.deletable,
        isFalse,
      );
    });
  });

  test('adding the component an entity already has changes nothing', () {
    final world = World();
    final tracked = _Tracked();
    final entity = world.createEntityWithComponents([tracked]);
    final version = world.queryVersion([_Tracked]);
    entity.addComponent(tracked);
    expect(tracked.attached, 1);
    expect(tracked.detached, 0);
    expect(world.queryVersion([_Tracked]), version);
    expect(entity.components, [tracked]);
  });

  test('the event bus says whether anything listens', () {
    final bus = EventBus();
    expect(bus.hasListeners<_Ping>(), isFalse);
    final sub = bus.on<_Ping>((_) {});
    expect(bus.hasListeners<_Ping>(), isTrue);
    sub.cancel();
    expect(bus.hasListeners<_Ping>(), isFalse);
  });
}

class _Probe extends System {
  _Probe(this.onUpdate);
  final void Function() onUpdate;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void update(double deltaTime) => onUpdate();
}

/// Clears its world as it is attached.
class _ClearOnAttach extends Component {
  _ClearOnAttach(this.world);
  final World world;
  @override
  void onAttach(EntityId entityId) => world.destroyAllEntities();
}
