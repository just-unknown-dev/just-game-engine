// Material files (`*.material.json`): a shape drawn with one once it is
// read, made again when the file changes; laid out in metres; a broken one
// leaving the shape its own look; a model's materials swapped for one and
// back; a layered one's layers; and a model's choices saved with it.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'fixtures.dart';

const _red = 'assets/materials/red.material.json';
const _tiles = 'assets/materials/tiles.material.json';
const _broken = 'assets/materials/broken.material.json';
const _mossy = 'assets/materials/mossy_red.material.json';
const _orphan = 'assets/materials/orphan.material.json';

Uint8List _file(MaterialFile file) =>
    Uint8List.fromList(utf8.encode(file.encode()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  late TestBundle bundle;

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    bundle = TestBundle({
      _red: _file(const MaterialFile(color: 0xFFFF0000, roughness: 0.2)),
      _tiles: _file(
        const MaterialFile(uv: MaterialUv.metres, tilingX: 2, tilingY: 2),
      ),
      _broken: Uint8List.fromList(
        utf8.encode('{"formatVersion": 1, "kind": "glass"}'),
      ),
      _mossy: Uint8List.fromList(
        utf8.encode('{"parent": "$_red", "metallic": 1}'),
      ),
      _orphan: Uint8List.fromList(
        utf8.encode(
          '{"parent": "assets/materials/gone.material.json", "metallic": 1}',
        ),
      ),
      cubePath: cubeGlb(),
    });
    engine = Engine(
      config: EngineConfig(graphics3D: service),
      context: EngineContext(bundle: bundle),
    );
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  final view = frameView(eye: Vector3(0, -3, -8));

  Entity add(String name, List<Component> components) {
    final e = engine.world.createEntity(name: name)
      ..addComponent(TransformComponent());
    for (final c in components) {
      e.addComponent(c);
    }
    return e;
  }

  /// Draws frames until [done], or gives up.
  Future<void> until(bool Function() done) async {
    final renderer = service.sceneRenderer;
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      renderer.update(view);
    }
    expect(done(), isTrue);
  }

  test(
    'a shape is drawn with its material file once read, and again when it changes',
    () async {
      final renderer = service.sceneRenderer;
      add('crate', [Cube3D(material: _red)]);
      renderer.update(view);
      final instance = renderer.debugShapeInstances.single!;
      expect(
        instance.material.data.roughness,
        0.75,
        reason: 'its own look meanwhile',
      );
      await until(() => instance.material.data.roughness == 0.2);
      final (r, g, b, a) = instance.material.data.baseColor;
      expect([r, g, b, a], [1, 0, 0, 1], reason: 'red, made linear');

      bundle.files[_red] = _file(const MaterialFile(roughness: 0.9));
      renderer.materials.reload(_red);
      await until(() => instance.material.data.roughness == 0.9);
    },
  );

  test('laid out in metres: the mesh is made for its size', () async {
    final renderer = service.sceneRenderer;
    final cube = Cube3D(material: _tiles);
    add('floor', [cube]);
    renderer.update(view);
    await until(() => renderer.shapes.tilesInMetres(cube));
    final scale = (renderer
        .debugShapeInstances
        .single!
        .material
        .data
        .baseColorTexture!
        .scale);
    expect(scale, (2.0, 2.0), reason: 'repeats per metre');
  });

  test('a broken file leaves the shape its own look', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _broken, roughness: 0.5)]);
    renderer.update(view);
    await until(() => renderer.materials.errorOf(_broken) != null);
    expect(renderer.debugShapeInstances.single!.material.data.roughness, 0.5);
  });

  test('a model\'s materials are swapped for a file, and back', () async {
    final renderer = service.sceneRenderer;
    final model = ModelComponent(model: cubePath, materials: {'*': _red});
    add('box', [model]);
    renderer.update(view);
    await until(() {
      final instances = renderer.debugModelInstances;
      return instances.isNotEmpty &&
          instances.single.material.data.roughness == 0.2;
    });
    model.materials = {};
    renderer.update(view);
    expect(
      renderer.debugModelInstances.single.material.data.roughness,
      closeTo(0.6, 1e-6),
      reason: 'its own again',
    );
    model.materials = {'#0': _red};
    renderer.update(view);
    expect(
      renderer.debugModelInstances.single.material.data.roughness,
      0.2,
      reason: 'by index',
    );
  });

  test('a layered material: its layers tiled as each says', () {
    final data = MaterialLibrary.dataOf(
      const MaterialFile(kind: MaterialKind.layered, layers: [_tiles, _red]),
      layers: const [MaterialFile(tilingX: 4), MaterialFile(tilingX: 0.5)],
    );
    expect(data.layered, isTrue);
    expect(data.layerTiling, (4.0, 0.5, 1.0, 1.0));
    final world = MaterialLibrary.dataOf(
      const MaterialFile(
        uv: MaterialUv.world,
        alpha: MaterialAlpha.blend,
        opacity: 0.5,
      ),
    );
    expect(world.uvMode, UvMode.world);
    expect(world.alphaMode, AlphaMode.blend);
    expect(world.baseColor.$4, 0.5);
  });

  test('transparency as the file says; maps moved and turned', () {
    final solid = MaterialLibrary.dataOf(const MaterialFile(opacity: 0.5));
    expect(
      solid.alphaMode,
      AlphaMode.opaque,
      reason: 'opacity counts only when it blends',
    );
    expect(solid.baseColor.$4, 1);
    final cut = MaterialLibrary.dataOf(
      const MaterialFile(
        alpha: MaterialAlpha.cutout,
        alphaCutoff: 0.3,
        occlusionStrength: 0.4,
        tilingX: 2,
        offsetX: 0.5,
        offsetY: 0.25,
        rotation: 90,
      ),
    );
    expect(cut.alphaMode, AlphaMode.mask);
    expect(cut.alphaCutoff, 0.3);
    expect(cut.occlusionStrength, 0.4);
    final ref = cut.baseColorTexture!;
    expect(ref.scale, (2.0, 1.0));
    expect(ref.offset, (0.5, 0.25));
    expect(
      ref.rotation,
      closeTo(1.5708, 1e-4),
      reason: 'degrees in the file, radians drawn',
    );
  });

  test('a variant is drawn over its parent, and follows it', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _mossy)]);
    renderer.update(view);
    final instance = renderer.debugShapeInstances.single!;
    await until(() => instance.material.data.metallic == 1);
    expect(instance.material.data.roughness, 0.2, reason: "the parent's");
    expect(renderer.materials.sourceOf(_mossy)!.isVariant, isTrue);
    expect(renderer.materials.fileOf(_mossy)!.isVariant, isFalse);

    bundle.files[_red] = _file(const MaterialFile(roughness: 0.9));
    renderer.materials.reload(_red);
    await until(() => instance.material.data.roughness == 0.9);
    expect(instance.material.data.metallic, 1, reason: 'its own still');
  });

  test('a parent that is missing: drawn over the defaults, and said', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _orphan)]);
    renderer.update(view);
    await until(() => renderer.materials.problemsOf(_orphan).isNotEmpty);
    expect(
      renderer.materials.problemsOf(_orphan).single,
      contains('gone.material.json'),
    );
    await until(
      () => renderer.debugShapeInstances.single!.material.data.metallic == 1,
    );
  });

  test('an unsaved edit is drawn until it ends, its variants too', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _red)]);
    add('mossy', [Cube3D(material: _mossy)]);
    renderer.update(view);
    final crate = renderer.debugShapeInstances[0]!;
    final mossy = renderer.debugShapeInstances[1]!;
    await until(
      () =>
          crate.material.data.roughness == 0.2 &&
          mossy.material.data.metallic == 1,
    );

    renderer.materials.preview(_red, const MaterialFile(roughness: 0.5));
    expect(renderer.materials.isPreviewing(_red), isTrue);
    renderer.update(view);
    expect(crate.material.data.roughness, 0.5);
    expect(
      mossy.material.data.roughness,
      0.5,
      reason: 'a variant of it follows',
    );
    expect(mossy.material.data.metallic, 1);

    renderer.materials.endPreview(_red);
    renderer.update(view);
    expect(crate.material.data.roughness, 0.2, reason: 'as saved again');
  });

  test('saved again, the old look stays until the new file arrives', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _red)]);
    renderer.update(view);
    final instance = renderer.debugShapeInstances.single!;
    await until(() => instance.material.data.roughness == 0.2);
    bundle.files[_red] = _file(const MaterialFile(roughness: 0.9));
    renderer.materials.reload(_red);
    renderer.update(view);
    expect(
      instance.material.data.roughness,
      0.2,
      reason: 'not its own look meanwhile',
    );
    await until(() => instance.material.data.roughness == 0.9);
  });

  test(
    "an entity's own values over its material file, shape and model",
    () async {
      final renderer = service.sceneRenderer;
      final shapeOverrides = MaterialOverrides3D(
        values: {'roughness': 0.4, 'emissionStrength': 3},
      );
      add('crate', [Cube3D(material: _red), shapeOverrides]);
      final model = ModelComponent(model: cubePath, materials: {'*': _red});
      final modelOverrides = MaterialOverrides3D(values: {'metallic': 0.7});
      add('box', [model, modelOverrides]);
      renderer.update(view);
      final crate = renderer.debugShapeInstances.single!;
      await until(() {
        final models = renderer.debugModelInstances;
        return crate.material.data.roughness == 0.4 &&
            models.isNotEmpty &&
            models.single.material.data.metallic == 0.7;
      });
      expect(crate.material.data.emissiveStrength, 3);
      final shared = renderer.materials.gpuOf(_red)!;
      expect(
        shared.data.roughness,
        0.2,
        reason: 'the file itself is untouched',
      );

      shapeOverrides.set('roughness', 0.6);
      modelOverrides.remove('metallic');
      renderer.update(view);
      expect(crate.material.data.roughness, 0.6);
      expect(
        renderer.debugModelInstances.single.material.data.metallic,
        0,
        reason: "the file's own",
      );
      expect(
        identical(
          renderer.materials.gpuOf(_red, overrides: shapeOverrides.values),
          crate.material,
        ),
        isTrue,
        reason: 'the same values, the same material',
      );
    },
  );

  test(
    'the Timeline keys an override, one number of a pair at a time',
    () async {
      final renderer = service.sceneRenderer;
      final e = add('crate', [Cube3D(material: _red), MaterialOverrides3D()]);
      final field = engine.context.definitions
          .definitionByType('MaterialOverrides3D')!
          .fields
          .firstWhere((f) => f.name == 'values');
      expect(
        PropertyAccess.channelsOf(field),
        containsAll(['roughness', 'tiling#0', 'offset#1']),
      );
      PropertyAccess.of(
        e,
        'MaterialOverrides3D',
        'values',
        'roughness',
      )!.write(0.3);
      PropertyAccess.of(
        e,
        'MaterialOverrides3D',
        'values',
        'tiling#0',
      )!.write(3);
      renderer.update(view);
      final instance = renderer.debugShapeInstances.single!;
      await until(() => instance.material.data.roughness == 0.3);
      expect(instance.material.data.baseColorTexture!.scale, (3.0, 1.0));
    },
  );

  test('overrides are saved with the entity', () {
    final definitions = engine.context.definitions;
    final o = MaterialOverrides3D(
      values: {
        'color': 0xFF00FF00,
        'tiling': [2.0, 3.0],
      },
    );
    final back =
        definitions.decode(
              jsonDecode(jsonEncode(definitions.encode(o)))
                  as Map<String, dynamic>,
            )!
            as MaterialOverrides3D;
    expect(back.values, {
      'color': 0xFF00FF00,
      'tiling': [2.0, 3.0],
    });
    final revision = back.revision;
    back.set('color', 0xFF00FF00);
    expect(back.revision, revision, reason: 'the same value changes nothing');
  });

  test('a model\'s material files are saved with it', () {
    final definitions = engine.context.definitions;
    final model = ModelComponent(
      model: cubePath,
      materials: {'Body': _red, '#2': _tiles},
    );
    final json =
        jsonDecode(jsonEncode(definitions.encode(model)))
            as Map<String, dynamic>;
    final back = definitions.decode(json)! as ModelComponent;
    expect(back.materials, {'Body': _red, '#2': _tiles});
    final shape = definitions.decode(
      jsonDecode(jsonEncode(definitions.encode(Cube3D(material: _red))))
          as Map<String, dynamic>,
    )!;
    expect((shape as Primitive3D).material, _red);
  });
}
