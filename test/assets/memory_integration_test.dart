import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('AssetManager scoped memory', () {
    test('releases scoped assets when the scope is disposed', () async {
      final manager = AssetManager()..initialize();
      manager.registerLoader(AssetType.text, _FakeAssetLoader());
      final scope = MemoryScope(debugLabel: 'scene');

      final asset = await manager.acquireScoped(
        'fake://scene.txt',
        AssetType.text,
        scope,
      );

      expect(asset.isLoaded, isTrue);
      expect(manager.refCount('fake://scene.txt'), 1);

      scope.dispose();

      expect(manager.refCount('fake://scene.txt'), 0);
      expect(manager.isLoaded('fake://scene.txt'), isFalse);
    });
  });

  group('ParticleEmitter pooling', () {
    test('returns expired particles to the shared pool', () {
      final emitter = ParticleEmitter(
        maxParticles: 1,
        emissionRate: 100,
        particleLifetime: 0.05,
        lifetimeVariation: 0.0,
        sizeVariation: 0.0,
        speedVariation: 0.0,
        startSize: 1,
        endSize: 1,
        startColor: Colors.white,
        endColor: Colors.transparent,
      );

      emitter.update(0.02);
      expect(emitter.particleCount, 1);

      emitter.isEmitting = false;
      emitter.update(0.1);

      expect(emitter.particleCount, 0);
      expect(emitter.pooledParticleCount, 1);
    });
  });

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
  });
}

class _FakeAssetLoader implements AssetLoader {
  @override
  Asset createAsset(String path) => _FakeAsset(path);
}

class _FakeAsset extends Asset {
  _FakeAsset(String path) : super(path, AssetType.text);

  @override
  Future<void> load() async {
    markAsLoaded();
  }

  @override
  void unload() {
    markAsUnloaded();
  }

  @override
  int getMemoryUsage() => 128;
}
