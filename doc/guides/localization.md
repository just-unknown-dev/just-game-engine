# Localization

_Audio & content_ · Translate your game with a LocalizationManager on engine.context.localization: string files per locale, namespaces, fallbacks, plurals, selects and widgets that follow the locale.

A `LocalizationManager` holds your string tables and the current locale. Set it as `engine.context.localization` and every `GameWidget` showing the engine provides it to the widgets drawn over the game, and the dialogue system can use the same strings.

## String files

Strings are JSON files, one per locale (and per namespace, if you use them). Keys can be flat or nested; nested keys are joined with dots, so `{"ui": {"back": "Back"}}` gives the key `ui.back`. List the folder under `flutter: assets:`.

```json assets/l10n/ui_en.json
{
  "ui": {
    "start_game": "Start game",
    "back": "Back"
  },
  "hud.greeting": "Welcome back, {name}!",
  "hud.coins": "{count, plural, =0{No coins} =1{One coin} other{{count} coins}}",
  "hud.arrived": "{who, select, male{He arrived} female{She arrived} other{They arrived}}"
}
```

## Set up the manager

```dart lib/l10n.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Locale;
import 'package:just_game_engine/just_game_engine.dart';

Future<void> setUpLocalization(Engine engine) async {
  final l10n = LocalizationManager(); // falls back to English
  await l10n.loadAll(
    const [Locale('en'), Locale('fr')],
    'assets/l10n/ui_{locale}.json',
    ns: 'ui',
  );
  l10n.setLocale(const Locale('fr'));
  engine.context.localization = l10n; // before building the GameWidget

  debugPrint(l10n.t('ui.back'));
  debugPrint(l10n.t('hud.coins', args: {'count': 3}));
  debugPrint(l10n.tr('hud.greeting', {'name': 'Aria'}));
}
```

- `load(locale, path, ns: ...)` loads one file; `loadAll(locales, template, ns: ...)` loads one per locale, replacing `{locale}` with the locale's tag (`en`, `fr_CA`, `zh_Hans`). A missing file is skipped quietly; a file that is there but malformed is logged.
- `registerMap(locale, strings)` and `register(locale, table)` add strings from code, for tests or downloaded content.
- `t(key, args: ..., locale: ..., ns: ...)` looks a key up; `tr(key, args)` is the short form. `has(key)` and `raw(key)` read without filling anything in.
- `setLocale(locale)` switches language and notifies `localeChanged`, a signal the widgets below listen to.

## Namespaces

A namespace keeps one area's strings in tables of their own: `ui` for menus, `game` for gameplay, `dialogue` for lines (`LocalizationManager.dialogueNamespace`). Without `ns:` strings go to `LocalizationManager.defaultNamespace`.

A namespace does not prefix keys. `t('ui.back')` searches every namespace, the default one first and then the others in the order they were loaded; `t('ui.back', ns: 'ui')` searches only `ui`. Files loaded for the same locale and namespace merge, and a key in a later file replaces the same key from an earlier one.

## Fallbacks

For a key looked up in `fr_CA`, the manager tries the `fr_CA` tables, then `fr`, then the fallback locale (`en` unless you pass `LocalizationManager(fallbackLocale: ...)`), and finally returns the key itself, so missing strings are obvious on screen. A locale with a script keeps its own tables: `zh_Hans_CN` falls back to `zh_Hans`, then `zh`, and its file is named like `ui_zh_Hans.json`.

## Variables, plurals and selects

`{name}` is replaced by the `name` argument. Two ICU-style forms choose text by an argument:

- `{count, plural, =0{...} =1{...} one{...} other{...}}`: an exact `=N` wins, then `one` for exactly 1, then `other`. A count with a fraction matches only an `=N` equal to it, so 1.5 takes `other`. There are no `few` or `many` categories.
- `{who, select, male{...} female{...} other{...}}`: the branch named by the argument's value, else `other`.

Variables inside a branch are filled in too, as in `other{{count} coins}`. Forms are resolved one level deep: a plural inside a plural is not.

## In widgets

The widgets are in `package:just_game_engine/widgets.dart`. Under a `GameWidget` they find the engine's manager themselves; elsewhere, wrap your widgets in `LocalizationScope(manager: l10n, child: ...)`.

```dart lib/menu.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LocalizedText('ui.start_game'),
      LocalizationBuilder(
        builder: (context, l10n) =>
            Text(l10n.t('hud.coins', args: {'count': 3})),
      ),
      const LocaleSelector(
        locales: [Locale('en'), Locale('fr')],
        labels: {'en': 'English', 'fr': 'Français'},
      ),
    ],
  );
}
```

- `LocalizedText(key, args: ..., ns: ..., style: ...)` is a `Text` that rebuilds when the locale changes.
- `LocalizationBuilder` rebuilds its subtree on every locale change and hands you the manager.
- `LocaleSelector` shows a tappable label for each locale and switches to it.
- `context.t(key)` and `context.tr(key, args)` (the `BuildContextLocalization` extension) look a key up in the nearest scope. They do not rebuild when the locale changes, so use them inside a `LocalizationBuilder`.
- `LocalizationScope.of(context)` returns the manager itself.

Strings resolved once stay as they were when the locale changes: for example, `SubtitleTrack.localized` resolves its cues when it is made. See [Dialogue & subtitles](/docs/dialogue).
