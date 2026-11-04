// CacheManager in memory, as on a platform without its database: old
// binary entries go when the budget is exceeded.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('CacheManager memory fallback', () {
    test(
      'evicts old binary entries when the in-memory budget is exceeded',
      () async {
        final cache = CacheManager(
          maxBinaryEntries: 2,
          forceMemoryFallback: true,
        );
        await cache.initialize();

        await cache.setBinary('cache/one', Uint8List.fromList([1]));
        await cache.setBinary('cache/two', Uint8List.fromList([2]));
        expect(await cache.getBinary('cache/one'), isNotNull);

        await cache.setBinary('cache/three', Uint8List.fromList([3]));

        expect(await cache.getBinary('cache/one'), isNotNull);
        expect(await cache.getBinary('cache/two'), isNull);
        expect(await cache.getBinary('cache/three'), isNotNull);
      },
    );

    test(
      'cache manager falls back to in-memory storage when plugins are unavailable',
      () async {
        final cache = CacheManager();

        await cache.initialize();
        await cache.setString('test_key', 'value');
        await cache.setBinary('test-binary', Uint8List.fromList([1, 2, 3]));

        expect(cache.isInitialized, true);
        expect(await cache.getString('test_key'), 'value');
        expect(
          await cache.getBinary('test-binary'),
          Uint8List.fromList([1, 2, 3]),
        );
      },
    );
  });
}
