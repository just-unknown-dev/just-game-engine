// The engine's cache: any key works, it keeps to its own entries in the app's
// store — players' key bindings and the app's own settings survive clearAll —
// a store that fails does not take the working one down with it, and a
// failed write is not answered with the stale value underneath.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_database/just_database.dart' show JustDatabase;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_storage/just_storage.dart';

var _databases = 0;

/// A database that lives only in memory, fresh for each call.
Future<JustDatabase> _memoryDatabase() =>
    JustDatabase.open('fx_misc_cache_${_databases++}', persist: false);

FileStorage _fileStore() {
  final dir = Directory.systemTemp.createTempSync('fx_misc_cache_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return FileStorage(dir);
}

Future<CacheManager> _cache(
  JustStandardStorage store, {
  Future<JustDatabase> Function()? openDatabase,
}) async {
  final cache = CacheManager(
    openStorage: () async => store,
    openDatabase: openDatabase ?? _memoryDatabase,
  );
  await cache.initialize();
  addTearDown(cache.dispose);
  return cache;
}

/// A file store whose writes can be made to fail, as a full disk would.
class _FlakyStore extends FileStorage {
  _FlakyStore(super.directory);

  bool failWrites = false;

  @override
  Future<void> write(String key, String value) {
    if (failWrites) throw const StorageException('disk full');
    return super.write(key, value);
  }
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

  group('keys', () {
    test(
      'any string is a key: spaces, symbols, quotes, other scripts',
      () async {
        final cache = await _cache(_fileStore());
        expect(cache.isBinaryInMemory, isFalse);

        const keys = [
          'Player Idle.png',
          'assets/maps/level map 1.tmx',
          'a@b+c(1)[2]',
          "it's",
          r'back\slash',
          'ñandú/straße/日本',
          '50%',
          '',
        ];
        for (var i = 0; i < keys.length; i++) {
          await cache.setBinary(keys[i], Uint8List.fromList([i]));
        }
        for (var i = 0; i < keys.length; i++) {
          expect(await cache.getBinary(keys[i]), [i], reason: keys[i]);
        }
        await cache.remove('Player Idle.png');
        expect(await cache.getBinary('Player Idle.png'), isNull);
        expect(await cache.getBinaryCacheSize(), keys.length - 1);
      },
    );

    test('in memory too', () async {
      final cache = CacheManager(forceMemoryFallback: true);
      await cache.initialize();
      addTearDown(cache.dispose);
      await cache.setBinary('Player Idle.png', Uint8List.fromList([5]));
      expect(await cache.getBinary('Player Idle.png'), [5]);
    });

    test('a store that cannot open leaves the cache in memory', () async {
      final cache = CacheManager(
        openStorage: () async => throw StateError('no storage here'),
      );
      await cache.initialize();
      addTearDown(cache.dispose);
      expect(cache.isUsingMemoryFallback, isTrue);
      await cache.setString('a', 'b');
      expect(await cache.getString('a'), 'b');
    });

    test('two long keys that differ only at the end stay apart', () async {
      final cache = await _cache(_fileStore());
      final stem = 'x' * 700;
      await cache.setBinary('${stem}a', Uint8List.fromList([1]));
      await cache.setBinary('${stem}b', Uint8List.fromList([2]));
      expect(await cache.getBinary('${stem}a'), [1]);
      expect(await cache.getBinary('${stem}b'), [2]);
    });

    test('a key the cache always accepted still finds its old row', () async {
      // Written as 1.x wrote it: the key as it is.
      late JustDatabase db;
      final cache = await _cache(
        _fileStore(),
        openDatabase: () async {
          db = await _memoryDatabase();
          await db.execute(
            'CREATE TABLE binary_cache (key TEXT PRIMARY KEY, data BLOB, '
            'timestamp INTEGER)',
          );
          await db.execute(
            "INSERT INTO binary_cache (key, data, timestamp) VALUES "
            "('saves/slot-1.bin', '${base64Encode([4, 2])}', 1)",
          );
          return db;
        },
      );
      expect(await cache.getBinary('saves/slot-1.bin'), [4, 2]);
    });
  });

  group('its own entries only', () {
    test('clearAll leaves the app\'s keys and players\' bindings', () async {
      final store = _fileStore();
      final cache = await _cache(store);
      final bindings = CacheInputOverrideStore(cache);

      await store.write('app.theme', 'dark'); // the app's own setting
      await cache.setString('score', '10');
      await bindings.save('input.overrides.game.p1', {'b8': '<Keyboard>/k'});

      await cache.clearAll();

      expect(await cache.getString('score'), isNull);
      expect(await store.read('app.theme'), 'dark');
      expect(await bindings.load('input.overrides.game.p1'), {
        'b8': '<Keyboard>/k',
      });
    });

    test('cache entries sit under the cache\'s prefix', () async {
      final store = _fileStore();
      final cache = await _cache(store);
      await cache.setJson('best', {'time': 42});
      expect(await store.read('best'), isNull);
      expect(await store.read('${CacheManager.keyPrefix}best'), isNotNull);
      expect(await cache.getJson('best'), {'time': 42});
    });

    test('bindings saved before 2.0 are moved across once', () async {
      final store = _fileStore();
      await store.write(
        'input.overrides.game.p1',
        jsonEncode({'b8': '<Keyboard>/j'}),
      );
      final cache = await _cache(store);
      final bindings = CacheInputOverrideStore(cache);

      expect(await bindings.load('input.overrides.game.p1'), {
        'b8': '<Keyboard>/j',
      });
      // Out of the cache's way: the old key is gone, and clearAll spares
      // the moved copy.
      expect(await store.read('input.overrides.game.p1'), isNull);
      await cache.clearAll();
      expect(await bindings.load('input.overrides.game.p1'), {
        'b8': '<Keyboard>/j',
      });
    });

    test('clearing bindings also clears a copy from before 2.0', () async {
      final store = _fileStore();
      await store.write('input.overrides.game.p2', jsonEncode({'b8': 'x'}));
      final cache = await _cache(store);
      final bindings = CacheInputOverrideStore(cache);

      await bindings.clear('input.overrides.game.p2');
      expect(await bindings.load('input.overrides.game.p2'), isNull);
    });

    test('copies of bundle assets from before 2.0 are removed', () async {
      _bundleListing(const [
        'assets/scenes/level_01.scene.json',
        'assets/sprites/player.png',
      ]);
      final store = _fileStore();
      await store.write('assets/scenes/level_01.scene.json', '{"old": true}');
      await store.write('assets/notes.txt', 'not in the bundle: kept');
      await store.write('app.theme', 'dark');

      late JustDatabase db;
      final cache = await _cache(
        store,
        openDatabase: () async {
          db = await _memoryDatabase();
          await db.execute(
            'CREATE TABLE binary_cache (key TEXT PRIMARY KEY, data BLOB, '
            'timestamp INTEGER)',
          );
          for (final key in ['assets/sprites/player.png', 'saves/slot.bin']) {
            await db.execute(
              "INSERT INTO binary_cache (key, data, timestamp) VALUES "
              "('$key', '${base64Encode([1])}', 1)",
            );
          }
          return db;
        },
      );

      expect(await store.read('assets/scenes/level_01.scene.json'), isNull);
      expect(await store.read('assets/notes.txt'), 'not in the bundle: kept');
      expect(await store.read('app.theme'), 'dark');
      expect(await cache.getBinary('assets/sprites/player.png'), isNull);
      expect(await cache.getBinary('saves/slot.bin'), [1]);
    });
  });

  group('when a store fails', () {
    test('a database that will not open leaves strings persisting', () async {
      final store = _fileStore();
      final cache = await _cache(
        store,
        openDatabase: () async => throw StateError('no database here'),
      );

      expect(cache.isUsingMemoryFallback, isFalse);
      expect(cache.isBinaryInMemory, isTrue);
      await cache.setString('kept', 'yes');
      expect(await store.read('${CacheManager.keyPrefix}kept'), 'yes');
      await cache.setBinary('blob', Uint8List.fromList([7]));
      expect(await cache.getBinary('blob'), [7]);
    });

    test('a database without its table is given up on, and says so', () async {
      final lines = <String>[];
      final printer = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      addTearDown(() => debugPrint = printer);

      final cache = await _cache(
        _fileStore(),
        openDatabase: () async {
          final db = await _memoryDatabase();
          await db.close(); // every statement now fails
          return db;
        },
      );

      expect(cache.isBinaryInMemory, isTrue);
      expect(
        lines.any((l) => l.contains('binary data is kept in memory')),
        isTrue,
      );
      await cache.setBinary('blob', Uint8List.fromList([3]));
      expect(await cache.getBinary('blob'), [3]);
    });

    test('a failed write is read back, not the stale value under it', () async {
      final dir = Directory.systemTemp.createTempSync('fx_misc_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = _FlakyStore(dir);
      final cache = await _cache(store);

      await cache.setString('level', '1');
      store.failWrites = true;
      await cache.setString('level', '2');
      expect(await cache.getString('level'), '2');

      store.failWrites = false;
      await cache.setString('level', '3');
      expect(await cache.getString('level'), '3');
      expect(await store.read('${CacheManager.keyPrefix}level'), '3');
    });

    test('with no store at all, everything stays in memory', () async {
      final cache = CacheManager(forceMemoryFallback: true);
      await cache.initialize();
      addTearDown(cache.dispose);
      final bindings = CacheInputOverrideStore(cache);

      expect(cache.isUsingMemoryFallback, isTrue);
      await cache.setString('a', 'b');
      await bindings.save('input.overrides.game.p1', {'b8': 'k'});
      await cache.clearAll();
      expect(await cache.getString('a'), isNull);
      expect(await bindings.load('input.overrides.game.p1'), {'b8': 'k'});
    });
  });
}
