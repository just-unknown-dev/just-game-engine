import 'package:flutter/foundation.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../memory/cache_manager.dart';

/// Players' own bindings, kept in the engine's cache — a file on desktop
/// and mobile, local storage on the web.
///
/// Storage that fails is logged and treated as empty: a player who cannot
/// keep their bindings still plays with the defaults.
final class CacheInputOverrideStore implements InputOverrideStore {
  CacheInputOverrideStore(this.cache);

  final CacheManager cache;

  @override
  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final json = await cache.getJson(key);
      return json is Map ? json.cast<String, dynamic>() : null;
    } catch (e) {
      debugPrint('Input overrides: could not read $key ($e)');
      return null;
    }
  }

  @override
  Future<void> save(String key, Map<String, dynamic> json) async {
    try {
      await cache.setJson(key, json);
    } catch (e) {
      debugPrint('Input overrides: could not save $key ($e)');
    }
  }

  @override
  Future<void> clear(String key) async {
    try {
      await cache.remove(key);
    } catch (e) {
      debugPrint('Input overrides: could not clear $key ($e)');
    }
  }
}
