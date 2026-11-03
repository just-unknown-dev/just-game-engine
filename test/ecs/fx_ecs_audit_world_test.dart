// The ECS world's audit fixes: systems and plugins added or removed while
// they run, a stable order for equal priorities, components listed safely
// while they change, a command batch that survives a failing command,
// links let go on destroyAllEntities, copy-free event dispatch, profiling
// that can be switched off, readable profile names, and const queries.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class A extends Component {}

class B extends Component {}

class C extends Component {}

/// Logs each update under [name]; [onUpdate] runs first.
class LogSystem extends System implements FrameSystem {
  LogSystem(this.log, this.name, {int priority = 0, this.onUpdate}) {
    this.priority = priority;
  }

  final List<String> log;
  final String name;
  void Function(LogSystem self)? onUpdate;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    onUpdate?.call(this);
    log.add(name);
  }

  @override
  void frame(double deltaTime, double alpha) => log.add('frame $name');

  @override
  void render(Canvas canvas, Size size) => log.add('render $name');
}

class Ping extends GameEvent {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late List<String> log;
  setUp(() {
    world = World()..initialize();
    log = [];
  });
  tearDown(() => world.dispose());

  group('systems changed while the systems run (C4)', () {
    test('a one-shot system removes itself', () {
      world.addSystem(
        LogSystem(log, 'once', priority: 10, onUpdate: world.removeSystem),
      );
      world.addSystem(LogSystem(log, 'always'));
      world.update(0.016);
      world.update(0.016);
      expect(log, ['once', 'always', 'always']);
      expect(world.systems.map((s) => (s as LogSystem).name), ['always']);
    });

    test('a level switch clears the systems and adds new ones', () {
      world.addSystem(
        LogSystem(
          log,
          'switcher',
          priority: 10,
          onUpdate: (_) {
            world.clearSystems();
            world.addSystem(LogSystem(log, 'next level'));
          },
        ),
      );
      world.addSystem(LogSystem(log, 'old level'));
      world.update(0.016);
      expect(log, ['switcher'], reason: 'the old level is gone at once');
      log.clear();
      world.update(0.016);
      expect(log, ['next level']);
    });

    test('one removed before its turn does not run; one added waits', () {
      final late = LogSystem(log, 'late');
      world.addSystem(
        LogSystem(
          log,
          'first',
          priority: 10,
          onUpdate: (self) {
            world.removeSystem(late);
            world.addSystem(LogSystem(log, 'added'));
            self.onUpdate = null;
          },
        ),
      );
      world.addSystem(late);
      world.update(0.016);
      expect(log, ['first']);
      log.clear();
      world.update(0.016);
      expect(log, ['first', 'added']);
    });

    test('frame and render walk safely too', () {
      final a = LogSystem(log, 'a', priority: 2);
      final b = LogSystem(log, 'b', priority: 1);
      world
        ..addSystem(a)
        ..addSystem(b);
      // A FrameSystem that removes another mid-frame.
      world.addSystem(_FrameRemover(world, b)..priority = 5);
      world.frame(0.016, 1);
      expect(log, ['frame a']);
      log.clear();
      final recorder = PictureRecorder();
      world.render(Canvas(recorder), const Size(10, 10));
      recorder.endRecording();
      expect(log, ['render a']);
    });

    test('adding a system twice does nothing more', () {
      final a = LogSystem(log, 'a');
      world
        ..addSystem(a)
        ..addSystem(a);
      world.update(0.016);
      expect(log, ['a']);
    });
  });

  test('equal priorities keep the order they were added in (C5)', () {
    final names = [for (var i = 0; i < 50; i++) 's$i'];
    for (final name in names) {
      world.addSystem(LogSystem(log, name));
    }
    world.addSystem(LogSystem(log, 'high', priority: 1));
    world.addSystem(LogSystem(log, 'low', priority: -1));
    world.update(0.016);
    expect(log, ['high', ...names, 'low']);

    log.clear();
    world.sortSystems();
    world.update(0.016);
    expect(log, ['high', ...names, 'low']);
  });

  test(
    'walking components while the entity changes lists what it had (C9)',
    () {
      final a1 = A(), b1 = B();
      final e1 = world.createEntityWithComponents([a1, b1]);
      // Another entity of the same archetype: removing from e1 swaps it into
      // e1's old row.
      world.createEntityWithComponents([A(), B()]);
      final seen = <Component>[];
      for (final component in e1.components) {
        seen.add(component);
        if (component is A) e1.removeComponent<B>();
      }
      expect(seen, [a1, b1]);
      expect(e1.components, [a1]);

      final c = C();
      final again = <Component>[];
      for (final component in e1.components) {
        again.add(component);
        e1.addComponent(c);
      }
      expect(again, [a1]);
      expect(e1.components, [a1, c]);
      expect(identical(e1.components, e1.components), isTrue);
    },
  );

  test('a command that throws does not drop the rest of the batch (C13)', () {
    final e = world.createEntity();
    world.commands
      ..addComponent(e, A())
      ..create([_Throws()])
      ..addComponent(e, B())
      ..create([C()]);
    expect(world.commands.flush, throwsA(isA<StateError>()));
    expect(e.hasComponent<A>(), isTrue);
    expect(e.hasComponent<B>(), isTrue);
    expect(world.query([C]), hasLength(1));
    expect(world.commands.isNotEmpty, isFalse);
  });

  test('destroyAllEntities lets go of every parent link (C17)', () {
    final parent = world.createEntity();
    final child = world.createEntity();
    final link = ParentComponent(parentId: parent.id);
    child.addComponent(link);
    world.destroyAllEntities();

    final stranger = world.createEntity();
    link.parentId = stranger.id;
    expect(stranger.hasComponent<ChildrenComponent>(), isFalse);
  });

  group('event bus (P8)', () {
    test('a listener cancelled by an earlier one is not called', () {
      final calls = <String>[];
      late EventSubscription second;
      world.events.on<Ping>((_) {
        calls.add('first');
        second.cancel();
      });
      second = world.events.on<Ping>((_) => calls.add('second'));
      world.events.fire(Ping());
      world.events.fire(Ping());
      expect(calls, ['first', 'first']);
    });

    test('a listener added during dispatch hears the next event', () {
      final calls = <String>[];
      var added = false;
      world.events.on<Ping>((_) {
        calls.add('first');
        if (!added) {
          added = true;
          world.events.on<Ping>((_) => calls.add('late'));
        }
      });
      world.events.fire(Ping());
      expect(calls, ['first']);
      world.events.fire(Ping());
      expect(calls, ['first', 'first', 'late']);
    });

    test('cancelling twice, or after clear, is safe', () {
      final sub = world.events.on<Ping>((_) {});
      world.events.clear();
      sub.cancel();
      sub.cancel();
      world.events.fire(Ping());
    });
  });

  group('profiling (P10, W6)', () {
    test('is on outside release, and times each system by profile name', () {
      expect(world.profiling, isTrue);
      world.addSystem(_Named());
      world.update(0.016);
      final times = world.stats['systemTimesMs'] as Map<String, double>;
      expect(times.keys, contains('Readable'));
    });

    test('switched off, nothing is timed', () {
      world.profiling = false;
      world.addSystem(_Named());
      world.update(0.016);
      expect(world.stats['systemTimesMs'], isEmpty);
      expect(world.stats['lastUpdateMs'], 0.0);
    });

    test('the system manager times tasks only while profiling', () {
      final manager = SystemManager();
      var ran = 0;
      manager.registerUpdateTask('task', (_) => ran++);
      manager.runUpdateCycle(0.016);
      expect(manager.lastTaskTimesMs.keys, ['task']);
      expect(manager.schedulerStats['updateTaskCount'], 1);
      manager.profiling = false;
      manager.runUpdateCycle(0.016);
      expect(ran, 2);
      expect(manager.lastTaskTimesMs, isEmpty);
      expect(manager.lastFrameMs, 0.0);
    });
  });

  test('the engine\'s systems ask for const queries (P11)', () {
    for (final system in <System>[
      MovementSystem(),
      RenderSystem(),
      HealthSystem(),
      LifetimeSystem(),
    ]) {
      expect(
        identical(system.requiredComponents, system.requiredComponents),
        isTrue,
        reason: '${system.runtimeType}',
      );
    }
  });

  test('children of what a frame system moved follow in the frame (A7)', () {
    final parent = world.createEntityWithComponents([TransformComponent()]);
    final child = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 0, 0)),
    ]);
    child.addComponent(ParentComponent(parentId: parent.id));
    world.update(0.016);
    world.addSystem(_FrameMover(parent));
    world.frame(0.016, 1);
    expect(child.getComponent<TransformComponent>()!.position.x, 15);
  });

  group('plugins changed while they run (C4)', () {
    test('a plugin unregisters itself, and another registers one', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      final host = PluginHost(engine);
      final calls = <String>[];
      await host.register(_Plugin('a', calls, (p) => host.unregister('a')));
      await host.register(
        _Plugin('b', calls, (p) {
          if (host.byId('c') == null) {
            host.register(_Plugin('c', calls, null));
          }
        }),
      );
      host.update(0.016);
      expect(calls, ['a', 'b']);
      calls.clear();
      host.update(0.016);
      expect(calls, ['b', 'c']);
      calls.clear();
      final recorder = PictureRecorder();
      host.renderOverlay(Canvas(recorder), const Size(10, 10));
      recorder.endRecording();
      expect(calls, ['overlay b', 'overlay c']);
      host.detachAll();
      expect(host.all, isEmpty);
    });
  });
}

class _Throws extends Component {
  @override
  void onAttach(EntityId entityId) => throw StateError('boom');
}

class _Named extends System {
  @override
  String get profileName => 'Readable';

  @override
  List<Type> get requiredComponents => const [];
}

class _FrameRemover extends System implements FrameSystem {
  _FrameRemover(this.world2, this.victim);
  final World world2;
  final System victim;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void frame(double deltaTime, double alpha) => world2.removeSystem(victim);
}

class _FrameMover extends System implements FrameSystem {
  _FrameMover(this.target);
  final Entity target;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void frame(double deltaTime, double alpha) =>
      target.getComponent<TransformComponent>()!.position.x += 5;
}

class _Plugin extends EnginePlugin {
  _Plugin(this.id, this.calls, this.onUpdate);

  @override
  final String id;
  final List<String> calls;
  final void Function(_Plugin self)? onUpdate;

  @override
  void update(double dt) {
    calls.add(id);
    onUpdate?.call(this);
  }

  @override
  void renderOverlay(Canvas canvas, Size size) => calls.add('overlay $id');
}
