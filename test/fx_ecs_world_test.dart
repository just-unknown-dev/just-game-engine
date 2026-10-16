// The ECS world's bookkeeping: switching entities on and off, ids that are
// never reused, components detached on every way out, destroying a
// hierarchy, ordered deferred commands, and the caches and indexes behind
// query, findEntityByName and the tag lookups.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'fx_ecs_twin_types.dart' as twin;

class Health extends Component {
  Health(this.value);
  final int value;
}

class Speed extends Component {}

class Marker extends Component {}

class Watched extends Component {
  Watched(this.log, [this.label = 'w']);
  final List<String> log;
  final String label;

  @override
  void onAttach(EntityId entityId) => log.add('attach $label');

  @override
  void onDetach(EntityId entityId) => log.add('detach $label');
}

/// Links [child] under [parent] the way the scene loader does.
void link(Entity parent, Entity child) {
  child.addComponent(ParentComponent(parentId: parent.id));
  if (!parent.hasComponent<ChildrenComponent>()) {
    parent.addComponent(ChildrenComponent());
  }
  parent.getComponent<ChildrenComponent>()!.addChild(child.id);
}

void main() {
  late World world;
  setUp(() => world = World());

  group('switching an entity on and off (C1)', () {
    test('refreshes a cached query both ways', () {
      final e = world.createEntityWithComponents([Health(1)]);
      expect(world.query([Health]), [e]);

      e.isActive = false;
      expect(world.query([Health]), isEmpty);

      e.isActive = true;
      expect(world.query([Health]), [e]);
    });

    test('moves its query versions on, but only when it changes', () {
      final e = world.createEntityWithComponents([Health(1)]);
      final before = world.queryVersion([Health]);
      e.isActive = true; // already on
      expect(world.queryVersion([Health]), before);
      e.isActive = false;
      expect(world.queryVersion([Health]), isNot(before));
    });

    test('a switched-off entity does not move', () {
      world.addSystem(MovementSystem());
      final moving = world.createEntityWithComponents([
        TransformComponent(),
        VelocityComponent(velocity: Vector3(10, 0, 0)),
      ]);
      final parked = world.createEntityWithComponents([
        TransformComponent(),
        VelocityComponent(velocity: Vector3(10, 0, 0)),
      ])..isActive = false;

      world.update(1.0);

      expect(moving.getComponent<TransformComponent>()!.position.x, 10);
      expect(parked.getComponent<TransformComponent>()!.position.x, 0);
    });

    test('an entity switched off in a scene and on again is queried', () {
      final e = world.createEntityWithComponents([Health(1)])..isActive = false;
      world.query([Health]); // cached while it is off
      e.isActive = true;
      expect(world.query([Health]), contains(e));
    });

    test('stats count switched-off entities without a scan', () {
      world.createEntity();
      final off = world.createEntity()..isActive = false;
      expect(world.stats['activeEntities'], 1);
      world.destroyEntity(off);
      expect(world.stats['activeEntities'], 1);
      expect(world.stats['totalEntities'], 1);
    });
  });

  group('ids (C2, C40)', () {
    test('are never reused, not even after destroyAllEntities', () {
      final first = world.createEntity();
      world.destroyAllEntities();
      final next = world.createEntity();
      expect(next.id, isNot(first.id));
      expect(world.isEntityAlive(first), isFalse);
      expect(world.isEntityAlive(next), isTrue);
    });

    test('a stale handle cannot destroy the live entity', () {
      final live = world.createEntityWithComponents([Health(1)], name: 'a');
      // A handle with the same id that is not the world's entity.
      final stale = Entity(live.id, name: 'a');
      world.destroyEntity(stale);
      expect(world.isEntityAlive(live), isTrue);
      expect(world.getEntity(live.id), same(live));
      expect(world.query([Health]), [live]);
    });

    test('destroying twice is harmless', () {
      final a = world.createEntityWithComponents([Health(1)]);
      final b = world.createEntityWithComponents([Health(2)]);
      world.destroyEntity(a);
      world.destroyEntity(a);
      expect(world.entities, [b]);
      expect(world.query([Health]), [b]);
    });

    test('a destroyed handle reads as dead and switched off', () {
      final a = world.createEntity();
      final b = world.createEntity();
      world.destroyEntity(a);
      world.destroyAllEntities();
      for (final e in [a, b]) {
        expect(e.isAlive, isFalse);
        expect(e.isActive, isFalse);
      }
    });
  });

  group('components are detached on every way out (C18)', () {
    test('destroyEntity', () {
      final log = <String>[];
      final e = world.createEntityWithComponents([Watched(log)]);
      log.clear();
      world.destroyEntity(e);
      expect(log, ['detach w']);
    });

    test('destroyAllEntities and dispose', () {
      final log = <String>[];
      world.createEntityWithComponents([Watched(log, 'a')]);
      world.destroyAllEntities();
      world.createEntityWithComponents([Watched(log, 'b')]);
      log.clear();
      world.dispose();
      expect(log, ['detach b']);
    });

    test('a component replaced by another of its type', () {
      final log = <String>[];
      final e = world.createEntity()..addComponent(Watched(log, 'old'));
      e.addComponent(Watched(log, 'new'));
      expect(log, ['attach old', 'detach old', 'attach new']);
      expect(e.getComponent<Watched>()!.label, 'new');
    });

    test('but not one put back as it was', () {
      final log = <String>[];
      final w = Watched(log);
      final e = world.createEntity()..addComponent(w);
      e.addComponent(w);
      expect(log, isNot(contains('detach w')));
    });

    test('a batch with two of one type keeps the later, attached once', () {
      final log = <String>[];
      final e = world.createEntityWithComponents([
        Watched(log, 'a'),
        Watched(log, 'b'),
      ]);
      expect(e.getComponent<Watched>()!.label, 'b');
      expect(log, ['attach b']);
    });
  });

  group('destroying a hierarchy (A21)', () {
    late Entity root, child, grandchild;
    setUp(() {
      root = world.createEntityWithComponents([Health(0)], name: 'root');
      child = world.createEntityWithComponents([Health(1)], name: 'child');
      grandchild = world.createEntityWithComponents([Health(2)], name: 'gc');
      link(root, child);
      link(child, grandchild);
    });

    test('takes everything under the entity by default', () {
      world.destroyEntity(root);
      expect(world.entities, isEmpty);
      expect(world.query([Health]), isEmpty);
      expect([root, child, grandchild].any((e) => e.isAlive), isFalse);
    });

    test('with withChildren: false, cuts the children loose instead', () {
      world.destroyEntity(root, withChildren: false);
      expect(root.isAlive, isFalse);
      expect(child.isAlive, isTrue);
      expect(child.getComponent<ParentComponent>()!.parentId, isNull);
      // Its own children stay its own.
      expect(grandchild.getComponent<ParentComponent>()!.parentId, child.id);
    });

    test('leaves no dead id in the parent', () {
      world.destroyEntity(child);
      expect(root.getComponent<ChildrenComponent>()!.childIds, isEmpty);
      expect(grandchild.isAlive, isFalse);
      expect(root.isAlive, isTrue);
    });

    test('spares a listed child whose link names another parent', () {
      final other = world.createEntity(name: 'other');
      final adopted = world.createEntity(name: 'adopted');
      link(other, adopted);
      // Listed under root as well, but its own link says `other`.
      root.getComponent<ChildrenComponent>()!.addChild(adopted.id);
      world.destroyEntity(root);
      expect(adopted.isAlive, isTrue);
    });

    test('copes with a component that destroys a sibling as it goes', () {
      final sibling = world.createEntity()..isActive = false;
      link(root, sibling);
      // Destroyed before the sibling (children first, deepest first).
      grandchild.addComponent(_Destroys(world, sibling));
      world.destroyEntity(root);
      expect(world.entityCount, 0);
      expect(world.stats['activeEntities'], 0);
    });

    test('through the command buffer too', () {
      world.commands.destroy(root);
      world.commands.flush();
      expect(grandchild.isAlive, isFalse);
    });
  });

  group('the command buffer runs in the order it was told (C19)', () {
    test('remove then add ends with the new component', () {
      final e = world.createEntityWithComponents([Health(1)]);
      world.commands
        ..removeComponent<Health>(e)
        ..addComponent(e, Health(2));
      world.commands.flush();
      expect(e.getComponent<Health>()?.value, 2);
    });

    test('add then remove ends with none', () {
      final e = world.createEntity();
      world.commands
        ..addComponent(e, Health(2))
        ..removeComponent<Health>(e);
      world.commands.flush();
      expect(e.hasComponent<Health>(), isFalse);
    });

    test('a command on an entity destroyed before it is skipped', () {
      final e = world.createEntity();
      world.commands
        ..destroy(e)
        ..addComponent(e, Health(1));
      expect(() => world.commands.flush(), returnsNormally);
      expect(e.hasComponent<Health>(), isFalse);
    });

    test('commands queued while flushing run in the same flush', () {
      final e = world.createEntity();
      world.commands.addComponent(e, _Queues(world, Health(3)));
      world.commands.flush();
      expect(e.getComponent<Health>()?.value, 3);
      expect(world.commands.isNotEmpty, isFalse);
    });
  });

  group('names (C20, P14)', () {
    test('a name target skips a switched-off entity for a switched-on one', () {
      world.createEntity(name: 'Door').isActive = false;
      final open = world.createEntity(name: 'Door');
      expect(const EntityTarget.name('Door').resolve(world, null), open);
      expect(
        const EntityTarget.name(
          'Door',
        ).resolve(world, null, includeInactive: true),
        isNot(open),
      );
    });

    test('findEntityByName follows renames, oldest first', () {
      final a = world.createEntity(name: 'a');
      final b = world.createEntity(name: 'b');
      expect(world.findEntityByName('a'), a);
      a.name = 'x';
      expect(world.findEntityByName('a'), isNull);
      expect(world.findEntityByName('x'), a);
      b.name = 'x';
      expect(world.findEntityByName('x'), a); // a is older
      a.name = null;
      expect(world.findEntityByName('x'), b);
      world.destroyEntity(b);
      expect(world.findEntityByName('x'), isNull);
    });

    test('findEntityByName can pass switched-off entities by', () {
      final off = world.createEntity(name: 'n')..isActive = false;
      final on = world.createEntity(name: 'n');
      expect(world.findEntityByName('n'), off);
      expect(world.findEntityByName('n', includeInactive: false), on);
    });
  });

  group('the query cache (P7, W9)', () {
    test('an unrelated change keeps a cached result', () {
      world.createEntityWithComponents([Health(1)]);
      final health = world.query([Health]);
      world.createEntityWithComponents([Speed()]);
      expect(world.query([Health]), same(health));
    });

    test('finds entities in archetypes made after it was cached', () {
      final a = world.createEntityWithComponents([Health(1)]);
      expect(world.query([Health]), [a]);
      final b = world.createEntityWithComponents([Health(2), Speed()]);
      expect(world.query([Health]), [a, b]);
      expect(world.queryArchetypes([Health]).length, 2);
    });

    test('keys that collide never return another query', () {
      final speedy = world.createEntityWithComponents([Speed()]);
      // XOR hashing gives [Health, Health] the key of [] — the query for
      // everything with components.
      expect(world.query(const []), [speedy]);
      expect(world.query(const [Health, Health]), isEmpty);
    });

    test('types with the same name keep apart (P24)', () {
      final ours = world.createEntityWithComponents([Health(1)]);
      final theirs = world.createEntityWithComponents([twin.Health(2)]);
      final both = world.createEntity()
        ..addComponent(Health(3))
        ..addComponent(twin.Health(4));
      expect(world.query([Health]), [ours, both]);
      expect(world.query([twin.Health]), [theirs, both]);
      expect(both.getComponent<twin.Health>()!.value, 4);
      both.removeComponent<Health>();
      expect(world.query([Health]), [ours]);
    });

    test('rows keep their order through migrations', () {
      final a = world.createEntityWithComponents([Health(1)]);
      final b = world.createEntityWithComponents([Health(2)]);
      final c = world.createEntityWithComponents([Health(3)]);
      // Replacing moves the entity to the end, as it always has.
      a.addComponent(Health(4));
      expect(world.query([Health]), [c, b, a]);
      b.addComponent(Marker());
      b.removeComponent<Marker>();
      expect(world.query([Health]), [c, a, b]);
    });

    test('an archetype\'s type set cannot be changed from outside (A33)', () {
      world.createEntityWithComponents([Health(1)]);
      final archetype = world.queryArchetypes([Health]).single;
      expect(() => archetype.types.add(Speed), throwsUnsupportedError);
      expect(archetype.entityAt(0).getComponent<Health>()!.value, 1);
    });
  });

  group('World.entities (P35)', () {
    test('is reused until something is created or destroyed', () {
      final a = world.createEntity();
      final first = world.entities;
      expect(world.entities, same(first));
      expect(world.entityCount, 1);
      final b = world.createEntity();
      expect(world.entities, isNot(same(first)));
      expect(first, [a]); // a snapshot: never changed after it was given
      expect(world.entities, [a, b]);
      expect(world.entityCount, 2);
    });

    test('a world signal takes the list only when it is read', () {
      final signal = WorldSignal(world);
      addTearDown(signal.dispose);
      var heard = 0;
      signal.entities.addListener(() => heard++);
      for (var i = 0; i < 3; i++) {
        signal.notifyEntityCreated(world.createEntity());
      }
      expect(heard, 3);
      expect(signal.entityCount.value, 3);
      expect(signal.entities.value, same(world.entities));
    });
  });
}

/// Queues [next] onto its entity when it is attached.
class _Queues extends Component {
  _Queues(this.world, this.next);
  final World world;
  final Component next;

  @override
  void onAttach(EntityId entityId) {
    world.commands.addComponent(world.getEntity(entityId)!, next);
  }
}

/// Destroys [other] when it is detached.
class _Destroys extends Component {
  _Destroys(this.world, this.other);
  final World world;
  final Entity other;

  @override
  void onDetach(EntityId entityId) => world.destroyEntity(other);
}
