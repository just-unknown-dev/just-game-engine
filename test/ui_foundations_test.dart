// The foundations under in-game UI: a text style that survives a save, tags
// in text, values read from a running game, and actions a scene can hold.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text style', () {
    test('everything set survives a save — the whole point of it', () {
      const style = UiTextStyle(
        family: 'PressStart2P',
        size: 22,
        weight: FontWeight.w700,
        italic: true,
        color: Color(0xFFFFCC00),
        letterSpacing: 1.5,
        lineHeight: 1.2,
        outline: UiTextOutline(color: Color(0xFF102030), width: 3),
        shadow: UiTextShadow(
          color: Color(0x80000000),
          offset: Offset(2, 3),
          blur: 4,
        ),
      );
      final back = UiTextStyle.fromJson(style.toJson());
      expect(back, style, reason: 'nothing is lost on the way to a file');
      expect(back.toTextStyle().fontSize, 22);
      expect(back.toTextStyle().fontStyle, FontStyle.italic);
      expect(back.toTextStyle().shadows, hasLength(1));
    });

    test('what is not set is not written, and falls back when read', () {
      const style = UiTextStyle(size: 12);
      expect(style.toJson().keys, ['size']);
      expect(style.color, isNull);
      // Unset fields come from the fallback only when it is drawn.
      expect(style.toTextStyle().color, const Color(0xFFFFFFFF));
      expect(style.toTextStyle().fontSize, 12);
      expect(const UiTextStyle().isEmpty, isTrue);
      expect(UiTextStyle.fromJson(const {}), const UiTextStyle());
    });

    test('one style layers over another, and a field can be taken back', () {
      const theme = UiTextStyle(family: 'Inter', size: 16, color: Colors.white);
      const own = UiTextStyle(size: 24);
      final merged = own.over(theme);
      expect(merged.family, 'Inter', reason: "the theme's, untouched");
      expect(merged.size, 24, reason: 'its own wins');
      expect(merged.color, Colors.white);
      expect(merged.without('size').over(theme).size, 16);
    });

    test('a gradient keeps a colour for anything that ignores it', () {
      const style = UiTextStyle(gradient: [Colors.red, Colors.blue]);
      expect(style.toTextStyle().color, Colors.red);
      expect(UiTextStyle.fromJson(style.toJson()).gradient, hasLength(2));
    });

    test('a weight from a file lands on one Flutter knows', () {
      final style = UiTextStyle.fromJson(const {'weight': 640});
      expect(style.weight, FontWeight.w600);
    });
  });

  group('rich text', () {
    test('tags nest, and the plain text has none of them in it', () {
      final text = UiRichText.parse(
        'Press [b]Space[/b] for [color=#ffcc00]coins[/color]!',
      );
      expect(text.plain, 'Press Space for coins!');
      expect(text.spans.map((s) => s.text), [
        'Press ',
        'Space',
        ' for ',
        'coins',
        '!',
      ]);
      expect(text.spans[1].style.weight, FontWeight.w700);
      expect(text.spans[3].style.color, const Color(0xFFFFCC00));
      expect(text.spans[4].style.color, isNull, reason: 'the tag closed');
    });

    test('a tag inside a tag keeps both', () {
      final text = UiRichText.parse('[b]bold [i]and italic[/i][/b]');
      final inner = text.spans.last;
      expect(inner.style.weight, FontWeight.w700);
      expect(inner.style.italic, isTrue);
    });

    test('a tag nobody knows is left on screen, not swallowed', () {
      for (final source in [
        'a [nonsense] b',
        'a [b b',
        'a [/b] b',
        'a [color] b',
        'cost: [50] gold',
      ]) {
        final text = UiRichText.parse(source);
        expect(
          text.plain,
          source,
          reason: 'an author sees their mistake: $source',
        );
      }
    });

    test('colours are read as names or hex, of any length', () {
      Color? colorOf(String tag) =>
          UiRichText.parse('[color=$tag]x[/color]').spans.first.style.color;
      expect(colorOf('#f00'), const Color(0xFFFF0000));
      expect(colorOf('#00ff00'), const Color(0xFF00FF00));
      expect(colorOf('#8000ff00'), const Color(0x8000FF00));
      expect(colorOf('red'), isNotNull);
      expect(colorOf('wat'), isNull, reason: 'left as it was');
    });

    test('an icon is a span of its own and counts as one character', () {
      final text = UiRichText.parse('Got [icon=coin] x3');
      final icon = text.spans.firstWhere((s) => s.isIcon);
      expect(icon.icon, 'coin');
      expect(text.length, 'Got  x3'.length + 1);
    });

    test('effects and links ride on the spans under them', () {
      final text = UiRichText.parse('[wave]hi[/wave] [link=shop]buy[/link]');
      expect(text.spans.first.effect, UiTextEffect.wave);
      expect(text.spans.last.link, 'shop');
      expect(text.needsPainter, isTrue, reason: 'a wave must be painted');
      expect(
        UiRichText.parse('plain').needsPainter,
        isFalse,
        reason: 'plain text is left to Flutter, for a reader to read',
      );
    });

    test('a typewriter takes characters, not tags', () {
      final text = UiRichText.parse('[b]Hello[/b] world');
      expect(text.length, 'Hello world'.length);
      final part = text.take(7);
      expect(part.plain, 'Hello w');
      expect(part.spans.first.style.weight, FontWeight.w700);
      expect(text.take(0).isEmpty, isTrue);
      expect(text.take(999).length, text.length);
    });

    test('it becomes a TextSpan for the Flutter side', () {
      final span =
          UiRichText.parse('a [b]b[/b]').toTextSpan(const UiTextStyle(size: 14))
              as TextSpan;
      expect(span.children, hasLength(2));
      expect(
        (span.children!.last as TextSpan).style!.fontWeight,
        FontWeight.w700,
      );
      expect((span.children!.last as TextSpan).style!.fontSize, 14);
    });
  });

  group('bindings', () {
    setUp(UiBindings.clear);
    tearDown(UiBindings.clear);

    test('a name reads what the game says, and an unknown one shows', () {
      var coins = 7;
      UiBindings.register('coins', () => coins);
      expect(UiBindings.interpolate('Coins: {coins}'), 'Coins: 7');
      coins = 8;
      expect(UiBindings.interpolate('Coins: {coins}'), 'Coins: 8');
      expect(
        UiBindings.interpolate('{nope}'),
        '{nope}',
        reason: 'a missing binding is visible, not blank',
      );
      expect(UiBindings.namesIn('{a} and {b:n0}'), ['a', 'b']);
    });

    test('formats: clocks, decimals, thousands, percentages', () {
      UiBindings.register('t', () => 91.4);
      UiBindings.register('n', () => 1234567.0);
      UiBindings.register('f', () => 0.256);
      expect(UiBindings.interpolate('{t:mm:ss}'), '01:31');
      expect(UiBindings.interpolate('{t:m:ss.S}'), '1:31.4');
      expect(UiBindings.format(3725.0, 'hh:mm:ss'), '01:02:05');
      expect(UiBindings.interpolate('{n:n0}'), '1,234,567');
      expect(UiBindings.interpolate('{f:0.00}'), '0.26');
      expect(UiBindings.interpolate('{f:%0}'), '26%');
      expect(UiBindings.format(4.0), '4', reason: 'no stray .0');
      expect(UiBindings.format(null), '');
    });

    test('{{ writes a brace, and an unclosed one is text', () {
      expect(UiBindings.interpolate('{{coins}'), '{coins}');
      expect(UiBindings.interpolate('a {b'), 'a {b');
    });

    test('self.* reads the entity the text belongs to', () {
      final world = World();
      final hero = world.createEntity(name: 'Hero');
      UiBindings.registerBuiltIns();
      expect(UiBindings.interpolate('{self.name}', self: hero), 'Hero');
      expect(
        UiBindings.interpolate('{self.name}'),
        '',
        reason: 'no entity, nothing to read',
      );
      expect(UiBindings.names, contains('self.name'));
    });

    test('a number for a bar, from anything that is one', () {
      UiBindings.register('hp', () => 30);
      UiBindings.register('max', () => 40);
      UiBindings.register('word', () => 'nope');
      expect(UiBindings.readNumber('hp'), 30);
      expect(UiBindings.fraction('hp', 'max'), closeTo(0.75, 1e-9));
      expect(UiBindings.readNumber('word'), isNull);
      expect(UiBindings.fraction('hp', 'word'), 0, reason: 'no maximum');
    });
  });

  group('actions', () {
    setUp(UiActions.clear);
    tearDown(UiActions.clear);

    test('a list round-trips, and runs in order', () {
      const list = UiActionList([
        UiAction('signal', 'open'),
        UiAction('custom:log', 'hello'),
      ]);
      expect(UiActionList.fromJson(list.toJson()), list);
      expect(list.toJson().first, {'kind': 'signal', 'arg': 'open'});

      final ran = <String>[];
      UiActions.register('log', (c) => ran.add('log:${c.argument}'));
      final signals = <String>[];
      final stop = TimelineSignals.stream.listen(signals.add);
      addTearDown(stop.cancel);

      list.run(UiActionContext(world: World()));
      expect(signals, ['open']);
      expect(ran, ['log:hello']);
    });

    test('built-ins reach the game through the host', () {
      final done = <String>[];
      UiActions.host = UiActionHost(
        loadScene: (s) => done.add('scene:$s'),
        pause: () => done.add('pause'),
        showUi: (name, visible) => done.add('ui:$name=$visible'),
        back: () => done.add('back'),
      );
      final world = World();
      for (final action in const [
        UiAction('scene.load', 'level_02'),
        UiAction('game.pause'),
        UiAction('ui.hide', 'HUD'),
        UiAction('ui.toggle', 'Menu'),
        UiAction('ui.back'),
      ]) {
        UiActions.run(action, UiActionContext(world: world));
      }
      expect(done, [
        'scene:level_02',
        'pause',
        'ui:HUD=false',
        'ui:Menu=null',
        'back',
      ]);
    });

    test('an action nobody can carry out does nothing at all', () {
      final world = World();
      // No host, no handler, an unknown kind: none of these may throw
      // mid-frame — a button is not worth taking the game down for.
      for (final action in const [
        UiAction('scene.load', 'x'),
        UiAction('custom:missing'),
        UiAction('from.a.newer.engine'),
        UiAction('none'),
      ]) {
        expect(
          () => UiActions.run(action, UiActionContext(world: world)),
          returnsNormally,
        );
      }
    });

    test('a timeline action plays the entity it names', () {
      registerCoreCodecs();
      final world = World();
      registerSpriteSystems(world);
      final player = TimelinePlayerComponent(
        inline: TimelineAsset(duration: 1),
      );
      world.createEntityWithComponents([
        TransformComponent(),
        player,
      ], name: 'Door');
      world.update(0);
      expect(player.isPlaying, isFalse);
      UiActions.run(
        const UiAction('timeline.play', 'Door'),
        UiActionContext(world: world),
      );
      world.update(0);
      expect(player.isPlaying, isTrue);
    });
  });

  group('theme', () {
    test('it round-trips, and a role nobody named still reads', () {
      const theme = UiTheme(
        name: 'arcade',
        palette: UiPalette(primary: Color(0xFF00FF88)),
        textStyles: {'body': UiTextStyle(family: 'Inter', size: 14)},
        radius: 12,
        spacing: 6,
        sounds: UiSounds(press: 'assets/sfx/click.wav'),
      );
      final back = UiTheme.parse(theme.encode());
      expect(back.name, 'arcade');
      expect(back.palette.primary, const Color(0xFF00FF88));
      expect(back.textStyles['body']!.size, 14);
      expect(back.radius, 12);
      expect(back.sounds.press, 'assets/sfx/click.wav');

      // A title takes the body's family but a title's size and weight.
      final title = back.textStyle('title');
      expect(title.family, 'Inter');
      expect(title.size, 32);
      expect(title.weight, FontWeight.w700);
    });

    test('it becomes a real ThemeData for the Flutter layer', () {
      const theme = UiTheme(
        palette: UiPalette(primary: Color(0xFF123456)),
        textStyles: {'body': UiTextStyle(family: 'Inter')},
      );
      final data = theme.toThemeData();
      expect(data.colorScheme.primary, const Color(0xFF123456));
      expect(data.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(data.textTheme.displayLarge!.fontSize, 32);
    });

    test('a theme that will not load is the fallback, not a crash', () async {
      UiThemes.evict();
      UiThemes.loader = (path) async => throw StateError('no $path');
      addTearDown(UiThemes.useBundle);
      expect(await UiThemes.load('gone.uitheme.json'), UiThemes.fallback);
      expect(await UiThemes.load(''), UiThemes.fallback);

      UiThemes.loader = (path) async => const UiTheme(name: 'ok');
      expect((await UiThemes.load('a.uitheme.json')).name, 'ok');
      expect(UiThemes.cached('a.uitheme.json')!.name, 'ok');
      UiThemes.evict('a.uitheme.json');
      expect(UiThemes.cached('a.uitheme.json'), isNull);
    });
  });

  group('fonts', () {
    tearDown(UiFonts.reset);

    test('files are grouped into families by their names', () {
      final families = UiFonts.familiesIn([
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/PressStart2P.ttf',
        'assets/sprites/player.png',
      ]);
      expect(families.keys, containsAll(['Inter', 'PressStart2P']));
      expect(families['Inter'], hasLength(2));
      expect(families.containsKey('player'), isFalse, reason: 'not a font');
    });

    test('a font that will not load leaves text in the fallback', () async {
      UiFonts.read = (path) async => throw StateError('no $path');
      await UiFonts.ensureLoaded('Ghost', ['assets/fonts/Ghost.ttf']);
      expect(UiFonts.isLoaded('Ghost'), isFalse);
      expect(UiFonts.families, isEmpty);
      // And asking for nothing is not an error.
      await UiFonts.ensureLoaded('', const []);
    });
  });
}
