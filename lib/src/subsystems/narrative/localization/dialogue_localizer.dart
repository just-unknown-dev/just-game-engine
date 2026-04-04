/// Dialogue localization — delegates to the central [LocalizationManager].
library;

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:just_signals/just_signals.dart';

import '../../../subsystems/localization/localization_manager.dart';

// ---------------------------------------------------------------------------
// DialogueLocalizer
// ---------------------------------------------------------------------------

/// Resolves localized dialogue strings at runtime.
///
/// All strings are stored under the [LocalizationManager.dialogueNamespace]
/// (`'dialogue'`) namespace inside a shared [LocalizationManager] instance.
/// This means locale switches are automatically coordinated with the rest of
/// the engine — there is no separate locale state to keep in sync.
///
/// **Quick start**
/// ```dart
/// // 1. Set up the central manager once (typically in your game init):
/// final l10n = LocalizationManager();
/// LocalizationManager.instance = l10n;
/// await l10n.load(const Locale('en'), 'assets/data/dialogue_en.json',
///     ns: LocalizationManager.dialogueNamespace);
/// await l10n.load(const Locale('fr'), 'assets/data/dialogue_fr.json',
///     ns: LocalizationManager.dialogueNamespace);
///
/// // 2. Create a DialogueLocalizer backed by the same manager:
/// final loc = DialogueLocalizer(manager: l10n);
///
/// // 3. Switch locale via the central manager (or directly):
/// l10n.setLocale(const Locale('fr'));
/// print(loc.localize('innkeeper.welcome')); // Bonjour, voyageur!
/// ```
///
/// **Legacy / standalone use** — if no [manager] is supplied the localizer
/// creates its own internal [LocalizationManager].  Asset path template
/// `{basePath}_{languageCode}[_{countryCode}].json` is preserved for
/// backwards-compatible [loadLocale] calls.
class DialogueLocalizer {
  DialogueLocalizer({LocalizationManager? manager, String? basePath})
    : _manager = manager ?? LocalizationManager(),
      _basePath = basePath ?? 'assets/data/dialogue';

  final LocalizationManager _manager;
  final String _basePath;

  /// Currently active locale (delegates to the underlying manager).
  Locale get currentLocale => _manager.currentLocale;

  /// Emits the new [Locale] whenever [setLocale] / [loadLocale] changes it.
  ///
  /// This is the same signal as [LocalizationManager.localeChanged] on the
  /// backing manager, so listeners registered on either are equivalent.
  Signal<Locale> get localeSignal => _manager.localeChanged;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads (and caches) the dialogue string table for [locale].
  ///
  /// Falls back to the bare language code and then to English if the exact
  /// locale file is missing.  Uses the [LocalizationManager.dialogueNamespace].
  Future<void> loadLocale(Locale locale, {AssetBundle? bundle}) async {
    final candidates = [
      _assetPath(locale),
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty)
        _assetPath(Locale(locale.languageCode)),
      if (locale.languageCode != 'en') _assetPath(const Locale('en')),
    ];

    for (final path in candidates) {
      try {
        await _manager.load(
          locale,
          path,
          ns: LocalizationManager.dialogueNamespace,
          bundle: bundle,
        );
        return;
      } catch (_) {
        continue;
      }
    }
    // No file found — at minimum update the locale so signals fire.
    _manager.setLocale(locale);
  }

  /// Registers a string table directly from a [Map] (useful for tests or
  /// embedded content).
  void loadFromMap(Map<String, String> strings, Locale locale) {
    _manager.registerMap(
      locale,
      strings,
      ns: LocalizationManager.dialogueNamespace,
    );
    _manager.setLocale(locale);
  }

  // ---------------------------------------------------------------------------
  // Locale switching
  // ---------------------------------------------------------------------------

  /// Switches to [locale].
  ///
  /// If the locale has not been loaded yet, calls [loadLocale] automatically.
  Future<void> setLocale(Locale locale, {AssetBundle? bundle}) async {
    if (_manager.currentLocale == locale) return;
    // Attempt load; if files are missing the fallback chain handles it.
    await loadLocale(locale, bundle: bundle);
  }

  // ---------------------------------------------------------------------------
  // String resolution
  // ---------------------------------------------------------------------------

  /// Returns the localized string for [key].
  ///
  /// Falls back to [fallback] if provided, otherwise returns [key] itself.
  String localize(String key, {String? fallback}) {
    final result = _manager.raw(key, ns: LocalizationManager.dialogueNamespace);
    return result ?? fallback ?? key;
  }

  /// Returns `true` if [key] is present in the current locale table.
  bool hasKey(String key) =>
      _manager.has(key, ns: LocalizationManager.dialogueNamespace);

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _assetPath(Locale locale) {
    final country = locale.countryCode;
    final tag = (country != null && country.isNotEmpty)
        ? '${locale.languageCode}_$country'
        : locale.languageCode;
    return '${_basePath}_$tag.json';
  }
}
