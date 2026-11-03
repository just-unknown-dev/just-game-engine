# Assets & storage

_Audio & content_ · Load images, JSON, text and sounds through engine.assets, group and reference-count them, and keep data between runs with engine.cache.

`engine.assets` is the engine's `AssetManager`: it loads, caches and releases images, sounds, text, JSON and binary files. `engine.cache` is its `CacheManager`, which keeps strings, JSON and binary data between runs.

## The asset manager

Each engine has its own `AssetManager`, reading from the Flutter asset bundle. It is ready as soon as the engine is made, before `initialize()`. Every file it loads must be listed under `flutter: assets:` in `pubspec.yaml`, by itself or through its folder; a folder entry does not include its subfolders.

```dart lib/level_data.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

Future<void> loadLevelData(Engine engine) async {
  final waves = await engine.assets.loadJson('assets/data/waves.json');
  final sky = await engine.assets.loadImage('assets/images/sky.png');
  debugPrint('${(waves.data as List).length} waves; sky ${sky.width}x${sky.height}');

  // Later, anywhere: the same asset, already loaded.
  final again = engine.assets.getImage('assets/images/sky.png');
  debugPrint('still loaded: ${again?.isLoaded}');
}
```

- `loadImage`, `loadAudio`, `loadText`, `loadJson` and `loadBinary` load one file each; `load(path, type)` takes an `AssetType`, and `loadMultiple(paths, type)` loads several in parallel.
- Loading a path that is already loaded returns the cached asset. `getImage`, `getJson` and `get<T>(path)` return what is loaded, or null.
- `ImageAsset` has `image` (a `dart:ui` image), `width` and `height`; `JsonAsset` has the decoded `data`; `TextAsset` has `content`.
- `unload(path)` unloads every type loaded at that path, and `unloadAll()` everything.
- `totalMemoryUsage`, `assetCount` and `getCacheStats()` say what is loaded.

Image, audio, text, JSON and binary loaders are built in. The atlas loader is registered the first time `SpriteAtlas.fromAsset` runs. Fonts, shaders and models have no loader until you add one with `registerLoader(type, loader)`; loading one before that throws an `AssetLoadException`. Engine loaders that need the asset manager take it as a parameter, for example `Sprite.fromAsset(path, assets: engine.assets)`; see [Sprites](/docs/sprites).

## Groups and reference counting

A `GameAssetBundle` is a named group of assets that load and unload together. It was called `AssetBundle` in 1.x, which clashed with Flutter's class of that name.

When several screens or levels share assets, count references instead. `acquire(path, type)` loads or reuses an asset and adds one to its count; `release(path)` takes one away and unloads the asset when the count reaches zero. An `AssetScope` releases everything it acquired in one `dispose()` call, which suits one scope per level or screen.

```dart lib/level_assets.dart
final menuAssets = GameAssetBundle(
  name: 'menu',
  assetPaths: ['assets/images/title.png', 'assets/audio/menu.ogg'],
  assetTypes: [AssetType.image, AssetType.audio],
);

Future<void> showMenu(Engine engine) => menuAssets.load(engine.assets);
void leaveMenu(Engine engine) => menuAssets.unload(engine.assets);

/// One scope per level: leaving the level releases what it used.
Future<AssetScope> enterLevel(Engine engine) async {
  final scope = AssetScope(engine.assets);
  await scope.acquireImage('assets/images/cave_background.png');
  await scope.acquireJson('assets/data/cave_waves.json');
  return scope; // call scope.dispose() when the level ends
}
```

`engine.assets.createScope()` makes a `MemoryScope` from `just_memory` instead. Pass it to `acquireImageScoped(path, scope)` and the other `...Scoped` methods, and register any clean-up of your own with `scope.own(callback)`. Disposing the scope runs everything it owns, newest first.

## Tests and other bundles

The asset manager reads from the engine context's bundle, Flutter's `rootBundle` unless you say otherwise. To load from a bundle of your own, for example in a test, make the engine with `Engine(context: EngineContext(bundle: myBundle))`. A context you pass in is yours to dispose. See [Testing](/docs/testing).

## The cache

`engine.cache` stores small amounts of data between runs: settings, progress, downloaded content.

```dart lib/settings.dart
Future<void> saveVolume(Engine engine, double volume) =>
    engine.cache.setJson('settings', {'musicVolume': volume});

Future<double> loadVolume(Engine engine) async {
  final json = await engine.cache.getJson('settings');
  if (json is Map && json['musicVolume'] is num) {
    return (json['musicVolume'] as num).toDouble();
  }
  return 1.0;
}
```

- `setString` and `getString`, `setJson` and `getJson`, and `setBinary` and `getBinary` (a `Uint8List`) store and read values. Any string is a valid key.
- `remove(key)` deletes one entry. `clearAll()` deletes the cache's own entries only: the rest of the store, including players' key bindings, is left alone.
- Strings and JSON go to the engine's key-value store under the `just_game_engine.cache/` prefix; binary data goes to a database of its own.
- Where the key-value store cannot be opened (a test, a headless run), everything stays in memory for the run (`isUsingMemoryFallback`). If only the database fails, binary data stays in memory (`isBinaryInMemory`).

## The engine's storage file

The engine keeps its data apart from your app's. On desktop and mobile its key-value store is `<application support>/just_game_engine/just_storage.json`, beside the `just_storage.json` your app opens with `JustStorage.standard()`, not inside it: two writers on one file could drop each other's keys. On the web it is browser storage under the engine's own `just_game_engine/` key prefix.

On the first launch of 2.0, the engine moves the keys it left in the shared file in 1.x into its own store, and removes the copies of bundle assets that 1.x cached. Assets from the bundle are never copied into the cache, so an app update's new images show at once.

## Memory diagnostics

The engine re-exports the `just_memory` diagnostics it uses: `MemoryProfiler`, `PoolManager` and the snapshot types. `engine.cache.captureProfile()` returns a `MemoryProfileSnapshot`, and `engine.assets.getCacheStats()` reports loaded assets by type and their memory use. For the profiling tools and stats overlays, see [Debugging](/docs/debugging).
