import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../memory/cache_manager.dart';

/// Players' own bindings, kept beside the engine's cache — a file on desktop
/// and mobile, local storage on the web.
///
/// They are engine settings, not cache entries: [CacheManager.clearAll]
/// leaves them alone. Bindings saved before 2.0, when they sat among the
/// cache's own keys, are moved across the first time they are read.
///
/// Storage that fails is logged and treated as empty: a player who cannot
/// keep their bindings still plays with the defaults.
final class CacheInputOverrideStore implements InputOverrideStore {
  /// A store keeping each key's bindings, as JSON text, in [cache]'s
  /// settings.
  CacheInputOverrideStore(this.cache);

  /// The engine cache whose settings (not its cache entries) hold the
  /// bindings.
  final CacheManager cache;

  @override
  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final raw = await cache.readSetting(key, adoptLegacy: true);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map ? json.cast<String, dynamic>() : null;
    } catch (e) {
      debugPrint('Input overrides: could not read $key ($e)');
      return null;
    }
  }

  @override
  Future<void> save(String key, Map<String, dynamic> json) async {
    try {
      await cache.writeSetting(key, jsonEncode(json), dropLegacy: true);
    } catch (e) {
      debugPrint('Input overrides: could not save $key ($e)');
    }
  }

  @override
  Future<void> clear(String key) async {
    try {
      await cache.removeSetting(key, dropLegacy: true);
    } catch (e) {
      debugPrint('Input overrides: could not clear $key ($e)');
    }
  }
}
