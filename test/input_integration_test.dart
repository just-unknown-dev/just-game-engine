// The engine's input: the clock it runs on, paused or not; each player's
// actions reaching the entity they control; and keys from the scene's UI
// still reaching the game.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_inputs/testing.dart';

const _asset = InputActionAsset(
  name: 'test',
  nextId: 30,
  players: PlayerSettingsDef(
    maxPlayers: 2,
    joining: JoinBehavior.onJoinAction,
    joinActions: ['ui/join'],
  ),
  schemes: [
    ControlSchemeDef(
      name: 'Keyboard',
      group: 'Keyboard',
      devices: [DeviceRequirement(InputLayouts.keyboard)],
    ),
    ControlSchemeDef(
      name: 'Gamepad',
      group: 'Gamepad',
      devices: [DeviceRequirement(InputLayouts.gamepad)],
    ),
  ],
  maps: [
    ActionMapDef(
      id: 'm1',
      name: 'player',
      actions: [
        InputActionDef(
          id: 'a2',
          name: 'move',
          type: ActionValueType.vector2,
          bindings: [
            CompositeBindingDef(
              id: 'b3',
              composite: CompositeKinds.vector2,
              groups: ['Keyboard'],
              parts: [
                CompositePartDef(id: 'b4', part: 'left', path: '<Keyboard>/a'),
                CompositePartDef(id: 'b5', part: 'right', path: '<Keyboard>/d'),
              ],
            ),
            ControlBindingDef(
              id: 'b6',
              path: '<Gamepad>/leftStick',
              groups: ['Gamepad'],
            ),
          ],
        ),
        InputActionDef(
          id: 'a7',
          name: 'jump',
          bindings: [
            ControlBindingDef(
              id: 'b8',
              path: '<Keyboard>/space',
              groups: ['Keyboard'],
            ),
            ControlBindingDef(
              id: 'b9',
              path: '<Gamepad>/buttonSouth',
              groups: ['Gamepad'],
            ),
          ],
        ),
        InputActionDef(
          id: 'a10',
          name: 'charge',
          interactions: [
            InteractionDef('hold', {'duration': 0.5}),
          ],
          bindings: [ControlBindingDef(id: 'b11', path: '<Keyboard>/c')],
        ),
      ],
    ),
    ActionMapDef(
      id: 'm12',
      name: 'ui',
      actions: [
        InputActionDef(
          id: 'a13',
          name: 'join',
          interactions: [
            InteractionDef('hold', {'duration': 0.5}),
          ],
          bindings: [ControlBindingDef(id: 'b14', path: '<Gamepad>/start')],
        ),
      ],
    ),
  ],
);

KeyDownEvent _down(PhysicalKeyboardKey k) => KeyDownEvent(
  physicalKey: k,
  logicalKey: LogicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Engine> boot() async {
    Engine.resetInstance();
    final engine = Engine();
    await engine.initialize();
    addTearDown(Engine.resetInstance);
    engine.input.loadAsset(_asset);
    return engine;
  }

  group('the input clock', () {
    test('while paused, input still moves every frame', () async {
      final engine = await boot();
      engine.start();
      engine.pause();
      engine.input.handleKeyEvent(_down(PhysicalKeyboardKey.space));
      engine.gameLoop.tick();
      expect(engine.input.actions.action('jump').isPressed(), isTrue);
    });

    test('a hold takes real time, even while paused', () async {
      final engine = await boot();
      engine.start();
      engine.pause();
      final charge = engine.input.actions.action('charge');
      engine.input.handleKeyEvent(_down(PhysicalKeyboardKey.keyC));
      engine.gameLoop.tick();
      expect(charge.phase, InputActionPhase.started);
      // Frame by frame, as a game runs: one long frame counts only up to
      // the time manager's 100 ms cap.
      for (
        var i = 0;
        i < 40 && charge.phase != InputActionPhase.performed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        engine.gameLoop.tick();
      }
      expect(charge.phase, InputActionPhase.performed);
    });

    test('running, it advances by the fixed step, time scale or not', () async {
      final engine = await boot();
      engine.time.timeScale = 0;
      engine.start();
      engine.gameLoop.tick();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      engine.gameLoop.tick();
      expect(engine.input.time, greaterThan(0));
      expect(engine.input.updateCount, greaterThan(0));
      final steps = engine.input.updateCount;
      expect(
        engine.input.time,
        closeTo(steps * engine.gameLoop.fixedDeltaTime, 1e-9),
      );
    });
  });

  group('InputComponent', () {
    test('player 1 before anyone joins reads every device', () async {
      final engine = await boot();
      final world = engine.world;
      world.addSystem(InputSystem(engine.input));
      final entity = world.createEntityWithComponents([InputComponent()]);
      final input = entity.getComponent<InputComponent>()!;

      engine.input.handleKeyEvent(_down(PhysicalKeyboardKey.keyD));
      engine.input.handleKeyEvent(_down(PhysicalKeyboardKey.space));
      engine.input.update(1);
      world.update(1 / 60);

      expect(input.vector('move'), const Offset(1, 0));
      expect(input.isDown('jump'), isTrue);
      expect(input.wasPressed('jump'), isTrue);
      world.update(1 / 60);
      engine.input.update(2);
      world.update(1 / 60);
      expect(input.wasPressed('jump'), isFalse, reason: 'one step only');
      expect(input.isDown('jump'), isTrue);
    });

    test('two players, two entities: each gets their own', () async {
      final engine = await boot();
      final pads = FakeGamepadSource();
      await engine.input.attachGamepads(pads);
      engine.input.players.start();
      final world = engine.world..addSystem(InputSystem(engine.input));
      final one = world.createEntityWithComponents([
        InputComponent(playerIndex: 0),
      ]);
      final two = world.createEntityWithComponents([
        InputComponent(playerIndex: 1),
      ]);
      final t = InputTester(engine.input);

      t.tap(PhysicalKeyboardKey.keyA); // player 1: the keyboard
      pads.connect('p');
      pads.press('p', 9); // hold Start to join
      t.step(0.1);
      t.step(0.6);
      pads.release('p');
      t.step();
      expect(engine.input.players.players, hasLength(2));

      pads.press('p', 0);
      t.step();
      world.update(1 / 60);
      expect(two.getComponent<InputComponent>()!.isDown('jump'), isTrue);
      expect(one.getComponent<InputComponent>()!.isDown('jump'), isFalse);
    });

    test('a player who is not playing holds nothing', () async {
      final engine = await boot();
      final world = engine.world..addSystem(InputSystem(engine.input));
      final entity = world.createEntityWithComponents([
        InputComponent(playerIndex: 3),
      ]);
      final input = entity.getComponent<InputComponent>()!
        ..setDown('jump', true);
      world.update(1 / 60);
      expect(input.isDown('jump'), isFalse);
    });

    test('saves which player it is', () {
      registerCoreCodecs();
      final codec = ComponentCodecRegistry.instance;
      final json = codec.encode(InputComponent(playerIndex: 2))!;
      expect((codec.decode(json) as InputComponent).playerIndex, 2);
    });
  });

  test('SimpleMovement steers by an action', () async {
    final engine = await boot();
    final world = engine.world..addSystem(SimpleMovementSystem(engine.input));
    final entity = world.createEntityWithComponents([
      TransformComponent(),
      SimpleMovementComponent(speed: 60),
    ]);
    engine.input.handleKeyEvent(_down(PhysicalKeyboardKey.keyD));
    engine.input.update(1);
    world.update(1);
    expect(
      entity.getComponent<TransformComponent>()!.position.x,
      closeTo(60, 1e-6),
    );
  });

  group('GameWidget', () {
    testWidgets('keys the scene UI does not want still reach the game', (
      tester,
    ) async {
      // The engine's own start-up does real I/O (its cache), which the
      // widget test's fake clock would never finish.
      final engine = (await tester.runAsync(boot))!;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              GameWidget(engine: engine, showLayers: false),
              // Stands in for a focused HUD button.
              Focus(focusNode: focus, child: const SizedBox()),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.space,
        physicalKey: PhysicalKeyboardKey.space,
      );
      engine.input.update(1);
      expect(engine.input.actions.action('jump').isPressed(), isTrue);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.space,
        physicalKey: PhysicalKeyboardKey.space,
      );
      engine.input.update(2);
      expect(engine.input.actions.action('jump').isPressed(), isFalse);
    });
  });

  test('players\' bindings are kept in the engine cache', () async {
    final engine = await boot();
    expect(engine.input.overrideStore, isA<CacheInputOverrideStore>());
    await engine.input.overrideStore.save(
      'input.overrides.test.p1',
      const BindingOverrides({'b8': '<Keyboard>/k'}).toJson(),
    );
    final back = BindingOverrides.fromJson(
      await engine.input.overrideStore.load('input.overrides.test.p1'),
    );
    expect(back['b8'], '<Keyboard>/k');
  });
}
