/// The engine's store where there is no file system — the web: browser
/// storage under the engine's own key prefix — not exported.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:just_storage/just_storage.dart';

import 'namespaced_storage.dart';

/// Browser `localStorage` with every key under [engineStorageNamespace].
///
/// Not `JustStorage.standard()`: that puts its keys under `just_storage:`,
/// and the app's own `JustStorage.standard().clear()` or `readAll()` would
/// then reach the engine's cache and settings (players' key bindings). The
/// engine's keys sit beside the app's, not among them.
Future<JustStandardStorage> openEngineStorage() async =>
    engineNamespaceOf(_BrowserStorage(_localStorage));

@JS('localStorage')
external _Storage get _localStorage;

/// The Web Storage API, as much of it as the engine uses.
extension type _Storage._(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// [JustStandardStorage] over browser storage, keys as they are — the
/// namespace on top keeps the engine's apart.
final class _BrowserStorage implements JustStandardStorage {
  _BrowserStorage(this._storage);

  final _Storage _storage;
  final Map<String, StreamController<String?>> _watchers = {};

  void _changed(String key, String? value) => _watchers[key]?.add(value);

  @override
  Future<String?> read(String key) async => _storage.getItem(key);

  @override
  Future<void> write(String key, String value) async {
    try {
      _storage.setItem(key, value);
    } catch (e) {
      // Full, or storage switched off by the browser.
      throw StorageException('Could not write "$key".', cause: e);
    }
    _changed(key, value);
  }

  @override
  Future<void> delete(String key) async {
    _storage.removeItem(key);
    _changed(key, null);
  }

  @override
  Future<bool> containsKey(String key) async => _storage.getItem(key) != null;

  @override
  Future<Map<String, String>> readAll() async {
    final result = <String, String>{};
    for (var i = 0; i < _storage.length; i++) {
      final key = _storage.key(i);
      if (key == null) continue;
      final value = _storage.getItem(key);
      if (value != null) result[key] = value;
    }
    return Map.unmodifiable(result);
  }

  /// Clears every key of the page's storage. The engine never calls it on
  /// this store directly: [NamespacedStorage.clear] deletes only its own.
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
  ) async {
    final raw = _storage.getItem(key);
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw StorageException('"$key" does not hold JSON.', cause: e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('"$key" does not hold a JSON object.');
    }
    return fromJson(decoded);
  }

  @override
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) => write(key, jsonEncode(toJson(value)));

  @override
  Stream<String?> watch(String key) => _watchers
      .putIfAbsent(key, () => StreamController<String?>.broadcast())
      .stream;
}
