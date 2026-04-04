import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

// ── Minimal concrete components for testing ─────────────────────────────────

class HealthComponent extends Component {
  double hp;
  HealthComponent(this.hp);
}

class SpeedComponent extends Component {
  double speed;
  SpeedComponent(this.speed);
}

class TagComponent extends Component {
  final String tag;
  TagComponent(this.tag);
}

// ── Minimal concrete system for testing ─────────────────────────────────────

class CountingSystem extends System {
  int updateCount = 0;
  @override
  int get priority => 0;

  @override
  List<Type> get requiredComponents => [];

  @override
  void update(double dt) => updateCount++;
}

// ── Events for EventBus tests ────────────────────────────────────────────────

class DamageEvent extends GameEvent {
  final double amount;
  DamageEvent(this.amount);
}

class HealEvent extends GameEvent {
  final double amount;
  HealEvent(this.amount);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── World lifecycle ────────────────────────────────────────────────────────

  group('World — lifecycle', () {
    late World world;
    setUp(() => world = World());

    test('initializes once', () {
      expect(world.entities, isEmpty);
      world.initialize();
      world.initialize(); // second call is a no-op
      expect(world.entities, isEmpty);
    });

    test('disposes cleanly', () {
      world.initialize();
      final e = world.createEntity();
      e.addComponent(HealthComponent(10));
      world.dispose();
      expect(world.entities, isEmpty);
    });
  });

  // ── Entity creation / destruction ─────────────────────────────────────────

  group('World — entity CRUD', () {
    late World world;
    setUp(() {
      world = World();
      world.initialize();
    });

    test('createEntity returns unique IDs', () {
      final a = world.createEntity();
      final b = world.createEntity();
      expect(a.id, isNot(equals(b.id)));
    });

    test('createEntity with name', () {
      final e = world.createEntity(name: 'player');
      expect(e.name, 'player');
    });

    test('isEntityAlive returns true for live entity', () {
      final e = world.createEntity();
      expect(world.isEntityAlive(e), isTrue);
    });

    test('isEntityAlive returns false after destroy', () {
      final e = world.createEntity();
      world.destroyEntity(e);
      expect(world.isEntityAlive(e), isFalse);
    });

    test('destroyEntity removes from entity list', () {
      final e = world.createEntity();
      world.destroyEntity(e);
      expect(world.entities, isNot(contains(e)));
    });

    test('destroyAllEntities clears world', () {
      for (int i = 0; i < 5; i++) {
        world.createEntity();
      }
      expect(world.entities.length, 5);
      world.destroyAllEntities();
      expect(world.entities, isEmpty);
    });

    test('findEntityByName returns correct entity', () {
      world.createEntity(name: 'hero');
      world.createEntity(name: 'enemy');
      final found = world.findEntityByName('enemy');
      expect(found?.name, 'enemy');
    });

    test('findEntityByName returns null for unknown name', () {
      expect(world.findEntityByName('nobody'), isNull);
    });

    test('getEntity by ID returns correct entity', () {
      final e = world.createEntity();
      expect(world.getEntity(e.id), same(e));
    });
  });

  // ── Component add / remove ─────────────────────────────────────────────────

  group('World — components', () {
    late World world;
    late Entity entity;

    setUp(() {
      world = World();
      world.initialize();
      entity = world.createEntity();
    });

    test('addComponent stores component', () {
      entity.addComponent(HealthComponent(100));
      expect(entity.getComponent<HealthComponent>()?.hp, 100.0);
    });

    test('hasComponent returns true after add', () {
      entity.addComponent(HealthComponent(50));
      expect(entity.hasComponent<HealthComponent>(), isTrue);
    });

    test('hasComponent returns false before add', () {
      expect(entity.hasComponent<HealthComponent>(), isFalse);
    });

    test('removeComponent removes it', () {
      entity.addComponent(HealthComponent(50));
      entity.removeComponent<HealthComponent>();
      expect(entity.hasComponent<HealthComponent>(), isFalse);
    });

    test('multiple components coexist', () {
      entity.addComponent(HealthComponent(80));
      entity.addComponent(SpeedComponent(5.0));
      expect(entity.hasComponent<HealthComponent>(), isTrue);
      expect(entity.hasComponent<SpeedComponent>(), isTrue);
    });

    test('removing one component keeps others', () {
      entity.addComponent(HealthComponent(80));
      entity.addComponent(SpeedComponent(5.0));
      entity.removeComponent<HealthComponent>();
      expect(entity.hasComponent<HealthComponent>(), isFalse);
      expect(entity.hasComponent<SpeedComponent>(), isTrue);
    });

    test('createEntityWithComponents batch creates correctly', () {
      final e = world.createEntityWithComponents([
        HealthComponent(30),
        SpeedComponent(2.0),
      ]);
      expect(e.hasComponent<HealthComponent>(), isTrue);
      expect(e.hasComponent<SpeedComponent>(), isTrue);
    });

    test('onAttach called when component is added', () {
      var attached = false;
      final comp = _LifecycleComponent(onAttachCb: (_) => attached = true);
      entity.addComponent(comp);
      expect(attached, isTrue);
    });

    test('onDetach called when component is removed', () {
      var detached = false;
      final comp = _LifecycleComponent(onDetachCb: (_) => detached = true);
      entity.addComponent(comp);
      entity.removeComponent<_LifecycleComponent>();
      expect(detached, isTrue);
    });
  });

  // ── Query ─────────────────────────────────────────────────────────────────

  group('World — query', () {
    late World world;
    setUp(() {
      world = World();
      world.initialize();
    });

    test('query returns entities matching a single type', () {
      final e1 = world.createEntityWithComponents([HealthComponent(10)]);
      world.createEntityWithComponents([SpeedComponent(1)]);
      final results = world.query([HealthComponent]);
      expect(results, contains(e1));
      expect(results.length, 1);
    });

    test('query returns entities matching multiple types', () {
      final e1 = world.createEntityWithComponents([
        HealthComponent(10),
        SpeedComponent(5),
      ]);
      world.createEntityWithComponents([HealthComponent(10)]);
      final results = world.query([HealthComponent, SpeedComponent]);
      expect(results, contains(e1));
      expect(results.length, 1);
    });

    test('query is empty when no match', () {
      world.createEntityWithComponents([HealthComponent(10)]);
      expect(world.query([TagComponent]), isEmpty);
    });

    test('query cache is invalidated after add/remove', () {
      final before = world.query([HealthComponent]);
      expect(before, isEmpty);

      final e = world.createEntityWithComponents([HealthComponent(5)]);
      final after = world.query([HealthComponent]);
      expect(after, contains(e));
    });

    test('query cache evicted only for relevant type', () {
      world.createEntityWithComponents([HealthComponent(1)]);

      // Prime both caches.
      final hp = world.query([HealthComponent]);
      world.query([SpeedComponent]); // prime speed cache

      // Add a SpeedComponent to a new entity — should not evict Health cache.
      final e2 = world.createEntityWithComponents([SpeedComponent(2)]);
      final hp2 = world.query([HealthComponent]);
      final spd2 = world.query([SpeedComponent]);

      expect(hp2.length, hp.length); // Health cache unchanged
      expect(spd2, contains(e2));
    });

    test('queryArchetypes returns matching archetypes', () {
      world.createEntityWithComponents([HealthComponent(1), SpeedComponent(2)]);
      world.createEntityWithComponents([HealthComponent(1)]);

      final archetypes = world.queryArchetypes([HealthComponent]).toList();
      // Both archetypes contain HealthComponent
      expect(archetypes.length, 2);
    });

    test('destroyed entity does not appear in query', () {
      final e = world.createEntityWithComponents([HealthComponent(5)]);
      world.destroyEntity(e);
      expect(world.query([HealthComponent]), isNot(contains(e)));
    });
  });

  // ── System management ─────────────────────────────────────────────────────

  group('World — systems', () {
    late World world;
    setUp(() {
      world = World();
      world.initialize();
    });

    test('addSystem registers system', () {
      final sys = CountingSystem();
      world.addSystem(sys);
      expect(world.getSystem<CountingSystem>(), same(sys));
    });

    test('removeSystem unregisters system', () {
      final sys = CountingSystem();
      world.addSystem(sys);
      world.removeSystem(sys);
      expect(world.getSystem<CountingSystem>(), isNull);
    });

    test('clearSystems removes all', () {
      world.addSystem(CountingSystem());
      world.clearSystems();
      expect(world.systems, isEmpty);
    });

    test('update calls system.update', () {
      final sys = CountingSystem();
      world.addSystem(sys);
      world.update(0.016);
      expect(sys.updateCount, 1);
    });

    test('inactive system is not updated', () {
      final sys = CountingSystem();
      world.addSystem(sys);
      sys.isActive = false;
      world.update(0.016);
      expect(sys.updateCount, 0);
    });
  });

  // ── CommandBuffer ─────────────────────────────────────────────────────────

  group('CommandBuffer', () {
    late World world;
    setUp(() {
      world = World();
      world.initialize();
    });

    test('isNotEmpty when creates are pending', () {
      expect(world.commands.isNotEmpty, isFalse);
      world.commands.create([HealthComponent(5)]);
      expect(world.commands.isNotEmpty, isTrue);
    });

    test('flush creates entity from deferred create', () {
      world.commands.create([HealthComponent(10)], name: 'cmd-entity');
      world.commands.flush();
      expect(world.findEntityByName('cmd-entity'), isNotNull);
    });

    test('flush destroys entity from deferred destroy', () {
      final e = world.createEntity(name: 'doomed');
      world.commands.destroy(e);
      world.commands.flush();
      expect(world.isEntityAlive(e), isFalse);
    });

    test('flush adds component from deferred addComponent', () {
      final e = world.createEntity();
      world.commands.addComponent(e, HealthComponent(42));
      world.commands.flush();
      expect(e.getComponent<HealthComponent>()?.hp, 42.0);
    });

    test('flush removes component from deferred removeComponent', () {
      final e = world.createEntityWithComponents([HealthComponent(10)]);
      world.commands.removeComponent<HealthComponent>(e);
      world.commands.flush();
      expect(e.hasComponent<HealthComponent>(), isFalse);
    });

    test('buffer is cleared after flush', () {
      world.commands.create([HealthComponent(1)]);
      world.commands.flush();
      expect(world.commands.isNotEmpty, isFalse);
    });

    test('deferred destroy does not crash if already destroyed', () {
      final e = world.createEntity();
      world.destroyEntity(e);
      // Deferred command on already-dead entity should be silently skipped.
      world.commands.destroy(e);
      expect(() => world.commands.flush(), returnsNormally);
    });
  });

  // ── EventBus ─────────────────────────────────────────────────────────────

  group('EventBus', () {
    late EventBus bus;
    setUp(() => bus = EventBus());

    test('on receives fired events', () {
      double received = 0;
      bus.on<DamageEvent>((e) => received = e.amount);
      bus.fire(DamageEvent(25.0));
      expect(received, 25.0);
    });

    test('multiple subscribers all receive event', () {
      int count = 0;
      bus.on<DamageEvent>((_) => count++);
      bus.on<DamageEvent>((_) => count++);
      bus.fire(DamageEvent(10.0));
      expect(count, 2);
    });

    test('subscription cancellation stops receiving', () {
      int count = 0;
      final sub = bus.on<DamageEvent>((_) => count++);
      bus.fire(DamageEvent(1.0));
      sub.cancel();
      bus.fire(DamageEvent(1.0));
      expect(count, 1);
    });

    test('cancel is idempotent', () {
      final sub = bus.on<DamageEvent>((_) {});
      sub.cancel();
      expect(() => sub.cancel(), returnsNormally);
    });

    test('different event types do not cross-fire', () {
      double damage = 0;
      double heal = 0;
      bus.on<DamageEvent>((e) => damage = e.amount);
      bus.on<HealEvent>((e) => heal = e.amount);
      bus.fire(DamageEvent(10));
      expect(damage, 10);
      expect(heal, 0);
    });

    test('fire with no subscribers is safe', () {
      expect(() => bus.fire(DamageEvent(1)), returnsNormally);
    });

    test('clear removes all listeners', () {
      int count = 0;
      bus.on<DamageEvent>((_) => count++);
      bus.clear();
      bus.fire(DamageEvent(5));
      expect(count, 0);
    });

    test('handler may cancel own subscription during dispatch', () {
      EventSubscription? sub;
      int count = 0;
      sub = bus.on<DamageEvent>((_) {
        count++;
        sub?.cancel();
      });
      bus.fire(DamageEvent(1));
      bus.fire(DamageEvent(1));
      expect(count, 1); // only fired once before cancel
    });
  });

  // ── Archetype ─────────────────────────────────────────────────────────────

  group('Archetype', () {
    test(
      'entities with same component set share archetype (queryArchetypes returns 1)',
      () {
        final world = World()..initialize();
        world.createEntityWithComponents([HealthComponent(1)]);
        world.createEntityWithComponents([HealthComponent(2)]);
        // Both entities have only HealthComponent → 1 archetype
        final archetypes = world.queryArchetypes([HealthComponent]).toList();
        expect(archetypes.length, 1);
        expect(archetypes.first.length, 2);
      },
    );

    test('different component sets produce different archetypes', () {
      final world = World()..initialize();
      world.createEntityWithComponents([HealthComponent(1)]);
      world.createEntityWithComponents([SpeedComponent(1)]);
      // Health and Speed are separate archetypes — querying each returns 1.
      expect(world.queryArchetypes([HealthComponent]).length, 1);
      expect(world.queryArchetypes([SpeedComponent]).length, 1);
    });

    test('entity moves archetype on component add — still accessible', () {
      final world = World()..initialize();
      final e = world.createEntityWithComponents([HealthComponent(1)]);
      e.addComponent(SpeedComponent(5));
      // Must remain fully functional after archetype migration.
      expect(e.hasComponent<HealthComponent>(), isTrue);
      expect(e.hasComponent<SpeedComponent>(), isTrue);
      expect(e.getComponent<HealthComponent>()?.hp, 1.0);
    });

    test('swap-and-pop does not corrupt sibling entity data', () {
      final world = World()..initialize();
      // Three entities in same archetype.
      final e1 = world.createEntityWithComponents([HealthComponent(1)]);
      final e2 = world.createEntityWithComponents([HealthComponent(2)]);
      final e3 = world.createEntityWithComponents([HealthComponent(3)]);

      // Destroy middle entity — triggers swap-and-pop.
      world.destroyEntity(e2);

      expect(e1.getComponent<HealthComponent>()?.hp, 1.0);
      expect(e3.getComponent<HealthComponent>()?.hp, 3.0);
    });
  });

  // ── EntityPrefab ──────────────────────────────────────────────────────────

  group('EntityPrefab', () {
    test('instantiate creates entity with prefab components', () {
      final world = World()..initialize();
      final prefab = EntityPrefab(
        name: 'mob',
        factories: [() => HealthComponent(50), () => SpeedComponent(3.0)],
      );

      final e = world.instantiate(prefab);
      expect(e.name, 'mob');
      expect(e.getComponent<HealthComponent>()?.hp, 50.0);
      expect(e.getComponent<SpeedComponent>()?.speed, 3.0);
    });

    test('each instantiation produces independent component instances', () {
      final world = World()..initialize();
      final prefab = EntityPrefab(factories: [() => HealthComponent(100)]);
      final e1 = world.instantiate(prefab);
      final e2 = world.instantiate(prefab);
      e1.getComponent<HealthComponent>()!.hp = 50;
      expect(e2.getComponent<HealthComponent>()?.hp, 100.0);
    });
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

class _LifecycleComponent extends Component {
  final void Function(EntityId)? onAttachCb;
  final void Function(EntityId)? onDetachCb;

  _LifecycleComponent({this.onAttachCb, this.onDetachCb});

  @override
  void onAttach(EntityId id) => onAttachCb?.call(id);

  @override
  void onDetach(EntityId id) => onDetachCb?.call(id);
}
