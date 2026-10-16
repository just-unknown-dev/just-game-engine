// The engine's store on the web: browser storage — one key per value, the
// page's storage that the app's own JustStorage.standard() also writes to
// (under its own just_storage: prefix) — seen through the engine's own key
// prefix. The keys the engine wrote there before it had a namespace move
// under it once, and the app's keys are never read as the engine's.
//
// No dart:io: this runs on the VM with an in-memory stand-in for
// localStorage, and in a browser (`flutter test --platform chrome`) against
// the real one as well.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_database/just_database.dart' show JustDatabase;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/memory/engine_storage.dart';
import 'package:just_game_engine/src/memory/namespaced_storage.dart';
import 'package:just_storage/just_storage.dart';

var _databases = 0;

Future<JustDatabase> _memoryDatabase() =>
    JustDatabase.open('cache_web_storage_${_databases++}', persist: false);

/// Browser storage as `just_storage` uses it there: every value its own
/// key, nothing rewritten whole.
class _BrowserStorage implements JustStandardStorage {
  final Map<String, String> keys = {};
  final _changes = StreamController<(String, String?)>.broadcast(sync: true);

  @override
  Future<String?> read(String key) async => keys[key];

  @override
  Future<void> write(String key, String value) async {
    keys[key] = value;
    _changes.add((key, value));
  }

  @override
  Future<void> delete(String key) async {
    keys.remove(key);
    _changes.add((key, null));
  }

  @override
  Future<void> clear() async => keys.clear();

  @override
  Future<bool> containsKey(String key) async => keys.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(keys);

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    final raw = keys[key];
    return raw == null ? null : fromJson(jsonDecode(raw));
  }

  @override
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) => write(key, jsonEncode(toJson(value)));

  @override
  Stream<String?> watch(String key) =>
      _changes.stream.where((c) => c.$1 == key).map((c) => c.$2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No bundle assets: nothing is taken for a pre-2.0 asset copy.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          return key == 'AssetManifest.bin'
              ? const StandardMessageCodec().encodeMessage(<Object?, Object?>{})
              : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('the engine\'s namespace', () {
    test('keys go under the prefix; the rest is not seen', () async {
      final browser = _BrowserStorage()..keys['app.theme'] = 'dark';
      final engine = engineNamespaceOf(browser);

      await engine.write('a', '1');
      expect(browser.keys, {
        'app.theme': 'dark',
        '${engineStorageNamespace}a': '1',
      });
      expect(await engine.read('a'), '1');
      expect(await engine.containsKey('app.theme'), isFalse);
      expect(await engine.readAll(), {'a': '1'});

      await engine.writeJson('j', {'x': 1}, (m) => m);
      expect(await engine.readJson('j', (m) => m), {'x': 1});

      final seen = <String?>[];
      final sub = engine.watch('a').listen(seen.add);
      await engine.write('a', '2');
      await engine.delete('a');
      await sub.cancel();
      expect(seen, containsAllInOrder(['2', null]));

      await engine.clear();
      expect(browser.keys, {'app.theme': 'dark'}, reason: 'the app\'s stays');
    });
  });

  group('the cache on the web', () {
    Future<CacheManager> cacheOver(_BrowserStorage browser) async {
      final cache = CacheManager(
        openStorage: () async => engineNamespaceOf(browser),
        openDatabase: _memoryDatabase,
        openSharedStorage: () async => browser,
      );
      await cache.initialize();
      addTearDown(cache.dispose);
      return cache;
    }

    test('keys written before the namespace move under it, once', () async {
      final browser = _BrowserStorage()
        ..keys['app.theme'] = 'dark'
        ..keys['${CacheManager.keyPrefix}best'] = '{"time":42}'
        ..keys['input.overrides.game.p1'] = '{"b8":"<Keyboard>/k"}';

      final cache = await cacheOver(browser);
      expect(await cache.getJson('best'), {'time': 42});
      expect(
        await CacheInputOverrideStore(cache).load('input.overrides.game.p1'),
        {'b8': '<Keyboard>/k'},
      );
      expect(browser.keys['app.theme'], 'dark');
      expect(
        browser.keys.keys.where((k) => !k.startsWith(engineStorageNamespace)),
        ['app.theme'],
      );
    });

    test('clearAll leaves the app\'s keys and the settings', () async {
      final browser = _BrowserStorage()..keys['app.theme'] = 'dark';
      final cache = await cacheOver(browser);
      final bindings = CacheInputOverrideStore(cache);
      await cache.setString('score', '3');
      await bindings.save('input.overrides.game.p1', {'b8': 'k'});

      await cache.clearAll();

      expect(await cache.getString('score'), isNull);
      expect(await bindings.load('input.overrides.game.p1'), {'b8': 'k'});
      expect(browser.keys['app.theme'], 'dark');
    });
  });

  // Only in a browser: on the VM the conditional import takes the dart:io
  // file (and path_provider), which cache_own_store_test covers.
  if (kIsWeb) {
    test(
      'in a browser, the engine\'s store is browser storage under its prefix',
      () async {
        final engine = await openEngineStorage();
        final shared = await openSharedStorage();
        await engine.write('probe', 'yes');
        addTearDown(() => engine.delete('probe'));
        expect(await shared.read('${engineStorageNamespace}probe'), 'yes');
        expect(await shared.read('probe'), isNull);
      },
    );
  }
}
