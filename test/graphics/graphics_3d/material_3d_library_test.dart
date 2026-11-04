// Material3DLibrary on its own, reading through a fake reader: a variant
// whose parent was missing is made once the parent is there; maps arrive
// and are read again without the material losing them meanwhile; previews,
// complete(); materials made for an entity's own values let go once no
// user holds them, the least recently asked for first past the limit; and
// what a level no longer uses let go by retainOnly.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show DefaultTextures, NullGpuDevice, rendererNullShaders;

const _variant = 'assets/materials/variant.material.json';
const _base = 'assets/materials/base.material.json';
const _red = 'assets/materials/red.material.json';
const _blue = 'assets/materials/blue.material.json';
const _map = 'assets/textures/a.png';
const _normal = 'assets/textures/n.png';

Uint8List _json(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _file(Material3DFile file) => _json(file.encode());

Future<Uint8List> _png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = color);
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Uint8List> files;
  late List<String> reads;
  late DefaultTextures defaults;
  late Material3DLibrary library;

  setUp(() async {
    files = {
      _red: _file(const Material3DFile(color: 0xFFFF0000, roughness: 0.2)),
      _blue: _file(const Material3DFile(color: 0xFF0000FF)),
      _map: await _png(const ui.Color(0xFF00FF00)),
      _normal: await _png(const ui.Color(0xFF8080FF)),
    };
    reads = [];
    final device = NullGpuDevice(shaders: rendererNullShaders);
    defaults = DefaultTextures(device);
    library = Material3DLibrary(ModelUploader(device, defaults), (path) async {
      reads.add(path);
      final bytes = files[path];
      if (bytes == null) throw StateError('No file $path');
      return bytes;
    });
  });

  /// Lets reads land until [done], or gives up.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  /// The colour map [material] draws with.
  GpuTexture colorMap(GpuMaterial material) => material.textures.first.$1;

  test(
    'a variant whose parent was missing is made once the parent is there',
    () async {
      files[_variant] = _json('{"parent": "$_base", "metallic": 1}');
      expect(library.fileOf(_variant), isNull);
      await until(() => library.problemsOf(_variant).isNotEmpty);
      expect(library.fileOf(_variant)!.color, isNot(0xFFFF0000));

      files[_base] = _file(const Material3DFile(color: 0xFFFF0000));
      library.reload(_base);
      await until(() => library.problemsOf(_variant).isEmpty);
      final file = library.fileOf(_variant)!;
      expect(
        (file.color, file.metallic),
        (0xFFFF0000, 1.0),
        reason: 'its parent laid under it',
      );
    },
  );

  test(
    'a missing file, asked for every frame, is read once and made once it is there',
    () async {
      const gone = 'assets/materials/gone.material.json';
      for (var frame = 0; frame < 5; frame++) {
        expect(library.gpuOf(gone), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(library.errorOf(gone), isNotNull);
      expect(reads.where((p) => p == gone), hasLength(1));
      files[gone] = _file(const Material3DFile(roughness: 0.4));
      library.reload(gone);
      await until(() => library.gpuOf(gone) != null);
      expect(library.fileOf(gone)!.roughness, 0.4);
    },
  );

  test('previewing the missing parent makes the variant again too', () async {
    files[_variant] = _json('{"parent": "$_base", "metallic": 1}');
    library.fileOf(_variant);
    await until(() => library.problemsOf(_variant).isNotEmpty);
    library.preview(_base, const Material3DFile(roughness: 0.3));
    expect(library.problemsOf(_variant), isEmpty);
    expect(library.fileOf(_variant)!.roughness, 0.3);
  });

  test(
    'a map arrives, and is read again without the material losing it meanwhile',
    () async {
      files[_red] = _file(const Material3DFile(colorMap: _map));
      await until(() => library.gpuOf(_red) != null);
      final before = library.revision;
      expect(
        colorMap(library.gpuOf(_red)!),
        same(defaults.whiteSrgb),
        reason: 'its map is still being read',
      );
      await until(
        () => !identical(colorMap(library.gpuOf(_red)!), defaults.whiteSrgb),
      );
      expect(
        library.revision,
        greaterThan(before),
        reason: 'what draws with it asks again',
      );
      final first = colorMap(library.gpuOf(_red)!);

      library.reload(_map);
      expect(
        colorMap(library.gpuOf(_red)!),
        same(first),
        reason: 'what it was, until the new one is there',
      );
      await until(() => !identical(colorMap(library.gpuOf(_red)!), first));
      expect(reads.where((p) => p == _map), hasLength(2));
    },
  );

  test('clear lets go of everything, previews too', () async {
    library.preview(_red, const Material3DFile(roughness: 0.9));
    expect(library.isPreviewing(_red), isTrue);
    library.clear();
    expect(library.isPreviewing(_red), isFalse);
    expect(library.fileOf(_red), isNull, reason: 'read again');
    await until(() => library.fileOf(_red) != null);
    expect(library.fileOf(_red)!.roughness, 0.2);
  });

  test('complete waits for every map', () async {
    final material = await library.complete(
      const Material3DFile(colorMap: _map, normalMap: _normal),
    );
    expect(reads, containsAll([_map, _normal]));
    expect(colorMap(material), isNot(same(defaults.whiteSrgb)));
    expect(material.textures[2].$1, isNot(same(defaults.flatNormal)));
  });

  group('materials made for an entity\'s own values', () {
    setUp(() async => until(() => library.gpuOf(_red) != null));

    test('are shared, and let go once no user holds them', () {
      final made = library.gpuOf(_red, overrides: {'metallic': 0.5})!;
      expect(library.gpuOf(_red, overrides: {'metallic': 0.5}), same(made));
      expect(made.data.metallic, 0.5);
      library
        ..hold(made)
        ..hold(made)
        ..release(made);
      expect(
        library.gpuOf(_red, overrides: {'metallic': 0.5}),
        same(made),
        reason: 'one user still holds it',
      );
      library.release(made);
      expect(
        library.gpuOf(_red, overrides: {'metallic': 0.5}),
        isNot(same(made)),
        reason: 'made again',
      );
    });

    test(
      'past the limit, the least recently asked for goes, never one held',
      () {
        final held = library.gpuOf(_red, overrides: {'metallic': 0.1})!;
        library.hold(held);
        final kept = library.gpuOf(_red, overrides: {'metallic': 0.15})!;
        for (var i = 0; i < Material3DLibrary.maxOverridden + 40; i++) {
          library.gpuOf(_red, overrides: {'metallic': 0.2 + i / 1000});
          // Asked for every frame, so never the least recent.
          library.gpuOf(_red, overrides: {'metallic': 0.15});
        }
        expect(library.gpuOf(_red, overrides: {'metallic': 0.1}), same(held));
        expect(library.gpuOf(_red, overrides: {'metallic': 0.15}), same(kept));
        expect(
          library.gpuOf(_red, overrides: {'metallic': 0.2}),
          isNot(same(held)),
        );
      },
    );
  });

  test(
    'retainOnly lets go of the files, and the maps, only others used',
    () async {
      files[_red] = _file(const Material3DFile(colorMap: _map));
      files[_blue] = _file(const Material3DFile(colorMap: _normal));
      await until(
        () => [_red, _blue].every((p) {
          final gpu = library.gpuOf(p);
          return gpu != null && !identical(colorMap(gpu), defaults.whiteSrgb);
        }),
      );
      reads.clear();
      expect(library.retainOnly([_red]), 1);
      // The kept one draws as it did, nothing read again.
      final red = library.gpuOf(_red)!;
      expect(colorMap(red), isNot(same(defaults.whiteSrgb)));
      expect(reads, isEmpty);
      // The other is read again, its map too.
      expect(library.gpuOf(_blue), isNull);
      await until(() {
        final blue = library.gpuOf(_blue);
        return blue != null && !identical(colorMap(blue), defaults.whiteSrgb);
      });
      expect(reads, [_blue, _normal]);
    },
  );
}
