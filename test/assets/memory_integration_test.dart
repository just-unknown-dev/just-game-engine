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
      expect(manager.refCount('fake://scene.txt', AssetType.text), 1);

      scope.dispose();

      expect(manager.refCount('fake://scene.txt', AssetType.text), 0);
      expect(manager.isLoaded('fake://scene.txt'), isFalse);
    });
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
  int get memoryUsage => 128;
}
