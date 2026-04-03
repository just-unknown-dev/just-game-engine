/// Central localization manager for the just_game_engine.
library;

import 'dart:ui' show Locale;

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
/// **Global instance**
/// ```dart
/// // On app / engine init:
/// LocalizationManager.instance = l10n;
///
/// // Anywhere in game code:
/// final text = LocalizationManager.instance.t('ui.back');
/// ```
///
/// **Fallback chain**
/// For any key looked up under locale `fr_CA`:
/// 1. `fr_CA` table
/// 2. `fr` table
/// 3. `en` table (or whichever [fallbackLocale] is set to)
/// 4. The key itself (so missing keys are obvious in the UI)
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
  LocalizationManager({Locale? fallbackLocale})
    : fallbackLocale = fallbackLocale ?? const Locale('en');

  // ---- Global instance -----------------------------------------------------

  /// Optional global singleton — set this once on engine/app init for
  /// convenient access via `LocalizationManager.instance`.
  static LocalizationManager? instance;

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

  // Merged view per locale-tag (invalidated when tables change)
  final Map<String, LocaleStringTable> _merged = {};

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
  /// Multiple files may be loaded under the same locale; they are merged
  /// lazily on first access.
  ///
  /// Returns the loaded [LocaleStringTable].
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
  /// tag (e.g. `'en'`, `'fr_CA'`):
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
      final tag = _tag(locale);
      final path = pathTemplate.replaceAll('{locale}', tag);
      try {
        await load(locale, path, ns: ns, bundle: bundle);
      } catch (_) {
        // Missing locale file — silently skip, fallback chain handles it.
      }
    }
  }

  /// Registers a pre-built [table] under [locale] / [ns].
  ///
  /// Use this to load dialogue strings programmatically or in tests.
  void register(
    Locale locale,
    LocaleStringTable table, {
    String ns = defaultNamespace,
  }) {
    final tag = _tag(locale);
    (_tables[tag] ??= {})[ns] = table;
    _merged.remove(tag); // invalidate cached merge
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

  void dispose() {
    _tables.clear();
    _merged.clear();
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
    final full = _tag(locale);
    chain.add(full);
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      chain.add(locale.languageCode); // language-only fallback
    }
    final fb = _tag(fallbackLocale);
    if (!chain.contains(fb)) chain.add(fb);
    return chain;
  }

  /// Converts a [Locale] to a cache key string (`'en'`, `'fr_CA'`).
  static String _tag(Locale locale) {
    final country = locale.countryCode;
    return (country != null && country.isNotEmpty)
        ? '${locale.languageCode}_$country'
        : locale.languageCode;
  }
}
