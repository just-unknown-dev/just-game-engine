# Services & plugins

_Flutter & shipping_ · Run your own code beside the engine with EngineService, observe a running engine with EnginePlugin, and add achievements, currency and more from just_game_services.

Two hooks let code live beside the game. An `EngineService` starts when the engine initializes and stops when it is disposed. An `EnginePlugin` attaches to an engine to watch or extend it and is called every frame.

## Engine services

A service implements two methods: `start(ServiceContext context)` and `stop()`. List it in `EngineConfig(services: [...])`, or add it later with `engine.services.add(service)`.

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

/// Counts the collisions the game has had, for the engine's whole life.
class CollisionCounter implements EngineService {
  int count = 0;
  EventSubscription? _subscription;

  @override
  Future<void> start(ServiceContext context) async {
    _subscription = context.events.on<CollisionEnter2DEvent>((_) => count++);
  }

  @override
  Future<void> stop() async {
    _subscription?.cancel();
    _subscription = null;
  }
}

Future<Engine> boot() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      services: [CollisionCounter()],
    ),
  );
  await engine.initialize(); // starts the service
  debugPrint('${engine.service<CollisionCounter>().count} collisions so far');
  return engine;
}
```

- **Starting.** Services start last in `initialize()`, after the world exists, in the order they are listed. List `Graphics3D` before any service that loads models as it starts; `Physics3D` starts wherever you list it. A service added to an engine that is already initialized starts at once.
- **Failing.** A `start` that throws fails `initialize()` with an `EngineInitException` whose `stage` is `service:<Type>`, and the services already started are stopped.
- **Stopping.** `dispose()` calls every `stop()`, last started first, before the world goes, and its Future completes once all of them have finished. A service must not touch the world after its `stop()` is called.
- **Context.** `ServiceContext` gives the service its `engine`, the engine's `context`, and `events`, the world's event bus. `events` is read on each call, so never cache the world itself. `engine` is a `GameEngine`: the world, context, assets, rendering and the other services. A service that needs more of its engine casts it: `context.engine as Engine`.

`engine.service<T>()` returns the service of type `T`, and throws a `StateError` that says how to add it when there is none. `engine.maybeService<T>()` returns null instead. `engine.services` also has `has<T>()`, `all` and `remove(service)`. Adding a service whose runtime type is already there stops and replaces the old one.

## Plugins

An `EnginePlugin` is for tools that observe or extend a running engine: an editor, a profiler, a replay recorder. Register it with `engine.plugins.register(plugin)`. A plugin has an `id`; registering another with the same id detaches and replaces the first.

| Member | When it is called |
|---|---|
| `attach(engine)` | Once, when the plugin is registered. |
| `update(dt)` | Once per frame, with the unscaled frame time, even while the game is paused or its time scale is zero. |
| `renderOverlay(canvas, size)` | Once per frame, in screen space, after the world has drawn. |
| `detach()` | When the plugin is unregistered, or when the engine is disposed. |

```dart
/// Logs every frame that takes longer than 1/30 s.
class SlowFrameLogger extends EnginePlugin {
  @override
  String get id => 'slow_frame_logger';

  @override
  void update(double dt) {
    if (dt > 1 / 30) {
      debugPrint('Slow frame: ${(dt * 1000).toStringAsFixed(1)} ms');
    }
  }
}

// await engine.plugins.register(SlowFrameLogger());
```

`engine.plugins` also has `unregister(id)`, `byId(id)` and `all`. Simulation belongs in systems, which run on the fixed step; a plugin sees the engine on wall-clock time.

## Achievements, currency and more

Achievements, sign-in, leaderboards, a currency wallet, an inventory and ads are services in a separate package, `just_game_services`. Nothing from it runs unless you list it.

> **Note:** `just_game_services` is not on pub.dev yet, so the dependency below will not resolve until it is published. Watch the [engine repository](https://github.com/just-unknown-dev/just-game-engine) for its release.

```yaml pubspec.yaml
dependencies:
  just_game_engine: ^2.0.0-dev.4
  just_game_services: ^0.1.0
```

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_services/just_game_services.dart';

Future<Engine> startGame() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      // Or GameServices.all() for all six.
      services: [
        AchievementManager()..define(
          Achievement(
            id: 'first_win',
            name: 'First Win',
            description: 'Beat level 1',
          ),
        ),
        CurrencyManager(),
      ],
    ),
  );
  await engine.initialize(); // starts both services
  engine.achievements.unlock('first_win');
  engine.currency.add('coins', 10); // saved to disk by default
  return engine;
}
```

`engine.achievements`, `engine.currency` and the others are extension getters from the package, and each is `engine.service<T>()` under another name: asking for one the engine was not given throws a `StateError` naming the fix. `AdsManager.initialize(consent: ...)` is still yours to call. For a real sign-in or leaderboard backend, write an `AuthProvider` or `LeaderboardProvider`.

> **Note:** Coming from 1.x, where every engine built all six: the managers' `bindWorld`, `initialize` and `dispose` are now `start` and `stop`, called by the engine. See [Migration](/docs/migration).
