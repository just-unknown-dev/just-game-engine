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

Uint8List _file(MaterialFile file) => Uint8List.fromList(utf8.encode(file.encode()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  late TestBundle bundle;

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    bundle = TestBundle({
      _red: _file(const MaterialFile(color: 0xFFFF0000, roughness: 0.2)),
      _tiles: _file(const MaterialFile(uv: MaterialUv.metres, tilingX: 2, tilingY: 2)),
      _broken: Uint8List.fromList(utf8.encode('{"formatVersion": 1, "kind": "glass"}')),
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
    final e = engine.world.createEntity(name: name)..addComponent(TransformComponent());
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

  test('a shape is drawn with its material file once read, and again when it changes', () async {
    final renderer = service.sceneRenderer;
    add('crate', [Cube3D(material: _red)]);
    renderer.update(view);
    final instance = renderer.debugShapeInstances.single!;
    expect(instance.material.data.roughness, 0.75, reason: 'its own look meanwhile');
    await until(() => instance.material.data.roughness == 0.2);
    final (r, g, b, a) = instance.material.data.baseColor;
    expect([r, g, b, a], [1, 0, 0, 1], reason: 'red, made linear');

    bundle.files[_red] = _file(const MaterialFile(roughness: 0.9));
    renderer.materials.reload(_red);
    await until(() => instance.material.data.roughness == 0.9);
  });

  test('laid out in metres: the mesh is made for its size', () async {
    final renderer = service.sceneRenderer;
    final cube = Cube3D(material: _tiles);
    add('floor', [cube]);
    renderer.update(view);
    await until(() => renderer.shapes.tilesInMetres(cube));
    final scale = (renderer.debugShapeInstances.single!.material.data.baseColorTexture!.scale);
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
      return instances.isNotEmpty && instances.single.material.data.roughness == 0.2;
    });
    model.materials = {};
    renderer.update(view);
    expect(renderer.debugModelInstances.single.material.data.roughness, closeTo(0.6, 1e-6), reason: 'its own again');
    model.materials = {'#0': _red};
    renderer.update(view);
    expect(renderer.debugModelInstances.single.material.data.roughness, 0.2, reason: 'by index');
  });

  test('a layered material: its layers tiled as each says', () {
    final data = MaterialLibrary.dataOf(
      const MaterialFile(kind: MaterialKind.layered, layers: [_tiles, _red]),
      layers: const [MaterialFile(tilingX: 4), MaterialFile(tilingX: 0.5)],
    );
    expect(data.layered, isTrue);
    expect(data.layerTiling, (4.0, 0.5, 1.0, 1.0));
    final world = MaterialLibrary.dataOf(const MaterialFile(uv: MaterialUv.world, opacity: 0.5));
    expect(world.uvMode, UvMode.world);
    expect(world.alphaMode, AlphaMode.blend);
  });

  test('a model\'s material files are saved with it', () {
    final definitions = engine.context.definitions;
    final model = ModelComponent(model: cubePath, materials: {'Body': _red, '#2': _tiles});
    final json = jsonDecode(jsonEncode(definitions.encode(model))) as Map<String, dynamic>;
    final back = definitions.decode(json)! as ModelComponent;
    expect(back.materials, {'Body': _red, '#2': _tiles});
    final shape = definitions.decode(jsonDecode(jsonEncode(definitions.encode(Cube3D(material: _red)))) as Map<String, dynamic>)!;
    expect((shape as Primitive3D).material, _red);
  });
}
