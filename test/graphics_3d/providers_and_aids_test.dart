// What kits and editors add to the 3-D scene renderer, on the null device:
// a provider's meshes and batches built for its component, moved with its
// entity and built again when it says so; and an editor's aids — what it
// hides, its slice, its view mode and the selection's outline — in its
// views and not in the plain ones.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'fixtures.dart';

/// A kit's component: a cube and a row of [copies] smaller ones.
class _Patch extends Component {
  _Patch({this.copies = 3});

  int copies;

  /// Bumped by whoever changes it; the provider reads it.
  int revision = 0;
}

class _PatchProvider extends RenderProvider<_Patch> {
  int builds = 0;

  @override
  Object? revisionOf(_Patch component) => component.revision;

  @override
  void build(
    RenderProviderContext context,
    Entity entity,
    _Patch component,
    RenderProviderOutput out,
  ) {
    builds++;
    final cube = Cube3D();
    final mesh = context.shapes.meshFor(cube, Vector3(1, 1, 1))!;
    final material = context.shapes.materialFor(cube);
    out
      ..addMesh(mesh, material, local: Matrix4.translationValues(0, -2, 0))
      ..addBatch(mesh, material, [
        for (var i = 0; i < component.copies; i++)
          Matrix4.translationValues(i.toDouble(), 0, 0),
      ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  final view = frameView(eye: Vector3(0, -3, -8));

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders), keepEdges: true);
    engine = Engine(config: EngineConfig(graphics3D: service));
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  group('render providers', () {
    late _PatchProvider provider;

    setUp(() {
      provider = _PatchProvider();
      RenderProviders.of(engine.world.context).register(provider);
    });

    Entity patch({Vector3? at, int copies = 3}) => engine.world.createEntity(name: 'patch')
      ..addComponent(TransformComponent(position: at ?? Vector3.zero()))
      ..addComponent(_Patch(copies: copies));

    test('what it builds is drawn where its entity is', () {
      patch(at: Vector3(10, 0, 0));
      final renderer = service.sceneRenderer..update(view);
      expect(provider.builds, 1);
      final batch = renderer.scene.batches.single;
      expect(batch.count, 3);
      expect((batch.bounds.min.x, batch.bounds.max.x), (9.5, 12.5), reason: 'three cubes from x = 10');
      final mesh = renderer.scene.instances.single;
      expect(mesh.world.storage[12], 10);
      expect(mesh.world.storage[13], -2, reason: 'its local placement kept');
    });

    test('it follows its entity, and is built again only when it says so', () {
      final e = patch();
      final renderer = service.sceneRenderer..update(view);
      e.getComponent<TransformComponent>()!.position.x = 5;
      renderer.update(view);
      expect(provider.builds, 1, reason: 'moved, not rebuilt');
      expect(renderer.scene.batches.single.bounds.min.x, 4.5);
      final patchComponent = e.getComponent<_Patch>()!..copies = 5;
      patchComponent.revision++;
      renderer.update(view);
      expect(provider.builds, 2);
      expect(renderer.scene.batches.single.count, 5);
      expect(renderer.scene.batches, hasLength(1), reason: 'the old batch is gone');
      expect(patchComponent.copies, 5, reason: 'its saved fields left alone');
    });

    test('registered after the world was built, it is still drawn', () {
      RenderProviders.of(engine.world.context).unregister(_Patch);
      patch();
      final renderer = service.sceneRenderer..update(view);
      expect(renderer.scene.batches, isEmpty);
      RenderProviders.of(engine.world.context).register(provider);
      renderer.update(view);
      expect(renderer.scene.batches, hasLength(1));
    });

    test('taken away with its component', () {
      final e = patch();
      final renderer = service.sceneRenderer..update(view);
      e.removeComponent<_Patch>();
      renderer.update(view);
      expect(renderer.scene.batches, isEmpty);
      expect(renderer.scene.instances, isEmpty);
    });
  });

  group('an editor\'s aids', () {
    late Entity low, high;
    late GraphicsSceneRenderer renderer;
    late SceneEditorAids aids;
    final preview = frameView(eye: Vector3(0, -3, -8));

    setUp(() {
      low = engine.world.createEntity(name: 'low')
        ..addComponent(TransformComponent(position: Vector3(0, -0.5, 0)))
        ..addComponent(Cube3D());
      high = engine.world.createEntity(name: 'high')
        ..addComponent(TransformComponent(position: Vector3(0, -5, 0)))
        ..addComponent(Cube3D());
      renderer = service.sceneRenderer;
      aids = renderer.aids = SceneEditorAids()..plainViews.add(preview);
    });

    MeshInstance of(Entity e) => renderer.debugShapeInstances
        .cast<MeshInstance>()
        .firstWhere((i) => (i.world.storage[13] - e.getComponent<TransformComponent>()!.position.y).abs() < 1e-9);

    test('what it hides is not drawn in its views, and is in the plain ones', () {
      aids.drawFilter = (e) => e != high;
      renderer.update(view);
      expect(of(low).visible, isTrue);
      expect(of(high).visible, isFalse);
      renderer.update(preview);
      expect(of(high).visible, isTrue, reason: 'the game camera sees it all');
    });

    test('a slice takes away what is wholly above it', () {
      aids.sliceY = -2;
      renderer.update(view);
      expect(of(high).visible, isFalse, reason: '5 m up, the slice at 2 m');
      expect(of(low).visible, isTrue);
      expect(service.renderer.clipPlane, (0, -1, 0, 2));
    });

    test('the selection is outlined, twice: where seen, and faintly through', () {
      aids.highlighted = () => [low];
      renderer.update(view);
      expect(renderer.scene.overlays, hasLength(2));
      expect(renderer.scene.overlays.where((o) => o.xray), hasLength(1));
      renderer.update(preview);
      expect(renderer.scene.overlays, isEmpty);
    });

    test('its view mode applies to its views only', () {
      aids.viewMode = RenderViewMode.wireframe;
      renderer.update(view);
      expect(service.renderer.viewMode, RenderViewMode.wireframe);
      renderer.update(preview);
      expect(service.renderer.viewMode, RenderViewMode.lit);
    });
  });

  test('edges are kept in a debug build, where an editor runs', () {
    expect(Graphics3D().keepEdges, isTrue);
    expect(Graphics3D(keepEdges: false).keepEdges, isFalse);
  });

  test('a camera told it is in space is never planar, whatever its lens', () {
    final camera = Camera();
    expect(camera.isPlanar, isTrue);
    camera.inSpace = true;
    expect(camera.isPlanar, isFalse);
  });
}
