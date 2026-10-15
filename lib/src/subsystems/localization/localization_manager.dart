/// Central localization manager for the just_game_engine.
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter/services.dart';
import 'package:just_signals/just_signals.dart';

import 'locale_string_table.dart';
import 'string_interpolator.dart';

// ---------------------------------------------------------------------------
// LocalizationManager
// ---------------------------------------------------------------------------

/// Engine-wide localization service.
///
/// Manages locale loading, key lookup, variable interpolation, and plural
/// selection for all engine subsystems and game code.
///
/// ---
/// **Setup**
/// ```dart
/// final l10n = LocalizationManager();
///
/// // Load namespaced JSON asset files
/// await l10n.load(const Locale('en'), 'assets/l10n/ui_en.json',   ns: 'ui');
/// await l10n.load(const Locale('en'), 'assets/l10n/game_en.json', ns: 'game');
/// await l10n.load(const Locale('fr'), 'assets/l10n/ui_fr.json',   ns: 'ui');
/// await l10n.load(const Locale('fr'), 'assets/l10n/game_fr.json', ns: 'game');
///
/// l10n.setLocale(const Locale('fr'));
///
/// print(l10n.t('ui.start_game'));               // Commencer
/// print(l10n.t('game.enemies.count', {'count': 3})); // 3 ennemis
/// ```
///
/// **The engine's manager**
/// ```dart
/// // On app / engine init:
/// engine.context.localization = l10n;
///
/// // In game code with the engine at hand:
/// final text = engine.context.localization!.t('ui.back');
///
/// // In widgets under a GameWidget (which provides a LocalizationScope for
/// // the engine's manager):
/// final text = LocalizationScope.of(context).t('ui.back');
/// ```
///
/// **Fallback chain**
/// For any key looked up under locale `fr_CA`:
/// 1. `fr_CA` table
/// 2. `fr` table
/// 3. `en` table (or whichever [fallbackLocale] is set to — and its bare
///    language after it, so a fallback of `en_US` also reads `en`)
/// 4. The key itself (so missing keys are obvious in the UI)
///
/// A locale with a script keeps its own tables: `zh_Hans` and `zh_Hant`
/// do not share one, and `zh_Hans_CN` falls back to `zh_Hans`, then `zh`.
///
/// ---
/// **JSON file format** — flat or nested, auto-flattened with `.` notation:
/// ```json
/// {
///   "ui": {
///     "start_game": "Start Game",
///     "back": "Back"
///   },
///   "game.hp.label": "HP",
///   "item.count": "{count, plural, =0{No items} =1{One item} other{{count} items}}"
/// }
/// ```
class LocalizationManager {
  /// A manager with no tables yet and `en` as its current locale; keys
  /// missing from the current locale are looked up in [fallbackLocale]
  /// (`en` when null).
  LocalizationManager({Locale? fallbackLocale})
    : fallbackLocale = fallbackLocale ?? const Locale('en');

  // ---- Locale state --------------------------------------------------------

  /// Locale used when a key is missing in the active locale chain.
  final Locale fallbackLocale;

  /// Currently active locale.
  Locale get currentLocale => _currentLocale;
  Locale _currentLocale = const Locale('en');

  /// Reactive signal — emits the new [Locale] on every [setLocale] call.
  final localeChanged = Signal<Locale>(const Locale('en'));

  // ---- Storage -------------------------------------------------------------

  // _tables[localeTag][namespace] = LocaleStringTable
  final Map<String, Map<String, LocaleStringTable>> _tables = {};

  // ---- Namespace constants -------------------------------------------------

  /// Default namespace used when none is specified.
  static const String defaultNamespace = 'default';

  /// Namespace used by the Narrative subsystem.
  static const String dialogueNamespace = 'dialogue';

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads a JSON asset file under [locale] and [ns] (namespace).
  ///
  /// If [ns] is omitted, keys are registered under [defaultNamespace].
  /// Multiple files may be loaded under the same locale and namespace;
  /// they are merged, a key in a later file replacing the same key from an
  /// earlier one.
  ///
  /// Returns the loaded [LocaleStringTable] (the file's own strings).
  Future<LocaleStringTable> load(
    Locale locale,
    String assetPath, {
    String ns = defaultNamespace,
    AssetBundle? bundle,
  }) async {
    final table = await LocaleStringTable.loadAsset(
      locale,
      assetPath,
      bundle: bundle,
    );
    register(locale, table, ns: ns);
    return table;
  }

  /// Loads all locales for a list of [locales] from a path template.
  ///
  /// [pathTemplate] must contain `{locale}` which is replaced by each locale
  /// tag ([tagOf]: e.g. `'en'`, `'fr_CA'`):
  ///
  /// ```dart
  /// await l10n.loadAll(
  ///   [const Locale('en'), const Locale('fr')],
  ///   'assets/l10n/ui_{locale}.json',
  ///   ns: 'ui',
  /// );
  /// ```
  Future<void> loadAll(
    List<Locale> locales,
    String pathTemplate, {
    String ns = defaultNamespace,
    AssetBundle? bundle,
  }) async {
    for (final locale in locales) {
      final tag = tagOf(locale);
      final path = pathTemplate.replaceAll('{locale}', tag);
      try {
        await load(locale, path, ns: ns, bundle: bundle);
      } catch (e) {
        // A missing locale file is expected — the fallback chain covers it.
        // One that is there but unreadable (bad JSON, not an object) is a
        // mistake to fix, so it is reported rather than taken for missing.
        if (!_isMissingAsset(e)) {
          debugPrint('Localization: skipped $path — $e');
        }
      }
    }
  }

  /// Registers a pre-built [table] under [locale] / [ns], merged into what
  /// is already there: its keys replace the same keys, the rest stay.
  ///
  /// Use this to load dialogue strings programmatically or in tests.
  void register(
    Locale locale,
    LocaleStringTable table, {
    String ns = defaultNamespace,
  }) {
    final byNs = _tables[tagOf(locale)] ??= {};
    final existing = byNs[ns];
    byNs[ns] = existing == null
        ? table
        : LocaleStringTable.merge([existing, table]);
  }

  /// Whether strings are registered for exactly [locale] — in namespace
  /// [ns], or in any when it is null. The fallback chain is not consulted.
  bool hasTable(Locale locale, {String? ns}) {
    final byNs = _tables[tagOf(locale)];
    if (byNs == null) return false;
    return ns == null ? byNs.isNotEmpty : byNs.containsKey(ns);
  }

  /// Registers a plain `Map<String, String>` directly.
  void registerMap(
    Locale locale,
    Map<String, String> strings, {
    String ns = defaultNamespace,
  }) {
    final table = LocaleStringTable(locale: locale, strings: strings);
    register(locale, table, ns: ns);
  }

  // ---------------------------------------------------------------------------
  // Locale switching
  // ---------------------------------------------------------------------------

  /// Switches to [locale] and notifies [localeChanged].
  ///
  /// If tables for [locale] have not been loaded, the fallback chain may still
  /// serve English strings.
  void setLocale(Locale locale) {
    if (locale == _currentLocale) return;
    _currentLocale = locale;
    localeChanged.value = locale;
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Returns the localized string for [key] in the active locale.
  ///
  /// - [args] — variable substitution map (e.g. `{'playerName': 'Aria'}`).
  /// - [locale] — override the active locale for this call.
  /// - [ns] — restrict search to one namespace; if `null`, all namespaces are
  ///   searched in registration order.
  ///
  /// **Fallback chain**: active locale → language-only (`en_CA` → `en`) →
  /// [fallbackLocale] → [key] itself.
  String t(
    String key, {
    Map<String, Object?> args = const {},
    Locale? locale,
    String? ns,
  }) {
    final target = locale ?? _currentLocale;
    final raw = _lookupRaw(key, target, ns: ns) ?? key;
    return args.isEmpty ? raw : StringInterpolator.process(raw, args);
  }

  /// Convenience: looks up [key] and immediately applies [args].
  ///
  /// Identical to [t] with named [args] — provided so callers avoid the
  /// named parameter syntax for the common two-argument case.
  String tr(
    String key,
    Map<String, Object?> args, {
    Locale? locale,
    String? ns,
  }) => t(key, args: args, locale: locale, ns: ns);

  /// Returns `true` if [key] is present in the active locale (or fallback).
  bool has(String key, {Locale? locale, String? ns}) {
    return _lookupRaw(key, locale ?? _currentLocale, ns: ns) != null;
  }

  /// Returns the raw (uninterpolated) template for [key], or `null` if absent.
  String? raw(String key, {Locale? locale, String? ns}) =>
      _lookupRaw(key, locale ?? _currentLocale, ns: ns);

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Forgets every table and disposes [localeChanged]. Not to be used
  /// afterwards.
  void dispose() {
    _tables.clear();
    localeChanged.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String? _lookupRaw(String key, Locale locale, {String? ns}) {
    final candidates = _fallbackChain(locale);
    for (final tag in candidates) {
      final v = _lookupInTag(key, tag, ns: ns);
      if (v != null) return v;
    }
    return null;
  }

  String? _lookupInTag(String key, String tag, {String? ns}) {
    final byNs = _tables[tag];
    if (byNs == null) return null;

    if (ns != null) {
      return byNs[ns]?.get(key);
    }

    // Search all namespaces; prefer `default` first, then registration order
    for (final namespace in [defaultNamespace, ...byNs.keys]) {
      final v = byNs[namespace]?.get(key);
      if (v != null) return v;
    }
    return null;
  }

  /// Builds the locale fallback chain: `['fr_CA', 'fr', 'en']`
  List<String> _fallbackChain(Locale locale) {
    final chain = <String>[];
    void addWithParents(Locale l) {
      for (final tag in _parents(l)) {
        if (!chain.contains(tag)) chain.add(tag);
      }
    }

    addWithParents(locale);
    addWithParents(fallbackLocale);
    return chain;
  }

  /// [locale]'s tag, then its less specific ones: `zh_Hans_CN`, `zh_Hans`,
  /// `zh`; `fr_CA`, `fr`.
  static List<String> _parents(Locale locale) {
    final script = locale.scriptCode;
    return [
      tagOf(locale),
      if (script != null &&
          script.isNotEmpty &&
          (locale.countryCode?.isNotEmpty ?? false))
        '${locale.languageCode}_$script',
      locale.languageCode,
    ];
  }

  /// The key [locale]'s tables are kept under, and what `{locale}` in a
  /// [loadAll] path becomes: language, script and country joined by `_` —
  /// `'en'`, `'fr_CA'`, `'zh_Hans'`, `'zh_Hant_TW'`.
  static String tagOf(Locale locale) {
    final script = locale.scriptCode;
    final country = locale.countryCode;
    return [
      locale.languageCode,
      if (script != null && script.isNotEmpty) script,
      if (country != null && country.isNotEmpty) country,
    ].join('_');
  }
}

/// Whether [error] is an asset bundle's "no such asset" — as opposed to an
/// asset that exists but could not be used.
bool _isMissingAsset(Object error) =>
    error is FlutterError && error.message.startsWith('Unable to load asset');
