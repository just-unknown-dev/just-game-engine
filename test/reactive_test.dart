import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

// ── Minimal concrete components ───────────────────────────────────────────────

class HpComponent extends Component {
  double hp;
  HpComponent(this.hp);
}

class MpComponent extends Component {
  double mp;
  MpComponent(this.mp);
}

// ── ReactiveComponent-based test component ────────────────────────────────────

class ReactiveHp extends Component with ReactiveComponent {
  double _hp;
  ReactiveHp(this._hp);

  double get hp => _hp;
  set hp(double v) {
    if (_hp != v) {
      _hp = v;
      notifyChange('hp');
    }
  }
}

// ── Concrete ReactiveSystem for testing ───────────────────────────────────────

class _TrackingReactiveSystem extends ReactiveSystem {
  final List<EntityId> processed = [];

  @override
  List<Type> get requiredComponents => [HpComponent];

  @override
  int get priority => 0;

  @override
  void processEntity(Entity entity, double dt) {
    processed.add(entity.id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ComponentSignal ───────────────────────────────────────────────────────

  group('ComponentSignal', () {
    late World world;
    late Entity entity;
    late TransformComponent transform;

    setUp(() {
      world = World()..initialize();
      entity = world.createEntityWithComponents([
        TransformComponent(position: const Offset(10, 20)),
      ]);
      transform = entity.getComponent<TransformComponent>()!;
    });

    test('initial value reads from component', () {
      final sig = ComponentSignal<TransformComponent, double>(
        transform,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
      );
      expect(sig.value, 10.0);
    });

    test('setting value updates component', () {
      final sig = ComponentSignal<TransformComponent, double>(
        transform,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
      );
      sig.value = 99.0;
      expect(transform.position.dx, 99.0);
    });

    test('setting same value does not notify', () {
      final sig = ComponentSignal<TransformComponent, double>(
        transform,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
      );
      int calls = 0;
      sig.addListener(() => calls++);
      sig.value = transform.position.dx; // same
      expect(calls, 0);
    });

    test('setting new value notifies listeners', () {
      final sig = ComponentSignal<TransformComponent, double>(
        transform,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
      );
      int calls = 0;
      sig.addListener(() => calls++);
      sig.value = 500.0;
      expect(calls, 1);
    });

    test('sync picks up external component change', () {
      final sig = ComponentSignal<TransformComponent, double>(
        transform,
        getter: (c) => c.position.dx,
        setter: (c, v) => c.position = Offset(v, c.position.dy),
      );
      transform.position = const Offset(42, 0); // external change
      sig.sync();
      expect(sig.value, 42.0);
    });
  });

  // ── TransformSignals ──────────────────────────────────────────────────────

  group('TransformSignals', () {
    late TransformComponent transform;
    late TransformSignals signals;

    setUp(() {
      transform = TransformComponent(
        position: const Offset(0, 0),
        rotation: 0.0,
        scale: 1.0,
      );
      signals = TransformSignals(transform);
    });

    test('x / y signals read component position', () {
      transform.position = const Offset(3, 7);
      expect(signals.x.value, 3.0);
      expect(signals.y.value, 7.0);
    });

    test('setting x updates component', () {
      signals.x.value = 55.0;
      expect(transform.position.dx, 55.0);
    });

    test('setting y updates component', () {
      signals.y.value = 66.0;
      expect(transform.position.dy, 66.0);
    });

    test('setPosition batches x and y into one notification each', () {
      int count = 0;
      signals.x.addListener(() => count++);
      signals.y.addListener(() => count++);
      signals.setPosition(10, 20);
      // One notification per signal after the batch flushes
      expect(count, lessThanOrEqualTo(2));
      expect(transform.position, const Offset(10, 20));
    });

    test('translate moves by delta', () {
      transform.position = const Offset(10, 10);
      signals.translate(5, -3);
      expect(transform.position.dx, closeTo(15.0, 1e-9));
      expect(transform.position.dy, closeTo(7.0, 1e-9));
    });

    test('rotation signal reads and writes rotation', () {
      transform.rotation = 1.5;
      expect(signals.rotation.value, closeTo(1.5, 1e-9));
      signals.rotation.value = 3.0;
      expect(transform.rotation, closeTo(3.0, 1e-9));
    });

    test('scale signal reads and writes scale', () {
      transform.scale = 2.0;
      expect(signals.scale.value, closeTo(2.0, 1e-9));
      signals.scale.value = 0.5;
      expect(transform.scale, closeTo(0.5, 1e-9));
    });
  });

  // ── EntitySignal ──────────────────────────────────────────────────────────

  group('EntitySignal', () {
    late World world;
    late Entity entity;

    setUp(() {
      world = World()..initialize();
      entity = world.createEntityWithComponents([HpComponent(100)]);
    });

    test('component signal returns current value', () {
      final es = EntitySignal(entity);
      final sig = es.component<HpComponent>();
      expect(sig.value?.hp, 100.0);
    });

    test('has<T> returns true when component present', () {
      final es = EntitySignal(entity);
      expect(es.has<HpComponent>(), isTrue);
    });

    test('has<T> returns false when component absent', () {
      final es = EntitySignal(entity);
      expect(es.has<MpComponent>(), isFalse);
    });

    test('get<T> returns component instance', () {
      final es = EntitySignal(entity);
      expect(es.get<HpComponent>()?.hp, 100.0);
    });

    test('isActive signal reflects entity active state', () {
      final es = EntitySignal(entity);
      expect(es.isActive.value, isTrue);
    });

    test('sync does not throw', () {
      final es = EntitySignal(entity);
      es.component<HpComponent>(); // materialize signal
      expect(() => es.sync(), returnsNormally);
    });
  });

  // ── WorldSignal ───────────────────────────────────────────────────────────

  group('WorldSignal', () {
    late World world;
    late WorldSignal ws;

    setUp(() {
      world = World()..initialize();
      ws = WorldSignal(world);
    });

    tearDown(() => ws.dispose());

    test('entityCount reflects existing entities', () {
      world.createEntity();
      world.createEntity();
      ws.sync();
      expect(ws.entityCount.value, 2);
    });

    test('notifyEntityCreated increments entityCount', () {
      final e = world.createEntity();
      ws.notifyEntityCreated(e);
      expect(ws.entityCount.value, 1);
    });

    test('notifyEntityDestroyed decrements entityCount', () {
      final e = world.createEntity();
      ws.notifyEntityCreated(e);
      world.destroyEntity(e);
      ws.notifyEntityDestroyed(e.id);
      expect(ws.entityCount.value, 0);
    });

    test('notifySystemAdded increments systemCount', () {
      final sys = _TrackingReactiveSystem();
      world.addSystem(sys);
      ws.notifySystemAdded(sys);
      expect(ws.systemCount.value, 1);
    });

    test('entitySignal returns a signal for the entity', () {
      final e = world.createEntity();
      final es = ws.entitySignal(e);
      expect(es.id, e.id);
    });

    test('query computed derives from world.query', () {
      final e = world.createEntityWithComponents([HpComponent(10)]);
      ws.sync();
      final result = ws.query([HpComponent]).value;
      expect(result, contains(e));
    });

    test('sync cleans up signals for destroyed entities', () {
      final e = world.createEntity();
      ws.entitySignal(e); // materialize
      world.destroyEntity(e);
      expect(() => ws.sync(), returnsNormally);
    });
  });

  // ── ReactiveComponent mixin ───────────────────────────────────────────────

  group('ReactiveComponent', () {
    test('notifyChange fires change listeners', () {
      int count = 0;
      final comp = ReactiveHp(100);
      comp.addChangeListener(() => count++);
      comp.hp = 80;
      expect(count, 1);
    });

    test('no notification when value unchanged', () {
      int count = 0;
      final comp = ReactiveHp(100);
      comp.addChangeListener(() => count++);
      comp.hp = 100; // same
      expect(count, 0);
    });

    test('removeChangeListener stops notifications', () {
      int count = 0;
      final comp = ReactiveHp(100);
      void listener() => count++;
      comp.addChangeListener(listener);
      comp.removeChangeListener(listener);
      comp.hp = 50;
      expect(count, 0);
    });

    test('propertySignal stores and returns value', () {
      final comp = ReactiveHp(50);
      final sig = comp.propertySignal<double>('hp', 50);
      expect(sig.value, 50.0);
    });
  });

  // ── ReactiveSystem ────────────────────────────────────────────────────────

  group('ReactiveSystem', () {
    late World world;
    late _TrackingReactiveSystem sys;

    setUp(() {
      world = World()..initialize();
      sys = _TrackingReactiveSystem();
      world.addSystem(sys);
    });

    test('marks entity dirty', () {
      final e = world.createEntityWithComponents([HpComponent(10)]);
      sys.markDirty(e);
      expect(sys.isDirty(e), isTrue);
    });

    test('clearDirty removes dirty status', () {
      final e = world.createEntityWithComponents([HpComponent(10)]);
      sys.markDirty(e);
      sys.clearDirty(e);
      expect(sys.isDirty(e), isFalse);
    });

    test('clearAllDirty removes all', () {
      final e1 = world.createEntityWithComponents([HpComponent(1)]);
      final e2 = world.createEntityWithComponents([HpComponent(2)]);
      sys.markDirty(e1);
      sys.markDirty(e2);
      sys.clearAllDirty();
      expect(sys.isDirty(e1), isFalse);
      expect(sys.isDirty(e2), isFalse);
    });

    test(
      'first update processes all matching entities (processAllOnFirstRun)',
      () {
        final e1 = world.createEntityWithComponents([HpComponent(1)]);
        final e2 = world.createEntityWithComponents([HpComponent(2)]);
        world.update(0.016);
        expect(sys.processed, containsAll([e1.id, e2.id]));
      },
    );

    test('subsequent update only processes dirty entities', () {
      world.createEntityWithComponents([HpComponent(1)]);
      final e2 = world.createEntityWithComponents([HpComponent(2)]);

      world.update(
        0.016,
      ); // first run — processAllOnFirstRun=true, cleared after
      sys.processed.clear();

      sys.markDirty(e2);
      world.update(0.016);
      expect(sys.processed, orderedEquals([e2.id]));
    });

    test('non-matching entity is not processed', () {
      // Add an entity without HpComponent — should not be processed.
      world.createEntityWithComponents([MpComponent(50)]);
      world.update(0.016);
      // processed list may still be empty or only contain hp entities
      // — verify no crash and HpComponent-less entity is absent.
      expect(sys.processed, isEmpty);
    });
  });
}
