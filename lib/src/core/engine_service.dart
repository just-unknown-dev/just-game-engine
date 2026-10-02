/// Services a game opts into: started with the engine, stopped with it.
library;

import 'package:meta/meta.dart' show internal;

import '../ecs/ecs.dart';
import 'engine.dart';
import '../ecs/base/engine_context.dart';

/// Something a game adds to its engine that lives as long as the engine
/// does — achievements, a wallet, sign-in, ads (package
/// `just_game_services`), or a game's own.
///
/// Declared in `EngineConfig.services` (or added later with
/// `engine.services.add`) and found with `engine.service<T>()`:
///
/// ```dart
/// final engine = Engine(
///   config: EngineConfig(services: [MyTelemetry()]),
/// );
/// await engine.initialize();              // starts it
/// engine.service<MyTelemetry>().send('hello');
/// await engine.dispose();                 // stops it
/// ```
///
/// A service belongs to one engine.
abstract class EngineService {
  /// Starts the service, once: while the engine initializes (after its
  /// world exists, before `initialize()` completes) in the order the
  /// services were declared, or at once when added to an initialized
  /// engine. Throwing fails `initialize()` with an `EngineInitException`
  /// whose stage is `service:<Type>`.
  Future<void> start(ServiceContext context);

  /// Stops the service, once: while the engine disposes, after its plugins
  /// detach and before its world goes — services in the reverse of their
  /// start order — or when it is removed. It must not touch the world after
  /// this is called; the engine's `dispose()` completes once every `stop()`
  /// has.
  Future<void> stop();
}

/// What a started [EngineService] gets from its engine.
final class ServiceContext {
  ServiceContext._(this.engine);

  /// The engine the service runs in.
  final Engine engine;

  /// The engine's context: its registries, loaders, and the per-package
  /// state a service may keep there (`EngineContext.slot`).
  EngineContext get context => engine.context;

  /// The engine world's event bus, read on each call — never cache the
  /// world itself.
  EventBus get events => engine.world.events;
}

/// The [EngineService]s of one engine (`engine.services`), in start order.
final class ServiceHost {
  ServiceHost._(this._engine) : _context = ServiceContext._(_engine);

  final Engine _engine;
  final ServiceContext _context;
  final List<EngineService> _services = [];
  final Set<EngineService> _started = Set.identity();

  /// Every service, in start order.
  List<EngineService> get all => List.unmodifiable(_services);

  /// The service of type [T]. Throws a [StateError] that says how to add it
  /// when there is none.
  T get<T extends EngineService>() =>
      maybe<T>() ??
      (throw StateError(
        'No $T on this engine. Add it: '
        'Engine(config: EngineConfig(services: [$T()])), or '
        'await engine.services.add($T()).',
      ));

  /// The service of type [T], or null.
  T? maybe<T extends EngineService>() {
    for (final service in _services) {
      if (service is T) return service;
    }
    return null;
  }

  /// Whether a service of type [T] is here.
  bool has<T extends EngineService>() => maybe<T>() != null;

  /// Adds [service]: before the engine initializes it waits to be started
  /// with the rest; on an initialized engine it is started now. One of the
  /// same runtime type is replaced — stopped and removed — first.
  Future<void> add(EngineService service) async {
    if (_engine.isDisposed) {
      throw StateError('This Engine was disposed; create a new Engine().');
    }
    if (_services.any((s) => identical(s, service))) return;
    for (final same in [
      for (final s in _services)
        if (s.runtimeType == service.runtimeType) s,
    ]) {
      await remove(same);
    }
    _services.add(service);
    if (_engine.isInitialized) await _start(service);
  }

  /// Stops [service], if it was started, and takes it out.
  Future<void> remove(EngineService service) async {
    if (!_services.remove(service)) return;
    if (_started.remove(service)) await service.stop();
  }

  Future<void> _start(EngineService service) async {
    await service.start(_context);
    _started.add(service);
  }

  /// Starts every service not yet started, in order — those added while
  /// this runs too. What a failure throws names the service.
  Future<void> _startAll() async {
    for (var i = 0; i < _services.length; i++) {
      final service = _services[i];
      if (_started.contains(service)) continue;
      try {
        await _start(service);
      } catch (error, stack) {
        throw _ServiceStartFailure(service, error, stack);
      }
    }
  }

  /// Calls `stop()` on every started service, last first, and returns their
  /// Futures. A service that throws at once is reported and passed over.
  List<Future<void>> _stopAll() {
    final stopping = <Future<void>>[];
    for (final service in _services.reversed.toList()) {
      if (!_started.remove(service)) continue;
      try {
        stopping.add(service.stop());
      } catch (error, stack) {
        stopping.add(Future.error(error, stack));
      }
    }
    return stopping;
  }
}

/// A service's `start()` threw; carries which one.
final class _ServiceStartFailure implements Exception {
  _ServiceStartFailure(this.service, this.error, this.stack);
  final EngineService service;
  final Object error;
  final StackTrace stack;
}

/// What the engine uses of a [ServiceHost]; not part of the public API.
@internal
extension ServiceHostEngineAccess on ServiceHost {
  /// See [ServiceHost._startAll]. Throws the service's own error, wrapped
  /// so the engine can name it.
  Future<void> startAllForEngine() => _startAll();

  /// See [ServiceHost._stopAll].
  List<Future<void>> stopAllForEngine() => _stopAll();
}

/// Reads a failed start: which service, and what it threw; null for any
/// other error.
@internal
({EngineService service, Object error, StackTrace stack})? serviceFailureOf(
  Object error,
) => error is _ServiceStartFailure
    ? (service: error.service, error: error.error, stack: error.stack)
    : null;

/// Makes the host for [engine]; the engine calls this once.
@internal
ServiceHost newServiceHost(Engine engine) => ServiceHost._(engine);
