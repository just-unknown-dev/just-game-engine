// GraphicsModels prefers a cooked copy beside a model, and asks the bundle
// for one only when the bundle's manifest lists it (on the web a missing
// asset is a failed request the browser console reports). A reload tells
// its listeners once the new model is there — once — and what a level no
// longer uses is let go. An engine's context knows its models while its
// Graphics3D runs.
@Tags(['graphics3d'])
library;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show CookedModel, DefaultTextures, NullGpuDevice, rendererNullShaders;

import 'fixtures.dart';

/// A bundle of [files] that records the keys it is asked for.
final class _LoggingBundle extends CachingAssetBundle {
  _LoggingBundle(this.files);

  final Map<String, Uint8List> files;
  final List<String> asked = [];

  @override
  Future<ByteData> load(String key) async {
    asked.add(key);
    final bytes = files[key];
    if (bytes == null) throw FlutterError('No asset $key');
    return ByteData.sublistView(bytes);
  }
}

/// The AssetManifest.bin a build writes for [keys].
Uint8List _manifest(Iterable<String> keys) {
  final message = const StandardMessageCodec().encodeMessage(<String, Object>{
    for (final key in keys)
      key: <Object>[
        <String, Object>{'asset': key},
      ],
  })!;
  return Uint8List.sublistView(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GraphicsModels models;
  late Uint8List cooked;
  final cookedPath = ModelImportSettings.cookedOf(cubePath);

  setUpAll(() async {
    // The cooked copy is a different model (skinned), so the test can tell
    // which one was loaded.
    cooked = CookedModel.write(
      await loadModelData(mannequinGlb(), name: 'mannequin'),
    );
  });

  GraphicsModels modelsOn(AssetBundle bundle) {
    final device = NullGpuDevice(shaders: rendererNullShaders);
    return GraphicsModels(
      bundle,
      ModelUploader(device, DefaultTextures(device)),
    );
  }

  test('a cooked copy the manifest lists wins', () async {
    final bundle = _LoggingBundle({
      'AssetManifest.bin': _manifest([cubePath, cookedPath]),
      cubePath: cubeGlb(),
      cookedPath: cooked,
    });
    models = modelsOn(bundle);
    final model = await models.load(cubePath);
    expect(model.data.skins, isNotEmpty);
    expect(bundle.asked, isNot(contains(cubePath)));
  });

  test('a cooked copy the manifest lacks is never asked for', () async {
    final bundle = _LoggingBundle({
      'AssetManifest.bin': _manifest([cubePath]),
      cubePath: cubeGlb(),
    });
    models = modelsOn(bundle);
    final model = await models.load(cubePath);
    expect(model.data.skins, isEmpty);
    expect(bundle.asked, isNot(contains(cookedPath)));
    expect(bundle.asked, contains(cubePath));
  });

  test('without a manifest the cooked copy is still tried', () async {
    final bundle = _LoggingBundle({cubePath: cubeGlb(), cookedPath: cooked});
    models = modelsOn(bundle);
    final model = await models.load(cubePath);
    expect(model.data.skins, isNotEmpty);
  });

  test(
    'readOverride supplies a cooked copy the bundle does not have',
    () async {
      final bundle = _LoggingBundle({
        'AssetManifest.bin': _manifest([cubePath]),
        cubePath: cubeGlb(),
      });
      models = modelsOn(bundle)
        ..readOverride = (path) async => path == cookedPath ? cooked : null;
      final model = await models.load(cubePath);
      expect(model.data.skins, isNotEmpty);
      expect(bundle.asked, isNot(contains(cookedPath)));
    },
  );
  group('reloading', () {
    test(
      'tells its reload listeners once, when the new model is there',
      () async {
        models = modelsOn(_LoggingBundle({cubePath: cubeGlb()}));
        final told = <String>[], reloaded = <String>[];
        models
          ..listeners.add(told.add)
          ..reloadListeners.add(reloaded.add);
        final old = await models.load(cubePath);
        expect(told, [cubePath]);
        models.reload(cubePath);
        expect(
          models.get(cubePath),
          isNull,
          reason: 'until the new one is there',
        );
        expect(told, hasLength(2), reason: 'told the old one went');
        expect(reloaded, isEmpty);
        final fresh = await models.load(cubePath);
        expect(fresh, isNot(same(old)));
        expect(told, hasLength(3));
        expect(reloaded, [cubePath]);
      },
    );

    test('two in a row tell once, for the last', () async {
      models = modelsOn(_LoggingBundle({cubePath: cubeGlb()}));
      final reloaded = <String>[];
      models.reloadListeners.add(reloaded.add);
      await models.load(cubePath);
      models
        ..reload(cubePath)
        ..reload(cubePath);
      await models.load(cubePath);
      await pumpEventQueue();
      expect(reloaded, [cubePath]);
    });

    test('a model never asked for is not read', () async {
      final bundle = _LoggingBundle({cubePath: cubeGlb()});
      models = modelsOn(bundle)..reload(cubePath);
      await pumpEventQueue();
      expect(bundle.asked, isEmpty);
    });

    test("the engine's model asset is read again once a reload", () async {
      final service = Graphics3D(
        device: NullGpuDevice(shaders: rendererNullShaders),
      );
      final engine = Engine(
        config: EngineConfig(services: [service]),
        context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      await engine.assets.load(cubePath, AssetType.model);
      final reloaded = <String>[];
      engine.assets.reloadListeners.add(reloaded.add);
      service.models.reload(cubePath);
      await service.models.load(cubePath);
      await pumpEventQueue();
      expect(reloaded, [
        cubePath,
      ], reason: '3-D physics rebuilds its colliders once');
    });
  });

  group('letting go', () {
    test(
      'retainOnly lets go of what is not kept, telling the listeners',
      () async {
        models = modelsOn(
          _LoggingBundle({cubePath: cubeGlb(), 'b.glb': cubeGlb()}),
        );
        await models.load(cubePath);
        await models.load('b.glb');
        final told = <String>[];
        models.listeners.add(told.add);
        expect(models.retainOnly([cubePath]), 1);
        expect(models.paths, [cubePath]);
        expect(told, ['b.glb']);
        models.clear();
        expect(models.paths, isEmpty);
      },
    );

    test('a model still loading is kept', () async {
      models = modelsOn(_LoggingBundle({cubePath: cubeGlb()}));
      final loading = models.load(cubePath);
      expect(models.retainOnly(const []), 0);
      await loading;
      expect(models.get(cubePath), isNotNull);
    });
  });

  test(
    "an engine's context knows its models while its Graphics3D runs",
    () async {
      final service = Graphics3D(
        device: NullGpuDevice(shaders: rendererNullShaders),
      );
      final engine = Engine(
        config: EngineConfig(services: [service]),
        context: EngineContext(bundle: TestBundle({cubePath: cubeGlb()})),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      final models = service.models;
      expect(engine.context.graphicsModels, same(models));
      await models.load(cubePath);
      await engine.services.remove(service);
      expect(engine.context.graphicsModels, isNull);
      expect(
        models.paths,
        isEmpty,
        reason: 'its GPU models let go as it stops',
      );
    },
  );
}
