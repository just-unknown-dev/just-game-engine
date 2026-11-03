/// A key-value store inside another, under a prefix — not exported.
library;

import 'package:just_storage/just_storage.dart';

/// The prefix the engine's keys get in browser storage, which the app's own
/// `JustStorage.standard()` shares on the web.
///
/// Not one of the engine's key prefixes (`just_game_engine.cache/`, …), so
/// the keys the engine wrote before it had a store of its own are told
/// apart from the ones it writes now.
const String engineStorageNamespace = 'just_game_engine/';

/// The engine's store within [browser]: every key under
/// [engineStorageNamespace].
JustStandardStorage engineNamespaceOf(JustStandardStorage browser) =>
    NamespacedStorage(browser, engineStorageNamespace);

/// [inner], seen through [namespace]: `write('a', …)` writes `'$namespace'
/// 'a'`, and [readAll] and [clear] see only keys under the namespace (with
/// it taken off) — never the rest of [inner].
///
/// On the web, where `just_storage` keeps every value as its own key in
/// `localStorage` rather than rewriting one file, this is what gives the
/// engine a store of its own.
final class NamespacedStorage implements JustStandardStorage {
  /// A view of [inner] holding only the keys that start with [namespace];
  /// nothing is read or copied until it is used.
  NamespacedStorage(this.inner, this.namespace);

  /// The store holding the keys.
  final JustStandardStorage inner;

  /// Put in front of every key.
  final String namespace;

  String _key(String key) => '$namespace$key';

  @override
  Future<String?> read(String key) => inner.read(_key(key));

  @override
  Future<void> write(String key, String value) => inner.write(_key(key), value);

  @override
  Future<void> delete(String key) => inner.delete(_key(key));

  @override
  Future<bool> containsKey(String key) => inner.containsKey(_key(key));

  @override
  Future<Map<String, String>> readAll() async {
    final all = await inner.readAll();
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in all.entries)
        if (key.startsWith(namespace)) key.substring(namespace.length): value,
    });
  }

  /// Removes this namespace's keys, and nothing else of [inner].
  @override
  Future<void> clear() async {
    for (final key in (await readAll()).keys) {
      await delete(key);
    }
  }

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) => inner.readJson(_key(key), fromJson);

  @override
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) => inner.writeJson(_key(key), value, toJson);

  @override
  Stream<String?> watch(String key) => inner.watch(_key(key));
}
