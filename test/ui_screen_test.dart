// Screen-space UI: entities in a scene become real Flutter widgets, a game
// puts its own widgets among them, and a frame that changes one thing
// rebuilds one thing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreCodecs);
  setUp(() {
    UiBindings.clear();
    UiWidgets.clear();
  });
  tearDown(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
  });

  ComponentDefinition definitionFor(String type) =>
      ComponentDefinitionRegistry.instance.definitionByType(type)!;

  /// Saves a component the way a scene does, then loads it back.
  T roundTrip<T extends Component>(String type, T component, T fresh) {
    final definition = definitionFor(type);
    final saved = {
      for (final f in definition.fields) f.name: f.encodeFrom(component),
    };
    for (final f in definition.fields) {
      f.decodeInto(fresh, saved[f.name]);
    }
    return fresh;
  }

  /// A canvas with [children] under it, as the scene loader would leave it.
  Entity canvasWith(
    World world,
    List<List<Component>> children, {
    UiCanvasComponent? canvas,
  }) {
    final root = world.createEntityWithComponents([
      canvas ?? UiCanvasComponent(designSize: const Size(400, 300)),
      ChildrenComponent(),
    ], name: 'Hud');
    for (var i = 0; i < children.length; i++) {
      final child = world.createEntityWithComponents([
        ...children[i],
        ParentComponent(parentId: root.id),
      ], name: 'Child$i');
      root.getComponent<ChildrenComponent>()!.addChild(child.id);
    }
    return root;
  }

  /// Puts [world]'s UI on a 400×300 screen and hands back the layer, so a
  /// test can drive it the way the game loop does.
  Future<UiLayerState> showUi(WidgetTester tester, World world) async {
    final key = GlobalKey<UiLayerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: UiLayer(key: key, world: world),
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  group('a screen in the scene', () {
    testWidgets('a world with no editor shows its HUD', (tester) async {
      UiBindings.register('coins', () => 7);
      final world = World();
      canvasWith(world, [
        [
          TextComponent(text: 'Coins: {coins}'),
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.topLeft,
            offset: const Offset(16, 16),
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Coins: 7', findRichText: true), findsOneWidget);
    });

    testWidgets('nothing on screen when every canvas is hidden', (
      tester,
    ) async {
      final world = World();
      canvasWith(world, [
        [TextComponent(text: 'Hidden')],
      ], canvas: UiCanvasComponent(visible: false));

      await showUi(tester, world);

      expect(find.text('Hidden', findRichText: true), findsNothing);
    });

    testWidgets('a canvas appearing later is picked up by sync', (
      tester,
    ) async {
      final world = World();
      final layer = await showUi(tester, world);
      expect(find.text('Later', findRichText: true), findsNothing);

      canvasWith(world, [
        [TextComponent(text: 'Later')],
      ]);
      layer.sync();
      await tester.pump();

      expect(find.text('Later', findRichText: true), findsOneWidget);
    });

    testWidgets('a row lays its children out in the order the scene holds '
        'them', (tester) async {
      final world = World();
      final root = world.createEntityWithComponents([
        UiCanvasComponent(designSize: const Size(400, 300)),
        ChildrenComponent(),
      ], name: 'Hud');
      final row = world.createEntityWithComponents([
        UiLayoutComponent(kind: UiLayoutKind.row, spacing: 8),
        ParentComponent(parentId: root.id),
        ChildrenComponent(),
      ], name: 'Row');
      root.getComponent<ChildrenComponent>()!.addChild(row.id);
      for (final word in ['one', 'two', 'three']) {
        final child = world.createEntityWithComponents([
          TextComponent(text: word),
          ParentComponent(parentId: row.id),
        ], name: word);
        row.getComponent<ChildrenComponent>()!.addChild(child.id);
      }

      await showUi(tester, world);

      final xs = [
        for (final word in ['one', 'two', 'three'])
          tester.getTopLeft(find.text(word, findRichText: true)).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
    });
  });

  group('widgets a game brings', () {
    testWidgets('a registered widget is built with its props', (tester) async {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [
            UiWidgetProp('caption', 'Caption', UiPropKind.text),
            UiWidgetProp(
              'count',
              'Count',
              UiPropKind.number,
              defaultValue: '1',
            ),
          ],
          build: (context) => Text(
            '${context.text('caption')} ×${context.number('count')!.toInt()}',
          ),
        ),
      );

      final world = World();
      canvasWith(world, [
        [
          UiCustomComponent(
            widgetId: 'badge',
            props: {'caption': 'Keys', 'count': '3'},
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Keys ×3'), findsOneWidget);
    });

    testWidgets('a prop the scene left out falls back to the default', (
      tester,
    ) async {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [
            UiWidgetProp(
              'count',
              'Count',
              UiPropKind.number,
              defaultValue: '9',
            ),
          ],
          build: (context) => Text('count=${context.props['count']}'),
        ),
      );

      final world = World();
      canvasWith(world, [
        [UiCustomComponent(widgetId: 'badge')],
      ]);

      await showUi(tester, world);

      expect(find.text('count=9'), findsOneWidget);
    });

    testWidgets('a widget this game does not have leaves a gap, not a crash', (
      tester,
    ) async {
      final world = World();
      canvasWith(world, [
        [UiCustomComponent(widgetId: 'nothing_registered')],
      ]);

      await showUi(tester, world);

      expect(tester.takeException(), isNull);
    });

    testWidgets('a prop reads a binding', (tester) async {
      UiBindings.register('lives', () => 2);
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [UiWidgetProp('caption', 'Caption', UiPropKind.text)],
          build: (context) => Text(context.text('caption')),
        ),
      );

      final world = World();
      canvasWith(world, [
        [
          UiCustomComponent(
            widgetId: 'badge',
            props: {'caption': 'Lives: {lives}'},
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Lives: 2'), findsOneWidget);
    });
  });

  group('rebuilding', () {
    /// A widget that counts how often it was built, registered under [id].
    int builds = 0;

    setUp(() {
      builds = 0;
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'counter',
          label: 'Counter',
          props: const [UiWidgetProp('note', 'Note', UiPropKind.text)],
          build: (context) {
            builds++;
            return Text('note=${context.props['note']}');
          },
        ),
      );
    });

    testWidgets('one field change rebuilds one node', (tester) async {
      final world = World();
      final canvas = canvasWith(world, [
        [TextComponent(text: 'first'), UiSlotComponent()],
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final textEntity = world.getEntity(
        canvas.getComponent<ChildrenComponent>()!.childIds.first,
      )!;
      final after = builds;

      // A neighbour changes: the counter must not be built again.
      textEntity.getComponent<TextComponent>()!.text = 'second';
      layer.sync();
      await tester.pump();

      expect(find.text('second', findRichText: true), findsOneWidget);
      expect(builds, after, reason: 'a sibling changed, not this node');
    });

    testWidgets('a node is rebuilt when its own field changes', (tester) async {
      final world = World();
      final canvas = canvasWith(world, [
        [TextComponent(text: 'first')],
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final custom = world
          .getEntity(canvas.getComponent<ChildrenComponent>()!.childIds.last)!
          .getComponent<UiCustomComponent>()!;
      final after = builds;

      custom.props['note'] = 'b';
      layer.sync();
      await tester.pump();

      expect(builds, after + 1);
      expect(find.text('note=b'), findsOneWidget);
    });

    testWidgets('a frame that changes nothing rebuilds nothing', (
      tester,
    ) async {
      final world = World();
      canvasWith(world, [
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final after = builds;

      for (var i = 0; i < 5; i++) {
        layer.sync();
        await tester.pump();
      }

      expect(builds, after);
    });

    testWidgets('a binding reading a new number redraws the text', (
      tester,
    ) async {
      var coins = 1;
      UiBindings.register('coins', () => coins);
      final world = World();
      canvasWith(world, [
        [TextComponent(text: '{coins}')],
      ]);
      final layer = await showUi(tester, world);
      expect(find.text('1', findRichText: true), findsOneWidget);

      // Nothing was edited: only the game moved on.
      coins = 2;
      layer.sync();
      await tester.pump();

      expect(find.text('2', findRichText: true), findsOneWidget);
    });
  });

  group('the canvas scaler', () {
    test('fit keeps the whole design on screen, at three sizes', () {
      const design = Size(800, 600);
      expect(UiScaleMode.fit.scaleFor(design, const Size(800, 600)), 1);
      expect(UiScaleMode.fit.scaleFor(design, const Size(400, 600)), 0.5);
      expect(UiScaleMode.fit.scaleFor(design, const Size(1600, 600)), 1);
      expect(UiScaleMode.none.scaleFor(design, const Size(400, 300)), 1);
      expect(UiScaleMode.width.scaleFor(design, const Size(400, 900)), 0.5);
      expect(UiScaleMode.height.scaleFor(design, const Size(400, 300)), 0.5);
    });

    testWidgets('a HUD drawn for a big screen is scaled down to a small one', (
      tester,
    ) async {
      // A widget that fills its slot exactly, so what is measured is where
      // the scaler put the slot and nothing else.
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (context) => const SizedBox.expand(key: ValueKey('probe')),
        ),
      );
      final world = World();
      canvasWith(
        world,
        [
          [
            UiCustomComponent(widgetId: 'probe'),
            UiSlotComponent(
              mode: UiSlotMode.anchored,
              anchor: UiAnchor.topLeft,
              pivot: Offset.zero,
              offset: const Offset(100, 100),
              size: const Size(80, 20),
            ),
          ],
        ],
        // Twice the 400×300 the test screen is.
        canvas: UiCanvasComponent(
          designSize: const Size(800, 600),
          safeArea: false,
        ),
      );

      await showUi(tester, world);

      // 100 design pixels in, on a screen at half scale: 50 real pixels,
      // and an 80×20 slot comes out 40×10.
      final box = tester.getTopLeft(find.byType(UiLayer));
      final probe = find.byKey(const ValueKey('probe'));
      expect(tester.getTopLeft(probe) - box, const Offset(50, 50));
      // On screen, not in the widget's own coordinates — the scale lives
      // in a Transform above it, so `getSize` would still say 80×20.
      expect(
        tester.getBottomRight(probe) - tester.getTopLeft(probe),
        const Offset(40, 10),
      );
    });
  });

  group('what a screen saves', () {
    test('a canvas keeps everything it was given', () {
      final canvas = UiCanvasComponent(
        designSize: const Size(1280, 720),
        scaleMode: UiScaleMode.width,
        safeArea: false,
        sortOrder: 3,
        theme: 'assets/ui/dark.uitheme.json',
        visible: false,
        isScreen: true,
        modal: true,
        transition: UiTransition.slideUp,
        initialFocus: 'PlayButton',
      );

      final loaded = roundTrip(
        'UiCanvasComponent',
        canvas,
        UiCanvasComponent(),
      );

      expect(loaded.designSize, const Size(1280, 720));
      expect(loaded.scaleMode, UiScaleMode.width);
      expect(loaded.safeArea, isFalse);
      expect(loaded.sortOrder, 3);
      expect(loaded.theme, 'assets/ui/dark.uitheme.json');
      expect(loaded.visible, isFalse);
      expect(loaded.isScreen, isTrue);
      expect(loaded.modal, isTrue);
      expect(loaded.transition, UiTransition.slideUp);
      expect(loaded.initialFocus, 'PlayButton');
    });

    test('a slot keeps where it sits, anchors and all', () {
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.bottomRight,
        pivot: const Offset(1, 1),
        offset: const Offset(-24, -16),
        size: const Size(120, 32),
        margin: const EdgeInsets.fromLTRB(1, 2, 3, 4),
        flex: 2,
        alignSelf: 'stretch',
        opacity: 0.5,
        visible: false,
        ignorePointer: true,
        heroTag: 'coin',
      );

      final loaded = roundTrip('UiSlotComponent', slot, UiSlotComponent());

      expect(loaded.mode, UiSlotMode.anchored);
      expect(loaded.anchor, UiAnchor.bottomRight);
      expect(loaded.anchor.presetName, 'bottomRight');
      expect(loaded.pivot, const Offset(1, 1));
      expect(loaded.offset, const Offset(-24, -16));
      expect(loaded.size, const Size(120, 32));
      expect(loaded.margin, const EdgeInsets.fromLTRB(1, 2, 3, 4));
      expect(loaded.flex, 2);
      expect(loaded.alignSelf, 'stretch');
      expect(loaded.opacity, 0.5);
      expect(loaded.visible, isFalse);
      expect(loaded.ignorePointer, isTrue);
      expect(loaded.heroTag, 'coin');
    });

    test('a container keeps how it lays out', () {
      final layout = UiLayoutComponent(
        kind: UiLayoutKind.grid,
        mainAxis: UiAlign.spaceBetween,
        crossAxis: UiAlign.stretch,
        spacing: 12,
        padding: const EdgeInsets.all(6),
        columns: 4,
        tight: true,
      );

      final loaded = roundTrip(
        'UiLayoutComponent',
        layout,
        UiLayoutComponent(),
      );

      expect(loaded.kind, UiLayoutKind.grid);
      expect(loaded.mainAxis, UiAlign.spaceBetween);
      expect(loaded.crossAxis, UiAlign.stretch);
      expect(loaded.spacing, 12);
      expect(loaded.padding, const EdgeInsets.all(6));
      expect(loaded.columns, 4);
      expect(loaded.tight, isTrue);
    });

    test('a panel keeps its look', () {
      final panel = UiPanelComponent(
        colorRole: 'danger',
        color: const Color(0xFF102030),
        borderColor: const Color(0xFFAABBCC),
        borderWidth: 2,
        radius: 14,
        shadowBlur: 8,
        blur: 3,
        image: 'assets/ui/frame.png',
        nineSlice: const EdgeInsets.all(12),
      );

      final loaded = roundTrip('UiPanelComponent', panel, UiPanelComponent());

      expect(loaded.colorRole, 'danger');
      expect(loaded.color, const Color(0xFF102030));
      expect(loaded.borderColor, const Color(0xFFAABBCC));
      expect(loaded.borderWidth, 2);
      expect(loaded.radius, 14);
      expect(loaded.shadowBlur, 8);
      expect(loaded.blur, 3);
      expect(loaded.image, 'assets/ui/frame.png');
      expect(loaded.nineSlice, const EdgeInsets.all(12));
    });

    test('the controls keep what they do', () {
      final toggle = roundTrip(
        'UiToggleComponent',
        UiToggleComponent(
          value: true,
          label: 'Music',
          binding: 'settings.music',
          onChanged: const UiActionList([UiAction('signal', 'music')]),
        ),
        UiToggleComponent(),
      );
      expect(toggle.value, isTrue);
      expect(toggle.label, 'Music');
      expect(toggle.binding, 'settings.music');
      expect(toggle.onChanged.actions.single.kind, 'signal');
      expect(toggle.onChanged.actions.single.argument, 'music');

      final slider = roundTrip(
        'UiSliderComponent',
        UiSliderComponent(value: 0.25, min: -1, max: 3, steps: 8),
        UiSliderComponent(),
      );
      expect(slider.value, 0.25);
      expect(slider.min, -1);
      expect(slider.max, 3);
      expect(slider.steps, 8);

      final field = roundTrip(
        'UiTextFieldComponent',
        UiTextFieldComponent(
          value: 'Ada',
          hint: 'Your name',
          maxLength: 12,
          obscure: true,
        ),
        UiTextFieldComponent(),
      );
      expect(field.value, 'Ada');
      expect(field.hint, 'Your name');
      expect(field.maxLength, 12);
      expect(field.obscure, isTrue);

      final dropdown = roundTrip(
        'UiDropdownComponent',
        UiDropdownComponent(
          value: 'medium',
          options: ['low', 'medium', 'high'],
        ),
        UiDropdownComponent(),
      );
      expect(dropdown.value, 'medium');
      expect(dropdown.options, ['low', 'medium', 'high']);

      final bar = roundTrip(
        'UiProgressComponent',
        UiProgressComponent(
          value: 0.3,
          binding: 'health',
          maxBinding: 'maxHealth',
          radial: true,
          thickness: 5,
        ),
        UiProgressComponent(),
      );
      expect(bar.value, 0.3);
      expect(bar.binding, 'health');
      expect(bar.maxBinding, 'maxHealth');
      expect(bar.radial, isTrue);
      expect(bar.thickness, 5);
    });

    test('a custom widget keeps which widget and what it was told', () {
      final loaded = roundTrip(
        'UiCustomComponent',
        UiCustomComponent(
          widgetId: 'inventory_grid',
          props: {'columns': '4', 'title': 'Bag'},
        ),
        UiCustomComponent(),
      );

      expect(loaded.widgetId, 'inventory_grid');
      expect(loaded.props, {'columns': '4', 'title': 'Bag'});
    });

    test('every screen component is in the registry, under UI', () {
      for (final type in [
        'UiCanvasComponent',
        'UiSlotComponent',
        'UiLayoutComponent',
        'UiPanelComponent',
        'UiImageComponent',
        'UiProgressComponent',
        'UiToggleComponent',
        'UiSliderComponent',
        'UiTextFieldComponent',
        'UiDropdownComponent',
        'UiCustomComponent',
        'UiSpacerComponent',
      ]) {
        final definition = definitionFor(type);
        expect(definition.hints.group, 'UI', reason: type);
        // Anything the inspector shows needs a label to show it under.
        for (final field in definition.fields) {
          expect(
            definition.hints.fields[field.name]?.label,
            isNotNull,
            reason: '$type.${field.name} has no label',
          );
        }
      }
    });
  });

  group('the system behind it', () {
    test('a text that types itself out advances with the world', () {
      final world = World();
      registerUiSystems(world);
      final text = TextComponent(text: 'Hello', revealSpeed: 10);
      world.createEntityWithComponents([text], name: 'Line');

      world.update(0.2);

      expect(text.revealed, closeTo(2, 0.001));
    });

    test('the layer is told when a binding reads something new', () {
      var coins = 0;
      UiBindings.register('coins', () => coins);
      final world = World();
      final system = UiSystem();
      world.addSystem(system);
      var told = 0;
      system.onChanged = () => told++;
      world.createEntityWithComponents([
        TextComponent(text: '{coins}'),
      ], name: 'Coins');

      world.update(1 / 60);
      final afterFirst = told;
      world.update(1 / 60);
      expect(told, afterFirst, reason: 'nothing changed');

      coins = 5;
      world.update(1 / 60);
      expect(told, afterFirst + 1);
    });

    test('bindings a scene asks for but the game never registered', () {
      final world = World();
      UiBindings.register('coins', () => 1);
      world.createEntityWithComponents([
        TextComponent(text: '{coins} / {gems}'),
      ], name: 'Line');

      expect(UiSystem.missingBindings(world), ['gems']);
    });
  });
  group('what a scene file means by a parent', () {
    /// A scene the way a hand-written file — or a generator — leaves it:
    /// the child names its parent and carries nothing else about it.
    Map<String, dynamic> sceneJson() => {
      'version': SceneFormat.current,
      'name': 'level_test',
      'entities': [
        {
          'name': 'Hud',
          'parentName': null,
          'components': [
            {
              'type': 'UiCanvasComponent',
              'fields': {'designW': 400.0, 'designH': 300.0},
            },
          ],
        },
        {
          'name': 'Label',
          'parentName': 'Hud',
          'components': [
            {
              'type': 'TextComponent',
              'fields': {'textValue': 'Coins'},
            },
          ],
        },
      ],
    };

    test('an entity the file switches off starts switched off', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final json = sceneJson();
      (json['entities'] as List)[1]['enabled'] = false;

      SceneLoader.load(world, json);

      final label = world.findEntityByName('Label')!;
      // In the world and part of the scene; the systems pass it by.
      expect(label.isAlive, isTrue);
      expect(label.isActive, isFalse);
      // And saying nothing about it means on.
      expect(world.findEntityByName('Hud')!.isActive, isTrue);
    });

    test('the child is linked both ways, whatever the file listed', () {
      final world = World()..initialize();
      addTearDown(world.dispose);

      SceneLoader.load(world, sceneJson());

      final hud = world.findEntityByName('Hud')!;
      final label = world.findEntityByName('Label')!;
      // Down: the parent holds it…
      expect(hud.getComponent<ChildrenComponent>()!.childIds, [label.id]);
      // …and up, which is what tells everything else it is not a root.
      expect(label.getComponent<ParentComponent>()?.parentId, hud.id);
    });

    test('and the link survives being saved again', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      SceneLoader.load(world, sceneJson());

      // What a save writes is read back from `ParentComponent`; without
      // one the hierarchy was lost on the way out.
      final label = world.findEntityByName('Label')!;
      final parentId = label.getComponent<ParentComponent>()!.parentId;
      expect(world.getEntity(parentId!)!.name, 'Hud');
    });

    testWidgets('a child with no ParentComponent still draws in place', (
      tester,
    ) async {
      final world = World()..initialize();
      addTearDown(world.dispose);
      SceneLoader.load(world, sceneJson());

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 400, height: 300, child: UiLayer(world: world)),
        ),
      );

      expect(find.text('Coins', findRichText: true), findsOneWidget);
    });
  });
}
