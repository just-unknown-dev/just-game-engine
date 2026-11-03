// AssetManager when loads and releases cross: a load overtaken by unload,
// unloadAll or dispose is not kept; one path loaded as two types is two
// assets, not a TypeError; a release while the asset is still loading counts;
// an AssetScope disposed during an acquire gives its count back.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A binary asset whose load waits for [gate].
class _GatedAsset extends BinaryAsset {
  _GatedAsset(super.path, this.gate);

  final Completer<void> gate;
  bool unloaded = false;

  @override
  Future<void> load() async {
    await gate.future;
    markAsLoaded();
  }

  @override
  void unload() {
    unloaded = true;
    markAsUnloaded();
  }

  @override
  int getMemoryUsage() => 0;
}

class _GatedLoader implements AssetLoader {
  final gates = <String, Completer<void>>{};
  final made = <_GatedAsset>[];

  @override
  Asset createAsset(String path) {
    final asset = _GatedAsset(path, gates.putIfAbsent(path, Completer.new));
    made.add(asset);
    return asset;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetManager assets;
  late _GatedLoader loader;
  setUp(() {
    assets = AssetManager();
    loader = _GatedLoader();
    assets.registerLoader(AssetType.binary, loader);
  });

  test('a load overtaken by unload is not kept', () async {
    final load = assets.load<BinaryAsset>('a.bin', AssetType.binary);
    assets.unload('a.bin');
    loader.gates['a.bin']!.complete();
    await expectLater(load, throwsA(isA<AssetLoadException>()));
    expect(assets.isLoaded('a.bin'), isFalse);
    expect(assets.assetCount, 0);
    expect(loader.made.single.unloaded, isTrue);
  });

  test('a load overtaken by dispose is not kept', () async {
    final load = assets.load<BinaryAsset>('b.bin', AssetType.binary);
    assets.dispose();
    loader.gates['b.bin']!.complete();
    await expectLater(load, throwsA(isA<AssetLoadException>()));
    expect(assets.assetCount, 0);
  });

  test('one path loaded as two types is two assets', () async {
    assets.registerLoader(AssetType.json, loader);
    final binary = assets.load<BinaryAsset>('c.bin', AssetType.binary);
    final json = assets.load<BinaryAsset>('c.bin', AssetType.json);
    loader.gates['c.bin']!.complete();
    final a = await binary, b = await json;
    expect(identical(a, b), isFalse);
    expect(assets.assetCount, 2);
    assets.unload('c.bin');
    expect(assets.assetCount, 0);
  });

  test('a release while loading counts', () async {
    final acquire = assets.acquire('d.bin', AssetType.binary);
    expect(assets.refCount('d.bin'), 1);
    assets.release('d.bin');
    loader.gates['d.bin']!.complete();
    await expectLater(acquire, throwsA(isA<AssetLoadException>()));
    expect(assets.refCount('d.bin'), 0);
    expect(assets.assetCount, 0);
  });

  test('a scope disposed during an acquire gives the count back', () async {
    final scope = AssetScope(assets);
    final acquire = scope.acquire('e.bin', AssetType.binary);
    scope.dispose();
    loader.gates['e.bin']!.complete();
    await acquire;
    expect(assets.refCount('e.bin'), 0);
  });
}
