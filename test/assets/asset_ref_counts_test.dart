// AssetManager's counts: an acquire whose load a release cancelled does not
// take another owner's count; counts are kept per path and type; what a
// plain load asked for survives the last release; retainOnly lets go of
// what nothing holds; the memory total is kept as assets come and go.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A binary asset whose load waits for [gate]; [size] bytes "in memory".
class _GatedAsset extends BinaryAsset {
  _GatedAsset(super.path, this.gate, this.size);

  final Completer<void> gate;
  final int size;
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
  int get memoryUsage => size;
}

/// Makes a new gated asset for every load; [open] lets them all load at
/// once.
class _GatedLoader implements AssetLoader {
  final made = <_GatedAsset>[];
  bool open = false;
  int size = 10;

  @override
  Asset createAsset(String path) {
    final gate = Completer<void>();
    if (open) gate.complete();
    final asset = _GatedAsset(path, gate, size);
    made.add(asset);
    return asset;
  }
}

/// Serves [files] as strings, counting the reads.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('no asset $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetManager assets;
  late _GatedLoader loader;
  setUp(() {
    assets = AssetManager();
    loader = _GatedLoader();
    assets
      ..registerLoader(AssetType.binary, loader)
      ..registerLoader(AssetType.json, loader);
  });

  test(
    "an acquire cancelled by a release does not take another owner's count",
    () async {
      // Scene A asks, and lets go while it still loads…
      final first = assets.acquire('x.bin', AssetType.binary);
      assets.release('x.bin', AssetType.binary);
      // …and scene B asks for the same file.
      final second = assets.acquire('x.bin', AssetType.binary);
      expect(assets.refCount('x.bin', AssetType.binary), 1);
      loader.made[0].gate.complete();
      await expectLater(first, throwsA(isA<AssetLoadException>()));
      expect(assets.refCount('x.bin', AssetType.binary), 1, reason: "B's");
      loader.made[1].gate.complete();
      await second;
      expect(assets.refCount('x.bin', AssetType.binary), 1);
      expect(assets.isLoaded('x.bin'), isTrue);
      assets.release('x.bin', AssetType.binary);
      expect(assets.isLoaded('x.bin'), isFalse);
    },
  );

  test('an acquire whose load fails gives back its own count', () async {
    final failing = assets.acquire('y.bin', AssetType.text); // no loader
    await expectLater(failing, throwsA(isA<AssetLoadException>()));
    expect(assets.refCount('y.bin', AssetType.text), 0);
  });

  test('counts are per path and type', () async {
    loader.open = true;
    await assets.acquire('c.json', AssetType.binary);
    await assets.acquire('c.json', AssetType.json);
    expect(assets.refCount('c.json', AssetType.binary), 1);
    expect(assets.refCount('c.json', AssetType.json), 1);
    assets.release('c.json', AssetType.binary);
    expect(assets.get<BinaryAsset>('c.json'), isNotNull);
    expect(assets.assetCount, 1, reason: 'only the binary one went');
    expect(loader.made[0].unloaded, isTrue);
    expect(loader.made[1].unloaded, isFalse);
  });

  group('a plain load', () {
    test('is not unloaded by the last release of an acquire', () async {
      loader.open = true;
      // A level holds the sheet in its scope; a sprite shows it with a
      // plain load.
      await assets.acquire('sheet.bin', AssetType.binary);
      await assets.load<BinaryAsset>('sheet.bin', AssetType.binary);
      assets.release('sheet.bin', AssetType.binary);
      expect(assets.isLoaded('sheet.bin'), isTrue);
      expect(loader.made.single.unloaded, isFalse);
    });

    test('still loading, is not cancelled by a release', () async {
      final acquired = assets.acquire('s.bin', AssetType.binary);
      final loaded = assets.load<BinaryAsset>('s.bin', AssetType.binary);
      assets.release('s.bin', AssetType.binary);
      loader.made.single.gate.complete();
      await acquired;
      expect((await loaded).isLoaded, isTrue);
      expect(assets.isLoaded('s.bin'), isTrue);
    });

    test('that fails leaves nothing behind', () async {
      final load = assets.load<TextAsset>('t.txt', AssetType.text);
      await expectLater(load, throwsA(isA<AssetLoadException>()));
      // Nothing pinned: an acquire and release now unloads.
      loader.open = true;
      assets.registerLoader(AssetType.text, loader);
      await assets.acquire('t.txt', AssetType.text);
      assets.release('t.txt', AssetType.text);
      expect(assets.isLoaded('t.txt'), isFalse);
    });

    test('is unloaded by unload, which can name one type', () async {
      loader.open = true;
      await assets.load<BinaryAsset>('u.json', AssetType.binary);
      await assets.load<BinaryAsset>('u.json', AssetType.json);
      assets.unload('u.json', AssetType.json);
      expect(assets.assetCount, 1);
      assets.unload('u.json');
      expect(assets.assetCount, 0);
    });
  });

  test('retainOnly keeps what is named or held, and drops the rest', () async {
    loader.open = true;
    await assets.load<BinaryAsset>('keep.bin', AssetType.binary);
    await assets.load<BinaryAsset>('drop.bin', AssetType.binary);
    await assets.acquire('held.bin', AssetType.binary);
    final arriving = assets.load<BinaryAsset>('late.bin', AssetType.binary);

    assets.retainOnly(['keep.bin']);
    expect(assets.isLoaded('keep.bin'), isTrue);
    expect(assets.isLoaded('held.bin'), isTrue);
    expect(assets.isLoaded('drop.bin'), isFalse);
    expect(loader.made[1].unloaded, isTrue);
    // Still loading: let go when it arrives.
    await expectLater(arriving, throwsA(isA<AssetLoadException>()));
    expect(assets.isLoaded('late.bin'), isFalse);

    assets.release('held.bin', AssetType.binary);
    expect(assets.isLoaded('held.bin'), isFalse);
  });

  group('memory', () {
    test('the total follows each load and unload', () async {
      loader
        ..open = true
        ..size = 100;
      await assets.load<BinaryAsset>('a.bin', AssetType.binary);
      loader.size = 30;
      await assets.load<BinaryAsset>('b.bin', AssetType.binary);
      expect(assets.totalMemoryUsage, 130);
      assets.unload('a.bin');
      expect(assets.totalMemoryUsage, 30);
      assets.unloadAll();
      expect(assets.totalMemoryUsage, 0);
    });

    test('a JSON asset is measured once, from its text', () async {
      const text = '{"a": [1, 2, 3], "b": "hello"}';
      final manager = AssetManager(bundle: _Bundle({'d.json': text}));
      final json = await manager.loadJson('d.json');
      expect(json.memoryUsage, text.length);
      expect(manager.totalMemoryUsage, text.length);
      manager.unload('d.json');
      expect(json.memoryUsage, 0);
      expect(manager.totalMemoryUsage, 0);
    });
  });
}
