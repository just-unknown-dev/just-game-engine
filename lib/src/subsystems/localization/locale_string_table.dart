/// An immutable, in-memory string table for one locale.
library;

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// LocaleStringTable
// ---------------------------------------------------------------------------

/// An immutable flat mapping from string key → localized string for one
/// [Locale].
///
/// Multiple tables may be [merged] together (e.g. one file per feature area):
/// ```dart
/// final table = LocaleStringTable.merge([uiTable, gameplayTable]);
/// ```
class LocaleStringTable {
  const LocaleStringTable({
    required this.locale,
    required Map<String, String> strings,
  }) : _strings = strings;

  /// The locale this table belongs to.
  final Locale locale;

  final Map<String, String> _strings;

  /// Number of keys in this table.
  int get size => _strings.length;

  /// Read-only view of all entries.
  Map<String, String> get entries => Map.unmodifiable(_strings);

  // ---- Lookup --------------------------------------------------------------

  /// Returns the string for [key], or `null` if absent.
  String? get(String key) => _strings[key];

  /// Returns the string for [key], or [fallback] if absent.
  String getOrFallback(String key, String fallback) =>
      _strings[key] ?? fallback;

  /// `true` if [key] exists in this table.
  bool has(String key) => _strings.containsKey(key);

  // ---- Construction --------------------------------------------------------

  /// Creates a table from a plain Dart [Map].
  factory LocaleStringTable.fromMap(Locale locale, Map<String, Object?> map) {
    final flat = <String, String>{};
    _flattenMap(map, '', flat);
    return LocaleStringTable(locale: locale, strings: flat);
  }

  /// Loads and parses a JSON asset from [assetPath].
  ///
  /// Supports flat and nested JSON:
  /// ```json
  /// { "ui": { "start": "Start Game" }, "hp": "HP" }
  /// // → keys: "ui.start", "hp"
  /// ```
  static Future<LocaleStringTable> loadAsset(
    Locale locale,
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw FormatException(
        'Localization file $assetPath must contain a JSON object.',
      );
    }
    return LocaleStringTable.fromMap(locale, decoded.cast<String, Object?>());
  }

  /// Merges [tables] into a single table (later entries win on conflict).
  factory LocaleStringTable.merge(List<LocaleStringTable> tables) {
    assert(tables.isNotEmpty, 'merge() requires at least one table.');
    final merged = <String, String>{};
    for (final t in tables) {
      merged.addAll(t._strings);
    }
    return LocaleStringTable(locale: tables.first.locale, strings: merged);
  }

  // ---- Internal ------------------------------------------------------------

  /// Recursively flattens a nested JSON map using `.` as separator.
  static void _flattenMap(
    Map<String, Object?> map,
    String prefix,
    Map<String, String> out,
  ) {
    for (final MapEntry(:key, :value) in map.entries) {
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, Object?>) {
        _flattenMap(value, fullKey, out);
      } else if (value != null) {
        out[fullKey] = value.toString();
      }
    }
  }

  @override
  String toString() =>
      'LocaleStringTable(${locale.toLanguageTag()}, $size keys)';
}
