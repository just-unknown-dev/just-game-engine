// Using the interface: typing, dragging, walking it with the keyboard, and
// screens that open over the game and close again.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreCodecs);
  setUp(() {
    UiBindings.clear();
    UiWidgets.clear();
    UiActions.clear();
  });
  tearDown(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
  });

  /// A theme with sounds, so a test can hear what the interface does.
  const noisy = UiTheme(
    sounds: UiSounds(hover: 'move.wav', press: 'click.wav', toggle: 'flip.wav'),
  );

  /// Builds a canvas entity holding one child per entry.
  Entity canvasWith(
    World world,
    List<List<Component>> children, {
    UiCanvasComponent? canvas,
    String name = 'Hud',
    List<String>? childNames,
  }) {
    final root = world.createEntityWithComponents([
      canvas ?? UiCanvasComponent(designSize: const Size(400, 300)),
      ChildrenComponent(),
    ], name: name);
    for (var i = 0; i < children.length; i++) {
      final child = world.createEntityWithComponents([
        ...children[i],
        ParentComponent(parentId: root.id),
      ], name: childNames == null ? '$name.$i' : childNames[i]);
      root.getComponent<ChildrenComponent>()!.addChild(child.id);
    }
    return root;
  }

  /// The UI over a stand-in for the game, so a test can see what the
  /// pointer reaches.
  Future<(UiLayerState, List<String>)> show(
    WidgetTester tester,
    World world, {
    void Function()? onGameTap,
    UiTheme? theme,
  }) async {
    final key = GlobalKey<UiLayerState>();
    final sounds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onGameTap,
                  ),
                ),
                Positioned.fill(
                  child: UiLayer(
                    key: key,
                    world: world,
                    themeOverride: theme,
                    onSound: sounds.add,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return (key.currentState!, sounds);
  }

  /// The words inside whatever holds the keyboard focus.
  String focusedText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return '';
    final texts = find.descendant(
      of: find.byElementPredicate((e) => identical(e, context)),
      matching: find.byType(Text),
    );
    final found = texts.evaluate().map((e) => e.widget as Text);
    return [
      for (final text in found) text.data ?? text.textSpan?.toPlainText() ?? '',
    ].join();
  }

  group('controls', () {
    testWidgets('a toggle writes back and says what it did', (tester) async {
      Object? changedTo;
      UiActions.register('flipped', (context) => changedTo = context.value);
      final world = World();
      final toggle = UiToggleComponent(
        label: 'Music',
        onChanged: const UiActionList([UiAction('custom:flipped')]),
      );
      canvasWith(world, [
        [toggle],
      ]);
      final (_, sounds) = await show(tester, world, theme: noisy);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(toggle.value, isTrue);
      expect(changedTo, true);
      expect(sounds, contains('flip.wav'));
    });

    testWidgets('a slider writes back the number it was dragged to', (
      tester,
    ) async {
      double? changedTo;
      UiActions.register('volume', (context) => changedTo = context.number);
      final world = World();
      final slider = UiSliderComponent(
        value: 0,
        onChanged: const UiActionList([UiAction('custom:volume')]),
      );
      canvasWith(world, [
        [
          slider,
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.stretchTop,
            margin: const EdgeInsets.all(8),
          ),
        ],
      ]);
      await show(tester, world);

      // Tap the far right of the track.
      final track = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(track.right - 4, track.center.dy));
      await tester.pump();

      expect(slider.value, greaterThan(0.8));
      expect(changedTo, slider.value);
    });

    testWidgets('a text field keeps what was typed and reports it', (
      tester,
    ) async {
      final submitted = <Object?>[];
      UiActions.register('named', (context) => submitted.add(context.value));
      final world = World();
      final field = UiTextFieldComponent(
        hint: 'Your name',
        onSubmitted: const UiActionList([UiAction('custom:named')]),
      );
      canvasWith(world, [
        [
          field,
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.stretchTop,
            margin: const EdgeInsets.all(8),
          ),
        ],
      ]);
      final (layer, _) = await show(tester, world);

      await tester.enterText(find.byType(TextField), 'Ada');
      await tester.pump();
      expect(field.value, 'Ada');

      // A frame going by must not swallow what is half-typed.
      layer.sync();
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, ['Ada']);
    });

    testWidgets('a dropdown picks one of its options', (tester) async {
      final world = World();
      final dropdown = UiDropdownComponent(
        value: 'low',
        options: ['low', 'medium', 'high'],
      );
      canvasWith(world, [
        [
          dropdown,
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.stretchTop,
            margin: const EdgeInsets.all(8),
          ),
        ],
      ]);
      await show(tester, world);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('high').last);
      await tester.pumpAndSettle();

      expect(dropdown.value, 'high');
    });
  });

  group('the keyboard', () {
    /// Two buttons in a column, the first asking for focus.
    World twoButtons() {
      final world = World();
      final root = world.createEntityWithComponents([
        UiCanvasComponent(
          designSize: const Size(400, 300),
          safeArea: false,
          initialFocus: 'Play',
        ),
        ChildrenComponent(),
      ], name: 'Menu');
      final column = world.createEntityWithComponents([
        UiLayoutComponent(kind: UiLayoutKind.column, tight: true),
        ParentComponent(parentId: root.id),
        ChildrenComponent(),
      ], name: 'Column');
      root.getComponent<ChildrenComponent>()!.addChild(column.id);
      for (final label in ['Play', 'Quit']) {
        final child = world.createEntityWithComponents([
          ButtonComponent(label: label),
          ParentComponent(parentId: column.id),
        ], name: label);
        column.getComponent<ChildrenComponent>()!.addChild(child.id);
      }
      return world;
    }

    testWidgets('the screen says what takes focus first', (tester) async {
      await show(tester, twoButtons());
      await tester.pump();

      expect(focusedText(), 'Play');
    });

    testWidgets('an arrow walks to the next control', (tester) async {
      final (_, sounds) = await show(tester, twoButtons(), theme: noisy);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(focusedText(), 'Quit');
      expect(sounds, contains('move.wav'));
    });

    testWidgets('confirm presses what is focused', (tester) async {
      final pressed = <String>[];
      UiActions.register('play', (_) => pressed.add('play'));
      final world = World();
      final root = world.createEntityWithComponents([
        UiCanvasComponent(safeArea: false, initialFocus: 'Play'),
        ChildrenComponent(),
      ], name: 'Menu');
      final child = world.createEntityWithComponents([
        ButtonComponent(
          label: 'Play',
          onPressed: const UiActionList([UiAction('custom:play')]),
        ),
        ParentComponent(parentId: root.id),
      ], name: 'Play');
      root.getComponent<ChildrenComponent>()!.addChild(child.id);

      await show(tester, world);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(pressed, ['play']);
    });
  });

  group('screens', () {
    World withPauseMenu({bool modal = true}) {
      final world = World();
      canvasWith(world, [
        [TextComponent(text: 'Score 0')],
      ], name: 'Hud');
      canvasWith(
        world,
        [
          [TextComponent(text: 'Paused'), UiSlotComponent()],
        ],
        canvas: UiCanvasComponent(
          isScreen: true,
          visible: false,
          modal: modal,
          safeArea: false,
          transition: UiTransition.slideUp,
        ),
        name: 'Pause',
      );
      return world;
    }

    testWidgets('ui.push opens a screen and ui.back closes it', (tester) async {
      final world = withPauseMenu();
      final (layer, _) = await show(tester, world);
      expect(find.text('Paused', findRichText: true), findsNothing);

      UiActions.run(
        const UiAction('ui.push', 'Pause'),
        UiActionContext(world: world),
      );
      layer.sync();
      await tester.pumpAndSettle();

      expect(find.text('Paused', findRichText: true), findsOneWidget);
      expect(layer.navigator.top?.name, 'Pause');
      // The scene is the record of what is open.
      expect(
        world
            .findEntityByName('Pause')!
            .getComponent<UiCanvasComponent>()!
            .visible,
        isTrue,
      );

      UiActions.run(const UiAction('ui.back'), UiActionContext(world: world));
      layer.sync();
      await tester.pumpAndSettle();

      expect(find.text('Paused', findRichText: true), findsNothing);
      expect(layer.navigator.isEmpty, isTrue);
    });

    testWidgets('the HUD stays while a screen is over it', (tester) async {
      final world = withPauseMenu();
      final (layer, _) = await show(tester, world);

      layer.navigator.push('Pause');
      layer.sync();
      await tester.pumpAndSettle();

      expect(find.text('Score 0', findRichText: true), findsOneWidget);
      expect(find.text('Paused', findRichText: true), findsOneWidget);
    });

    testWidgets('a transition runs and settles', (tester) async {
      final world = withPauseMenu();
      final (layer, _) = await show(tester, world);

      layer.navigator.push('Pause');
      layer.sync();
      await tester.pump();
      // Half-way through: on its way in, not yet where it lands.
      await tester.pump(const Duration(milliseconds: 100));
      final midway = tester.getTopLeft(find.text('Paused', findRichText: true));
      await tester.pumpAndSettle();
      final landed = tester.getTopLeft(find.text('Paused', findRichText: true));

      expect(midway.dy, isNot(landed.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a modal screen gates the game; a plain one does not', (
      tester,
    ) async {
      var gameTaps = 0;
      final world = withPauseMenu();
      final (layer, _) = await show(tester, world, onGameTap: () => gameTaps++);

      // Nothing open: the pointer reaches the game.
      await tester.tapAt(const Offset(200, 260));
      await tester.pump();
      expect(gameTaps, 1);

      layer.navigator.push('Pause');
      layer.sync();
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 260));
      await tester.pump();
      expect(gameTaps, 1, reason: 'the modal screen took it');

      layer.navigator.back();
      layer.sync();
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 260));
      await tester.pump();
      expect(gameTaps, 2);
    });

    testWidgets('a screen that is not modal lets the game through', (
      tester,
    ) async {
      var gameTaps = 0;
      final world = withPauseMenu(modal: false);
      final (layer, _) = await show(tester, world, onGameTap: () => gameTaps++);
      layer.navigator.push('Pause');
      layer.sync();
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 260));
      await tester.pump();

      expect(gameTaps, 1);
    });

    testWidgets('a button inside a modal screen can be pressed', (
      tester,
    ) async {
      final pressed = <String>[];
      UiActions.register('resume', (_) => pressed.add('resume'));
      final world = World();
      canvasWith(
        world,
        [
          [
            ButtonComponent(
              label: 'Resume',
              onPressed: const UiActionList([UiAction('custom:resume')]),
            ),
            UiSlotComponent(
              mode: UiSlotMode.anchored,
              anchor: UiAnchor.center,
              size: const Size(160, 48),
            ),
          ],
        ],
        canvas: UiCanvasComponent(
          isScreen: true,
          visible: false,
          modal: true,
          safeArea: false,
        ),
        name: 'Pause',
        childNames: ['Resume'],
      );
      final (layer, _) = await show(tester, world);
      layer.navigator.push('Pause');
      layer.sync();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resume', findRichText: true));
      await tester.pump();

      expect(pressed, ['resume']);
    });

    testWidgets('Escape goes back', (tester) async {
      final world = World();
      canvasWith(
        world,
        [
          [ButtonComponent(label: 'Resume'), UiSlotComponent()],
        ],
        canvas: UiCanvasComponent(
          isScreen: true,
          visible: false,
          modal: true,
          safeArea: false,
          initialFocus: 'Resume',
        ),
        name: 'Pause',
        childNames: ['Resume'],
      );
      final (layer, _) = await show(tester, world);
      layer.navigator.push('Pause');
      layer.sync();
      await tester.pumpAndSettle();
      expect(focusedText(), 'Resume');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      layer.sync();
      await tester.pumpAndSettle();

      expect(layer.navigator.isEmpty, isTrue);
    });

    testWidgets('a hero flies from one screen to the next', (tester) async {
      final world = World();
      canvasWith(world, [
        [TextComponent(text: 'Coin'), UiSlotComponent(heroTag: 'coin')],
      ], name: 'Hud');
      canvasWith(
        world,
        [
          [TextComponent(text: 'Coin'), UiSlotComponent(heroTag: 'coin')],
        ],
        canvas: UiCanvasComponent(
          isScreen: true,
          visible: false,
          safeArea: false,
        ),
        name: 'Shop',
      );

      final (layer, _) = await show(tester, world);
      expect(find.byType(Hero), findsOneWidget);

      layer.navigator.push('Shop');
      layer.sync();
      await tester.pumpAndSettle();

      expect(find.byType(Hero), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a scene saved with a screen open opens with it open', (
      tester,
    ) async {
      final world = World();
      canvasWith(
        world,
        [
          [TextComponent(text: 'Shop')],
        ],
        canvas: UiCanvasComponent(isScreen: true, safeArea: false),
        name: 'Shop',
      );

      final (layer, _) = await show(tester, world);
      await tester.pumpAndSettle();

      expect(find.text('Shop', findRichText: true), findsOneWidget);
      expect(layer.navigator.top?.name, 'Shop');
    });
  });

  group('the navigator on its own', () {
    test('show hides and flips a layer without touching the stack', () {
      final world = World();
      world.createEntityWithComponents([UiCanvasComponent()], name: 'Hud');
      final navigator = UiNavigator(world);
      final hud = world
          .findEntityByName('Hud')!
          .getComponent<UiCanvasComponent>()!;

      navigator.show('Hud', false);
      expect(hud.visible, isFalse);
      navigator.show('Hud', null);
      expect(hud.visible, isTrue);
      expect(navigator.isEmpty, isTrue);
    });

    test('show hides one element inside a canvas', () {
      final world = World();
      final slot = UiSlotComponent();
      world.createEntityWithComponents([
        TextComponent(text: 'Hint'),
        slot,
      ], name: 'Hint');

      UiNavigator(world).show('Hint', false);

      expect(slot.visible, isFalse);
    });

    test('pushing the same screen twice leaves one of it', () {
      final world = World();
      world.createEntityWithComponents([
        UiCanvasComponent(isScreen: true, visible: false),
      ], name: 'Pause');
      final navigator = UiNavigator(world);

      navigator
        ..push('Pause')
        ..push('Pause');

      expect(navigator.stack.length, 1);
    });

    test('back with nothing open does nothing', () {
      final navigator = UiNavigator(World());
      expect(navigator.back, returnsNormally);
    });

    test('a name that is not there is quietly nothing', () {
      final navigator = UiNavigator(World());
      navigator
        ..push('Missing')
        ..show('Missing', true);
      expect(navigator.isEmpty, isTrue);
    });

    test('what the game already handles is left to the game', () {
      final world = World();
      var asked = '';
      final host = UiActionHost(pushScreen: (name) => asked = name);
      final filled = UiNavigator(world).fillingIn(host);

      filled.pushScreen!('Shop');

      expect(asked, 'Shop');
      expect(filled.back, isNotNull);
    });
  });
}
