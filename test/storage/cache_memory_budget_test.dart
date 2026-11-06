// CacheManager's in-memory binary fallback is held to a byte budget, not
// only an entry count: large blobs cannot pile up when the database is not
// there.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List blob(int bytes, int fill) =>
      Uint8List(bytes)..fillRange(0, bytes, fill);

  test('blobs past the byte budget push out the least recently used', () async {
    final cache = CacheManager(
      forceMemoryFallback: true,
      maxMemoryBinaryBytes: 1000,
    );
    await cache.initialize();
    addTearDown(cache.dispose);

    await cache.setBinary('a', blob(400, 1));
    await cache.setBinary('b', blob(400, 2));
    expect(await cache.getBinary('a'), isNotNull); // a is now the newest
    await cache.setBinary('c', blob(400, 3)); // 1200 bytes: b goes

    expect(await cache.getBinary('b'), isNull);
    expect((await cache.getBinary('a'))!.first, 1);
    expect((await cache.getBinary('c'))!.first, 3);
  });

  test('a blob larger than the whole budget is not kept', () async {
    final cache = CacheManager(
      forceMemoryFallback: true,
      maxMemoryBinaryBytes: 100,
    );
    await cache.initialize();
    addTearDown(cache.dispose);
    await cache.setBinary('huge', blob(500, 9));
    expect(await cache.getBinary('huge'), isNull);
  });

  test('with an entry limit, neither limit is passed', () async {
    final cache = CacheManager(
      forceMemoryFallback: true,
      maxBinaryEntries: 3,
      maxMemoryBinaryBytes: 300,
    );
    await cache.initialize();
    addTearDown(cache.dispose);
    for (var i = 0; i < 5; i++) {
      await cache.setBinary('small$i', blob(1, i));
    }
    var kept = 0;
    for (var i = 0; i < 5; i++) {
      if (await cache.getBinary('small$i') != null) kept++;
    }
    expect(kept, 3, reason: 'the entry limit');
  });

  test('by default the budget is 32 MB', () {
    expect(CacheManager().maxMemoryBinaryBytes, 32 << 20);
  });
}
