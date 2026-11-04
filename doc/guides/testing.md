# Testing

_Flutter & shipping_ · Test game logic with a bare World or a headless Engine, step time yourself, and load scenes and assets without a device.

Make a new engine, or a new world, in each test and dispose it afterwards. Nothing ticks by itself in a test, because there is no `GameWidget` driving the loop: you step time yourself.

## A world on its own

For plain ECS logic, a `World()` on its own is enough, and much faster than an engine. It makes a fresh context with the ECS core's components (the transform, the parent and children links, tags) and disposes it with itself; a test that reads or writes scenes gives it the engine's too, `World(extensions: [BuiltInComponents.extension])`. Add the systems you are testing and call `world.update(1 / 60)` once per step:

```dart test/movement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('velocity moves an entity', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    world.addSystem(MovementSystem());

    final box = world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(velocity: Vector3(60, 0, 0)),
    ]);
    for (var i = 0; i < 30; i++) {
      world.update(1 / 60);
    }

    expect(
      box.getComponent<TransformComponent>()!.position.x,
      closeTo(30, 1e-9),
    );
  });
}
```

## A headless engine

When a test needs the engine's subsystems, make an engine with `DefaultSystems.headless`: every standard system except rendering and audio. Await `initialize()`, register `dispose` as a tear-down, and step its world directly.

```dart test/level_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a level loads', () async {
    final engine = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.headless),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    SceneLoader.loadString(engine.world, """
      {"version": 11, "name": "test", "mode": "2d", "entities": [
        {"name": "Spawn", "components": [
          {"type": "TransformComponent", "fields": {}},
          {"type": "SpawnComponent", "fields": {"spawner": "player"}}
        ]}
      ]}
    """);
    engine.world.update(1 / 60);

    expect(SpawnPoints.first(engine.world, 'player')?.name, 'Spawn');
  });
}
```

In a test, the engine's storage cannot open its file, so `engine.cache` keeps everything in memory (`isUsingMemoryFallback` is true), and the audio engine's failure to start is logged and ignored. Neither stops the test.

## Running the whole loop

`world.update` runs the systems only. To run a step the way a game does, with the input update and every other update task, start the engine and tick its game loop with frame timestamps. The first tick only starts the clock; after that, each tick 1/60 s later runs one fixed step.

```dart
test('a pressed key reaches the actions', () async {
  final engine = Engine();
  addTearDown(engine.dispose);
  await engine.initialize();
  engine.input.loadAsset(InputActionAsset.parse(inputJson)); // your asset
  engine.start();

  const frame = Duration(microseconds: 16667);
  engine.gameLoop.tick(Duration.zero); // starts the clock
  engine.input.handleKeyEvent(
    const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.space,
      logicalKey: LogicalKeyboardKey.space,
      timeStamp: Duration.zero,
    ),
  );
  engine.gameLoop.tick(frame); // one fixed step

  expect(engine.input.actions.action('player/jump').isPressed(), isTrue);
});
```

`KeyDownEvent` and the key classes come from `package:flutter/services.dart`. While the engine is paused, a tick still updates input, so you can test pause menus the same way.

## Assets in tests

- `SceneLoader.loadString` and `SceneLoader.load` read a scene without an asset bundle.
- `SceneLoader.loadAsset` reads through `world.context.bundle`. An engine made with `Engine(context: EngineContext(bundle: myTestBundle))` loads from a test bundle of your own, such as a `CachingAssetBundle` subclass that serves files from a map.
- `SceneLoader.loadManifest` does not use the context's bundle: it reads `scenes.json` from Flutter's `rootBundle` unless you pass it one, so give it the same test bundle with `loadManifest(bundle: myTestBundle)`.
- A context you pass in is yours to dispose: call `context.dispose()` once the engine has been disposed.

## Widget tests

`GameWidget` works in `testWidgets`. Run the engine's asynchronous work with `tester.runAsync`, and pump frames to tick it:

```dart
testWidgets('the game draws', (tester) async {
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  addTearDown(() => tester.runAsync(engine.dispose));

  await tester.pumpWidget(
    MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
  );
  await tester.runAsync(engine.initialize);
  engine.start();

  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(engine.performanceStats['frame'], greaterThan(0));
});
```

A `GameWidget` built before `initialize()` finishes picks the engine up once it is ready, so the order above works without a rebuild.
