// Services a game opts into: started with the engine, stopped with it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Recorder extends EngineService {
  _Recorder(this.name, this.log, {this.failStart = false, this.slowStop});
  final String name;
  final List<String> log;
  final bool failStart;
  final Completer<void>? slowStop;
  ServiceContext? context;

  @override
  Future<void> start(ServiceContext context) async {
    log.add('start $name');
    if (failStart) throw StateError('$name will not start');
    this.context = context;
    // The world exists by now, and its bus is the engine's.
    context.events.fire(_Hello(name));
  }

  @override
  Future<void> stop() async {
    log.add('stop $name');
    await slowStop?.future;
    log.add('stopped $name');
  }
}

class _Other extends _Recorder {
  _Other(super.name, super.log, {super.failStart});
}

class _Hello extends GameEvent {
  _Hello(this.name);
  final String name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'started in order as the engine initializes, stopped in reverse',
    () async {
      final log = <String>[];
      final a = _Recorder('a', log);
      final b = _Other('b', log);
      final engine = Engine(config: EngineConfig(services: [a, b]));
      await engine.initialize();
      expect(log, ['start a', 'start b']);
      expect(engine.service<_Recorder>(), same(a));
      expect(engine.service<_Other>(), same(b));
      expect(a.context!.engine, same(engine));

      log.clear();
      await engine.dispose();
      expect(log, ['stop b', 'stop a', 'stopped b', 'stopped a']);
    },
  );

  test('a service the engine lacks says how to add it', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    expect(engine.maybeService<_Recorder>(), isNull);
    expect(
      () => engine.service<_Recorder>(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('No _Recorder'), contains('EngineConfig(services')),
        ),
      ),
    );
  });

  test('added late, it starts at once; removed, it stops', () async {
    final log = <String>[];
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final late = _Recorder('late', log);
    await engine.services.add(late);
    expect(log, ['start late']);
    expect(engine.services.has<_Recorder>(), isTrue);
    await engine.services.remove(late);
    expect(log, ['start late', 'stop late', 'stopped late']);
    expect(engine.services.all, isEmpty);
  });

  test('added before initialize, it waits to start with the rest', () async {
    final log = <String>[];
    final engine = Engine(
      config: EngineConfig(services: [_Recorder('a', log)]),
    );
    addTearDown(engine.dispose);
    await engine.services.add(_Other('b', log));
    expect(log, isEmpty);
    await engine.initialize();
    expect(log, ['start a', 'start b']);
  });

  test('one of the same type replaces the other', () async {
    final log = <String>[];
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    await engine.services.add(_Recorder('first', log));
    final second = _Recorder('second', log);
    await engine.services.add(second);
    expect(engine.service<_Recorder>(), same(second));
    expect(log, contains('stop first'));
  });

  test('a service that fails to start fails initialize, naming it; the '
      'ones started are stopped', () async {
    final log = <String>[];
    final engine = Engine(
      config: EngineConfig(
        services: [_Recorder('a', log), _Other('b', log, failStart: true)],
      ),
    );
    addTearDown(engine.dispose);
    await expectLater(
      engine.initialize(),
      throwsA(
        isA<EngineInitException>()
            .having((e) => e.stage, 'stage', 'service:_Other')
            .having((e) => e.cause, 'cause', isA<StateError>()),
      ),
    );
    expect(log, ['start a', 'start b', 'stop a', 'stopped a']);
    expect(engine.state, EngineState.failed);
  });

  test(
    'dispose finishes the engine before a slow stop, and waits for it',
    () async {
      final log = <String>[];
      final slow = Completer<void>();
      final engine = Engine(
        config: EngineConfig(
          services: [_Recorder('slow', log, slowStop: slow)],
        ),
      );
      await engine.initialize();
      var done = false;
      final disposing = engine.dispose().then((_) => done = true);
      expect(engine.isDisposed, isTrue);
      expect(() => engine.world, throwsA(isA<EngineNotReadyError>()));
      await pumpEventQueue();
      expect(done, isFalse, reason: 'still stopping');
      slow.complete();
      await disposing;
      expect(log.last, 'stopped slow');
      expect(engine.state, EngineState.disposed);
    },
  );

  test('a disposed engine takes no more services', () async {
    final engine = Engine();
    await engine.dispose();
    expect(() => engine.services.add(_Recorder('x', [])), throwsStateError);
  });
}
