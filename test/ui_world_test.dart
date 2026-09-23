// UI in the world: text that keeps its look through a save, text that reads
// the game, and buttons that can finally be pressed.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreCodecs);
  setUp(UiBindings.clear);
  tearDown(() {
    UiBindings.clear();
    UiActions.clear();
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

  group('text', () {
    test('a saved text keeps how it looks — what used to be lost', () {
      final text = TextComponent(
        text: 'Hello',
        style: const UiTextStyle(
          family: 'Inter',
          size: 28,
          weight: FontWeight.w700,
          color: Color(0xFFFFCC00),
          outline: UiTextOutline(color: Color(0xFF223344), width: 2),
        ),
        styleRole: 'title',
        align: UiTextAlign.left,
        overflow: UiTextOverflow.ellipsis,
        wrap: true,
        maxLines: 2,
        revealSpeed: 30,
        size: const Size(320, 80),
      );
      final back = roundTrip('TextComponent', text, TextComponent(text: ''));

      expect(back.text, 'Hello');
      expect(back.style.size, 28);
      expect(back.style.color, const Color(0xFFFFCC00));
      expect(back.style.family, 'Inter');
      expect(back.style.outline!.width, 2);
      expect(back.styleRole, 'title');
      expect(back.align, UiTextAlign.left);
      expect(back.overflow, UiTextOverflow.ellipsis);
      expect(back.wrap, isTrue);
      expect(back.maxLines, 2);
      expect(back.revealSpeed, 30);
      expect(back.size, const Size(320, 80));
    });

    test('it reads the game, and a language key', () {
      var coins = 3;
      UiBindings.register('coins', () => coins);
      final text = TextComponent(text: 'Coins: {coins}');
      expect(text.resolve().plain, 'Coins: 3');
      coins = 4;
      expect(text.resolve().plain, 'Coins: 4', reason: 'read again');

      final key = TextComponent(text: '@hud.coins');
      expect(key.resolve().plain, 'hud.coins', reason: 'the key, unresolved');
      expect(
        key.resolve(localise: (k) => k == 'hud.coins' ? 'Münzen' : k).plain,
        'Münzen',
      );
    });

    test('parsing is kept until something it was made from changes', () {
      UiBindings.register('n', () => 1);
      final text = TextComponent(text: 'x{n}');
      final first = text.resolve();
      expect(identical(text.resolve(), first), isTrue, reason: 'kept');
      text.text = 'y{n}';
      expect(identical(text.resolve(), first), isFalse, reason: 'it changed');
    });

    test('setting what shows bumps the revision the UI watches', () {
      final text = TextComponent(text: 'a');
      final before = text.revision;
      text.text = 'b';
      expect(text.revision, greaterThan(before));
      final same = text.revision;
      text.text = 'b';
      expect(text.revision, same, reason: 'setting the same is not a change');
      text.style = const UiTextStyle(size: 9);
      expect(text.revision, greaterThan(same));
    });

    test('the style under a theme is the role, with its own on top', () {
      const theme = UiTheme(
        textStyles: {
          'body': UiTextStyle(family: 'Inter', size: 14),
          'title': UiTextStyle(size: 40),
        },
      );
      final text = TextComponent(
        text: 'x',
        styleRole: 'title',
        style: const UiTextStyle(color: Color(0xFFFF0000)),
      );
      final style = text.styleUnder(theme);
      expect(style.size, 40, reason: "the role's");
      expect(style.family, 'Inter', reason: "the theme's font");
      expect(style.color, const Color(0xFFFF0000), reason: 'its own');
    });

    test('a typewriter reveals characters, and can be hurried', () {
      final text = TextComponent(text: '[b]Hi[/b] there', revealSpeed: 10);
      final all = text.resolve();
      expect(all.length, 'Hi there'.length);
      text.revealed = 3;
      expect(all.take(text.revealed.floor()).plain, 'Hi ');
      expect(text.isRevealing, isTrue);
      text.revealAll();
      expect(text.isRevealing, isFalse);
    });
  });

  group('the text painter', () {
    /// Lays text out the way the painter does and hands back its size.
    Size measure(
      String source, {
      UiTextStyle style = const UiTextStyle(size: 20),
      UiTextLayout layout = const UiTextLayout(),
    }) {
      final painter = UiTextPainter()
        ..set(text: UiRichText.parse(source), style: style, layout: layout);
      painter.layout();
      return painter.size;
    }

    test('it wraps at the width it is given', () {
      final loose = measure('one two three four five six');
      final wrapped = measure(
        'one two three four five six',
        layout: const UiTextLayout(maxWidth: 80),
      );
      expect(wrapped.width, lessThanOrEqualTo(80.5));
      expect(wrapped.height, greaterThan(loose.height));
    });

    test('shrink brings the size down until it fits', () {
      const style = UiTextStyle(size: 40);
      const box = UiTextLayout(
        overflow: UiTextOverflow.shrink,
        maxWidth: 120,
        maxHeight: 40,
        minSize: 6,
      );
      final painter = UiTextPainter()
        ..set(
          text: UiRichText.parse('a fairly long line of text'),
          style: style,
          layout: box,
        );
      painter.layout();
      expect(painter.fittedSize, lessThan(40));
      expect(painter.size.height, lessThanOrEqualTo(40.5));

      // What already fits is left at the size it was asked for.
      final small = UiTextPainter()
        ..set(text: UiRichText.parse('hi'), style: style, layout: box);
      small.layout();
      expect(small.fittedSize, 40);
    });

    test('a line too long to break stops at the smallest size', () {
      final painter = UiTextPainter()
        ..set(
          text: UiRichText.parse('Supercalifragilisticexpialidocious'),
          style: const UiTextStyle(size: 40),
          layout: const UiTextLayout(
            overflow: UiTextOverflow.shrink,
            maxWidth: 20,
            maxHeight: 20,
            minSize: 7,
          ),
        );
      // It cannot fit, but it must stop rather than shrink forever.
      expect(painter.layout, returnsNormally);
      expect(painter.fittedSize, 7);
    });

    test('max lines and an ellipsis cut it off', () {
      final size = measure(
        'one two three four five six seven eight',
        layout: const UiTextLayout(
          maxWidth: 60,
          maxLines: 2,
          overflow: UiTextOverflow.ellipsis,
        ),
      );
      final oneLine = measure('one', layout: const UiTextLayout(maxWidth: 60));
      expect(size.height, lessThan(oneLine.height * 3));
    });

    test('it draws, outline and gradient and moving letters alike', () {
      // Painting is hard to assert on; what matters is that every path runs
      // and none of them throws on a real canvas.
      for (final source in [
        'plain',
        '[wave]moving[/wave]',
        '[rainbow]colour[/rainbow]',
        '[shake]jitter[/shake] and [pulse]fade[/pulse]',
      ]) {
        for (final style in [
          const UiTextStyle(size: 18),
          const UiTextStyle(
            size: 18,
            outline: UiTextOutline(color: Color(0xFF000000), width: 3),
          ),
          const UiTextStyle(size: 18, gradient: [Colors.red, Colors.blue]),
        ]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          final painter = UiTextPainter()
            ..set(text: UiRichText.parse(source), style: style);
          expect(
            () => painter.paint(
              canvas,
              Offset.zero,
              animation: const UiTextAnimation(seconds: 0.4),
            ),
            returnsNormally,
            reason: '$source at $style',
          );
          recorder.endRecording().dispose();
        }
      }
    });
  });

  group('buttons', () {
    late World world;
    late UiPointerSystem pointer;
    late ButtonComponent button;

    setUp(() {
      world = World();
      pointer = UiPointerSystem();
      world.addSystem(pointer);
      button = ButtonComponent(
        label: 'Play',
        size: const Size(100, 40),
        onPressed: const UiActionList([UiAction('custom:play')]),
      );
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 100, 0)),
        button,
      ], name: 'PlayButton');
    });

    void point(double x, double y, {bool down = false}) {
      pointer.pointer = UiPointer(position: Offset(x, y), isDown: down);
      world.update(1 / 60);
    }

    test('a saved button keeps its label, its look and what it does', () {
      final rich = ButtonComponent(
        label: 'Start',
        labelStyle: const UiTextStyle(size: 20, color: Color(0xFF00FF00)),
        styleRole: 'title',
        onPressed: const UiActionList([
          UiAction('scene.load', 'level_02'),
          UiAction('custom:cheer'),
        ]),
        colorRole: 'danger',
        color: const Color(0xFF123456),
        borderColor: const Color(0xFF654321),
        borderRadius: 14,
        size: const Size(180, 60),
      );
      final back = roundTrip('ButtonComponent', rich, ButtonComponent());
      expect(back.label, 'Start');
      expect(back.labelStyle.color, const Color(0xFF00FF00));
      expect(back.styleRole, 'title');
      expect(back.onPressed.actions, hasLength(2));
      expect(back.onPressed.actions.first.argument, 'level_02');
      expect(back.colorRole, 'danger');
      expect(back.color, const Color(0xFF123456));
      expect(back.borderRadius, 14);
      expect(back.size, const Size(180, 60));
    });

    test('hover, press and release — and the action runs', () {
      final pressed = <String>[];
      UiActions.register('play', (c) => pressed.add(c.entity?.name ?? ''));

      point(0, 0);
      expect(button.state, UiInteractionState.normal);

      point(200, 100);
      expect(button.state, UiInteractionState.hovered);

      point(200, 100, down: true);
      expect(button.state, UiInteractionState.pressed);
      expect(pressed, isEmpty, reason: 'not until it is let go');

      point(200, 100);
      expect(pressed, ['PlayButton']);
      expect(button.wasPressed, isTrue);
      expect(button.state, UiInteractionState.hovered);

      world.update(1 / 60);
      expect(button.wasPressed, isFalse, reason: 'only for that frame');
    });

    test('letting go off the button does not press it', () {
      final pressed = <String>[];
      UiActions.register('play', (c) => pressed.add('x'));

      point(200, 100, down: true);
      point(900, 900, down: true);
      expect(button.state, UiInteractionState.normal, reason: 'dragged off');
      point(900, 900);
      expect(pressed, isEmpty);

      // And a press that began outside does not count on the way in.
      point(900, 900, down: true);
      point(200, 100, down: true);
      point(200, 100);
      expect(pressed, isEmpty);
    });

    test('a disabled button says so and cannot be pressed', () {
      final pressed = <String>[];
      UiActions.register('play', (c) => pressed.add('x'));
      button.enabled = false;

      point(200, 100);
      expect(button.state, UiInteractionState.disabled);
      expect(button.opacity, lessThan(1), reason: 'faded, not hidden');
      point(200, 100, down: true);
      point(200, 100);
      expect(pressed, isEmpty);

      button.enabled = true;
      point(200, 100);
      expect(button.state, UiInteractionState.hovered);
    });

    test('the topmost button takes the press', () {
      final order = <String>[];
      UiActions.register('play', (c) => order.add(c.entity!.name!));
      UiActions.register('over', (c) => order.add(c.entity!.name!));
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 100, 0)),
        ButtonComponent(
          label: 'Over',
          size: const Size(100, 40),
          layer: 5,
          onPressed: const UiActionList([UiAction('custom:over')]),
        ),
      ], name: 'Above');

      point(200, 100, down: true);
      point(200, 100);
      expect(order, ['Above'], reason: 'the one on top, and only it');
    });

    test('a pointer that leaves takes the hover with it', () {
      point(200, 100);
      expect(button.state, UiInteractionState.hovered);
      pointer.pointer = UiPointer.away;
      world.update(1 / 60);
      expect(button.state, UiInteractionState.normal);
    });

    test('its colour comes from the theme, and its state tints it', () {
      const theme = UiTheme(palette: UiPalette(primary: Color(0xFF3050FF)));
      expect(button.colorUnder(theme), const Color(0xFF3050FF));
      button.state = UiInteractionState.hovered;
      final hovered = button.colorUnder(theme);
      expect(hovered, isNot(const Color(0xFF3050FF)));
      expect(
        hovered.computeLuminance(),
        greaterThan(const Color(0xFF3050FF).computeLuminance()),
      );
      button.state = UiInteractionState.pressed;
      expect(
        button.colorUnder(theme).computeLuminance(),
        lessThan(const Color(0xFF3050FF).computeLuminance()),
      );
      button.color = const Color(0xFF00FF00);
      button.state = UiInteractionState.normal;
      expect(
        button.colorUnder(theme),
        const Color(0xFF00FF00),
        reason: 'its own wins over the role',
      );
    });
  });

  group('v4 → v5', () {
    test('an old text keeps its words and the look it was drawn with', () {
      final migrated = SceneFormat.migrate({
        'version': 4,
        'entities': [
          {
            'name': 'Sign',
            'components': [
              {
                'type': 'TextComponent',
                'fields': {'textValue': 'Welcome', 'w': 200.0, 'h': 40.0},
              },
              {
                'type': 'ButtonComponent',
                'fields': {'label': 'Go', 'w': 120.0, 'h': 40.0},
              },
            ],
          },
        ],
      });
      expect(migrated['version'], SceneFormat.current);
      final components =
          (migrated['entities'] as List).single['components'] as List;

      final text =
          definitionFor(
                'TextComponent',
              ).decode((components.first as Map).cast<String, dynamic>())
              as TextComponent;
      expect(text.text, 'Welcome');
      expect(text.style.size, 16, reason: 'what the old painter drew');
      expect(text.style.color, const Color(0xFFFFFFFF));
      expect(text.size, const Size(200, 40));

      final button =
          definitionFor(
                'ButtonComponent',
              ).decode((components.last as Map).cast<String, dynamic>())
              as ButtonComponent;
      expect(button.label, 'Go');
      expect(button.labelStyle.weight, FontWeight.w700);
      expect(button.onPressed.isEmpty, isTrue, reason: 'it never had one');
    });
  });
}
