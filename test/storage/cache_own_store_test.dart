// The engine's key-value store is a file of its own. App code's
// JustStorage.standard() file and the engine's used to be one file, written
// whole by two instances that each dropped the other's keys. What the engine
// left in the app's file before 2.0 moves to its own file on the first run,
// and nothing of the app's is touched.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_database/just_database.dart' show JustDatabase;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_storage/just_storage.dart';

var _databases = 0;

Future<JustDatabase> _memoryDatabase() =>
    JustDatabase.open('cache_own_store_${_databases++}', persist: false);

Directory _folder() {
  final dir = Directory.systemTemp.createTempSync('cache_own_store_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// What is in [dir]'s `just_storage.json` now, read by a fresh instance.
Future<Map<String, String>> _file(Directory dir) => FileStorage(dir).readAll();

Future<CacheManager> _cache({
  required Directory own,
  Directory? shared,
  Future<JustStandardStorage?> Function()? openShared,
}) async {
  final cache = CacheManager(
    openStorage: () async => FileStorage(own),
    openDatabase: _memoryDatabase,
    openSharedStorage:
        openShared ?? (shared == null ? null : () async => FileStorage(shared)),
  );
  await cache.initialize();
  addTearDown(cache.dispose);
  return cache;
}

/// Serves an asset manifest listing [assets] from the test's asset bundle.
void _bundleListing(List<String> assets) {
  final manifest = const StandardMessageCodec().encodeMessage(
    <Object?, Object?>{
      for (final asset in assets)
        asset: [
          <Object?, Object?>{'asset': asset},
        ],
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        return key == 'AssetManifest.bin' ? manifest : null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    rootBundle.clear();
    _bundleListing(const []);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('a file of its own', () {
    test('the app and the engine no longer drop each other\'s keys', () async {
      final appDir = _folder();
      final engineDir = _folder();
      // The app's store, loaded before the engine starts — as the editor's
      // settings store is — and written to after the engine has written.
      final app = FileStorage(appDir);
      await app.write('app.theme', 'dark');

      final cache = await _cache(own: engineDir, shared: appDir);
      final bindings = CacheInputOverrideStore(cache);
      await cache.setString('score', '10');
      await bindings.save('input.overrides.game.p1', {'b8': '<Keyboard>/k'});

      await app.write('app.volume', '0.5');

      expect(await _file(appDir), {'app.theme': 'dark', 'app.volume': '0.5'});
      final engine = await _file(engineDir);
      expect(engine['${CacheManager.keyPrefix}score'], '10');
      expect(
        engine['just_game_engine.settings/input.overrides.game.p1'],
        isNotNull,
      );
      expect(
        File(
          '${engineDir.path}${Platform.pathSeparator}just_storage.json',
        ).existsSync(),
        isTrue,
      );
    });

    test('clearAll clears only the cache, in the engine\'s file', () async {
      final appDir = _folder();
      final engineDir = _folder();
      await FileStorage(appDir).write('app.theme', 'dark');
      final cache = await _cache(own: engineDir, shared: appDir);
      final bindings = CacheInputOverrideStore(cache);
      await cache.setString('score', '10');
      await bindings.save('input.overrides.game.p1', {'b8': 'k'});

      await cache.clearAll();

      expect(await cache.getString('score'), isNull);
      expect(await bindings.load('input.overrides.game.p1'), {'b8': 'k'});
      expect(await _file(appDir), {'app.theme': 'dark'});
    });

    test('with no shared store, there is nothing to move', () async {
      final engineDir = _folder();
      var opened = 0;
      Future<JustStandardStorage?> none() async {
        opened++;
        return null;
      }

      final first = await _cache(own: engineDir, openShared: none);
      await first.setString('score', '1');
      first.dispose();
      final second = await _cache(own: engineDir, openShared: none);
      expect(await second.getString('score'), '1');
      expect(opened, 1, reason: 'asked on the first run only');
    });
  });

  group('moving out of the shared file, once', () {
    test('the engine\'s entries move; the app\'s stay', () async {
      final appDir = _folder();
      final engineDir = _folder();
      final before = FileStorage(appDir);
      await before.write('app.theme', 'dark');
      await before.write('score', '7'); // a 1.x cache string: whose? left
      await before.write(
        '${CacheManager.keyPrefix}best',
        jsonEncode({'time': 42}),
      );
      await before.write(
        'just_game_engine.settings/input.overrides.game.p1',
        jsonEncode({'b8': '<Keyboard>/j'}),
      );
      await before.write('just_game_engine.meta/storage_version', '2');
      // Bindings saved before 2.0, bare.
      await before.write(
        'input.overrides.game.p2',
        jsonEncode({'b8': '<Keyboard>/l'}),
      );

      final cache = await _cache(own: engineDir, shared: appDir);
      final bindings = CacheInputOverrideStore(cache);

      expect(await _file(appDir), {'app.theme': 'dark', 'score': '7'});
      expect(await cache.getJson('best'), {'time': 42});
      expect(await bindings.load('input.overrides.game.p1'), {
        'b8': '<Keyboard>/j',
      });
      expect(await bindings.load('input.overrides.game.p2'), {
        'b8': '<Keyboard>/l',
      });
      final engine = await _file(engineDir);
      expect(engine['just_game_engine.meta/storage_version'], '2');
      expect(engine.containsKey('input.overrides.game.p2'), isFalse);
    });

    test('only on the first run', () async {
      final appDir = _folder();
      final engineDir = _folder();
      await FileStorage(
        appDir,
      ).write('${CacheManager.keyPrefix}best', jsonEncode({'time': 1}));

      var opened = 0;
      Future<JustStandardStorage?> openShared() async {
        opened++;
        return FileStorage(appDir);
      }

      final first = await _cache(own: engineDir, openShared: openShared);
      expect(await first.getJson('best'), {'time': 1});
      first.dispose();

      await _cache(own: engineDir, openShared: openShared);
      expect(opened, 1, reason: 'the shared file is not opened again');
    });

    test('a value the engine\'s own file has wins', () async {
      final appDir = _folder();
      final engineDir = _folder();
      await FileStorage(appDir).write('${CacheManager.keyPrefix}level', 'old');
      await FileStorage(
        engineDir,
      ).write('${CacheManager.keyPrefix}level', 'new');

      final cache = await _cache(own: engineDir, shared: appDir);
      expect(await cache.getString('level'), 'new');
      expect(await _file(appDir), isEmpty);
    });

    test('copies of bundle assets from before 2.0 are removed', () async {
      _bundleListing(const ['assets/scenes/level_01.scene.json']);
      final appDir = _folder();
      final engineDir = _folder();
      final before = FileStorage(appDir);
      await before.write('assets/scenes/level_01.scene.json', '{"old": 1}');
      await before.write('assets/notes.txt', 'not in the bundle: kept');
      await before.write('app.theme', 'dark');

      await _cache(own: engineDir, shared: appDir);
      expect(await _file(appDir), {
        'assets/notes.txt': 'not in the bundle: kept',
        'app.theme': 'dark',
      });
    });

    test('a shared file that cannot be read is tried again next run', () async {
      final appDir = _folder();
      final engineDir = _folder();
      await FileStorage(appDir).write('${CacheManager.keyPrefix}best', '"x"');

      final failed = await _cache(
        own: engineDir,
        openShared: () async => throw const StorageException('locked'),
      );
      expect(failed.isUsingMemoryFallback, isFalse);
      expect(await failed.getString('best'), isNull);
      failed.dispose();

      final next = await _cache(own: engineDir, shared: appDir);
      expect(await next.getString('best'), '"x"');
      expect(await _file(appDir), isEmpty);
    });

    test('one store passed as both: nothing moved, nothing lost', () async {
      final dir = _folder();
      final store = FileStorage(dir);
      await store.write('${CacheManager.keyPrefix}best', '"kept"');
      await store.write('input.overrides.game.p1', '{}');

      final cache = CacheManager(
        openStorage: () async => store,
        openDatabase: _memoryDatabase,
        openSharedStorage: () async => store,
      );
      await cache.initialize();
      addTearDown(cache.dispose);

      expect(await cache.getString('best'), '"kept"');
      expect(await store.read('input.overrides.game.p1'), '{}');
    });
  });
}
