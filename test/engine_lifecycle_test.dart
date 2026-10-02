// An engine's life: initialize, run, fail and retry, dispose for good.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// An audio backend that only counts how often it is started.
class _CountingBackend implements AudioBackend {
  int starts = 0;

  @override
  Future<bool> initialize() async {
    starts++;
    return false; // Not attached: nothing else is asked of it.
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Recorder implements ContextExtension {
  _Recorder(this.installs);
  final List<String> installs;
  @override
  String get id => 'recorder';
  @override
  void install(EngineContext context) => installs.add(id);
}

class _Probe extends System {
  _Probe(this.calls);
  final List<String> calls;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void onRemovedFromWorld() => calls.add('world removed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'states: uninitialized → initialized → running → paused → disposed',
    () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      expect(engine.state, EngineState.uninitialized);
      expect(engine.isInitialized, isFalse);

      final init = engine.initialize();
      expect(engine.state, EngineState.initializing);
      expect(engine.isInitialized, isFalse);
      expect(engine.initialize(), same(init), reason: 'no double initialize');
      await init;
      expect(engine.state, EngineState.initialized);

      engine.start();
      expect(engine.isRunning, isTrue);
      engine.pause();
      expect(engine.isPaused, isTrue);
      engine.pause(); // Lenient: a menu may ask twice.
      engine.resume();
      engine.stop();
      expect(engine.state, EngineState.initialized);

      await engine.dispose();
      expect(engine.state, EngineState.disposed);
      expect(engine.isDisposed, isTrue);
    },
  );

  test('initialize on an initialized engine, or start in the wrong state, '
      'throws', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.start, throwsStateError, reason: 'not initialized');
    await engine.initialize();
    expect(engine.initialize, throwsStateError);
    engine.start();
    expect(engine.start, throwsStateError, reason: 'already running');
  });

  test('subsystems before initialize, or after dispose, say why', () async {
    final engine = Engine();
    expect(
      () => engine.world,
      throwsA(
        isA<EngineNotReadyError>()
            .having((e) => e.member, 'member', 'world')
            .having((e) => e.state, 'state', EngineState.uninitialized)
            .having((e) => e.message, 'message', contains('initialize()')),
      ),
    );
    await engine.initialize();
    expect(engine.world, isNotNull);
    await engine.dispose();
    expect(
      () => engine.physics,
      throwsA(
        isA<EngineNotReadyError>().having(
          (e) => e.message,
          'message',
          contains('create a new Engine()'),
        ),
      ),
    );
    expect(engine.subsystem<PhysicsEngine>(), isNull);
    expect(engine.performanceStats['scheduler'], isEmpty);
  });

  test('a disposed engine cannot be initialized or started again', () async {
    final engine = Engine();
    await engine.initialize();
    await engine.dispose();
    expect(
      engine.initialize,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('create a new Engine()'),
        ),
      ),
    );
    expect(engine.start, throwsStateError);
    await engine.dispose(); // A no-op.
    expect(engine.state, EngineState.disposed);
  });

  test(
    'a failed initialize undoes what it built, and may be retried',
    () async {
      final engine = Engine(
        config: EngineConfig(
          createRendering: () => throw StateError('no renderer here'),
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.initialize(),
        throwsA(
          isA<EngineInitException>()
              .having((e) => e.stage, 'stage', 'rendering')
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
      expect(engine.state, EngineState.failed);
      expect(engine.lastError!.stage, 'rendering');
      expect(
        () => engine.physics,
        throwsA(isA<EngineNotReadyError>()),
        reason: 'what was built before the failure was undone',
      );

      await engine.initialize(config: const EngineConfig());
      expect(engine.isInitialized, isTrue);
      expect(engine.lastError, isNull);
    },
  );

  test('dispose after a failed initialize finishes cleanly', () async {
    final engine = Engine(
      config: EngineConfig(createRendering: () => throw StateError('boom')),
    );
    await expectLater(engine.initialize(), throwsA(isA<EngineInitException>()));
    await engine.dispose();
    expect(engine.state, EngineState.disposed);
  });

  test('dispose during initialize waits for it, then disposes', () async {
    final engine = Engine();
    final init = engine.initialize();
    final disposed = engine.dispose();
    await init;
    await disposed;
    expect(engine.state, EngineState.disposed);
  });

  test(
    'the world goes first, while physics and rendering still live',
    () async {
      final engine = Engine();
      await engine.initialize();
      final calls = <String>[];
      final probe = _Probe(calls);
      engine.world.addSystem(probe);
      final physics = engine.physics;
      await engine.dispose();
      expect(calls, ['world removed']);
      expect(() => physics.update(1 / 60), returnsNormally);
    },
  );

  test('layers and terminal are disposed with the engine', () async {
    final engine = Engine();
    await engine.initialize();
    await engine.dispose();
    expect(() => engine.layers.addListener(() {}), throwsFlutterError);
    expect(() => engine.terminal.addListener(() {}), throwsFlutterError);
  });

  test('an engine owns the context it made, not one it was given', () async {
    final own = Engine();
    await own.dispose();
    expect(own.context.isDisposed, isTrue);

    final shared = EngineContext();
    addTearDown(shared.dispose);
    final guest = Engine(context: shared);
    await guest.initialize();
    expect(guest.world.context, same(shared));
    await guest.dispose();
    expect(shared.isDisposed, isFalse);
  });

  test('two engines are independent', () async {
    final a = Engine();
    final b = Engine();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.initialize();
    await b.initialize();
    a.world.createEntity(name: 'only in a');
    expect(b.world.findEntityByName('only in a'), isNull);
    expect(a.physics, isNot(same(b.physics)));
    await a.dispose();
    expect(b.isInitialized, isTrue, reason: "a's disposal leaves b alone");
    expect(b.world.entityCount, 0);
  });

  test("the config's extensions are installed as the engine is made", () {
    final installs = <String>[];
    final engine = Engine(
      config: EngineConfig(extensions: [_Recorder(installs)]),
    );
    addTearDown(engine.dispose);
    expect(installs, ['recorder']);
    expect(engine.context.isInstalled('recorder'), isTrue);
  });

  group('audio', () {
    test('starts in initialize by default (off the web)', () async {
      final backend = _CountingBackend();
      final engine = Engine(
        config: EngineConfig(
          createAudio: () => AudioEngine.withBackend(backend),
        ),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(backend.starts, 1);
    });

    test('deferred, it starts at the first pointer press', () async {
      final backend = _CountingBackend();
      final engine = Engine(
        config: EngineConfig(
          createAudio: () => AudioEngine.withBackend(backend),
          deferAudioUntilInput: true,
        ),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(backend.starts, 0);

      GestureBinding.instance.pointerRouter.route(
        const PointerDownEvent(position: Offset(4, 4)),
      );
      await pumpEventQueue();
      expect(backend.starts, 1);

      GestureBinding.instance.pointerRouter.route(
        const PointerDownEvent(position: Offset(4, 4)),
      );
      await pumpEventQueue();
      expect(backend.starts, 1, reason: 'once');
    });

    test('a deferred start stops waiting when the engine goes', () async {
      final backend = _CountingBackend();
      final engine = Engine(
        config: EngineConfig(
          createAudio: () => AudioEngine.withBackend(backend),
          deferAudioUntilInput: true,
        ),
      );
      await engine.initialize();
      await engine.dispose();
      GestureBinding.instance.pointerRouter.route(
        const PointerDownEvent(position: Offset(4, 4)),
      );
      await pumpEventQueue();
      expect(backend.starts, 0);
    });
  });
}
