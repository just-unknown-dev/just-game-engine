// GraphicsModels prefers a cooked copy beside a model, and asks the bundle
// for one only when the bundle's manifest lists it (on the web a missing
// asset is a failed request the browser console reports).
@Tags(['graphics3d'])
library;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

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
}
