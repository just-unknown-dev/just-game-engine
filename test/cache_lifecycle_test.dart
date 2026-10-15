// CacheManager's binary limit and its start-up: the oldest binary entries
// go once there are more than maxBinaryEntries, two initialize() calls open
// the stores once, and a dispose() during initialize() closes what it
// opened.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_database/just_database.dart' show JustDatabase;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_storage/just_storage.dart';

var _databases = 0;

Future<JustDatabase> _memoryDatabase() =>
    JustDatabase.open('cache_lifecycle_${_databases++}', persist: false);

Directory _folder() {
  final dir = Directory.systemTemp.createTempSync('cache_lifecycle_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the oldest binary entries go past maxBinaryEntries', () async {
    final dir = _folder();
    final cache = CacheManager(
      maxBinaryEntries: 2,
      openStorage: () async => FileStorage(dir),
      openDatabase: _memoryDatabase,
      openSharedStorage: null,
    );
    await cache.initialize();
    addTearDown(cache.dispose);
    expect(cache.isBinaryInMemory, isFalse);

    for (var i = 0; i < 20; i++) {
      final key = 'k${i.toString().padLeft(2, '0')}';
      await cache.setBinary(key, Uint8List.fromList([i]));
    }
    expect(await cache.getBinaryCacheSize(), 2);
    // Written last (and, for equal timestamps, last by key): kept.
    expect(await cache.getBinary('k19'), [19]);
    expect(await cache.getBinary('k00'), isNull);
  });

  test('two initialize calls open the stores once', () async {
    final dir = _folder();
    var opened = 0;
    final cache = CacheManager(
      openStorage: () async => FileStorage(dir),
      openDatabase: () {
        opened++;
        return _memoryDatabase();
      },
      openSharedStorage: null,
    );
    addTearDown(cache.dispose);
    await Future.wait([cache.initialize(), cache.initialize()]);
    expect(cache.isInitialized, isTrue);
    expect(opened, 1);
  });

  test('dispose during initialize closes what it opened', () async {
    final dir = _folder();
    final storage = Completer<JustStandardStorage>();
    JustDatabase? database;
    final cache = CacheManager(
      openStorage: () => storage.future,
      openDatabase: () async => database = await _memoryDatabase(),
      openSharedStorage: null,
    );
    final starting = cache.initialize();
    cache.dispose();
    storage.complete(FileStorage(dir));
    await starting;

    expect(cache.isInitialized, isFalse);
    // Disposed before the key-value store opened: the database never was.
    expect(database, isNull);

    // And once the store is open, a dispose still gives the database back.
    final later = CacheManager(
      openStorage: () async => FileStorage(dir),
      openDatabase: () async {
        database = await _memoryDatabase();
        return database!;
      },
      openSharedStorage: null,
    );
    final again = later.initialize();
    await Future<void>.delayed(Duration.zero);
    later.dispose();
    await again;
    expect(later.isInitialized, isFalse);
    if (database != null) expect(database!.isOpen, isFalse);
  });
}
