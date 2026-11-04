// What kits and editors add to the 3-D scene renderer, on the null device:
// a provider's meshes and batches built for its component, moved with its
// entity and built again when it says so; and an editor's aids — what it
// hides, its slice, its view mode and the selection's outline — in its
// views and not in the plain ones. Views drawn in one engine frame (an
// editor's panes) share one look at the world.
@Tags(['graphics3d'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart' show NullGpuDevice, rendererNullShaders;

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

  /// How many times the renderer asked whether a patch changed.
  int looks = 0;

  @override
  Object? revisionOf(_Patch component) {
    looks++;
    return component.revision;
  }

  @override
  void build(
    RenderProviderContext context,
    Entity entity,
    _Patch component,
    RenderProviderOutput out,
  ) {
    builds++;
    final cube = Cube3DComponent();
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
    engine = Engine(config: EngineConfig(services: [service]));
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  /// One engine frame that also draws [panes], as an editor's split view
  /// does from its overlay hook.
  void drawFrame(List<FrameView> panes) {
    final renderer = service.sceneRenderer..renderWithoutGpu = true;
    void drawPanes(ui.Canvas canvas, ui.Size size) {
      for (final pane in panes) {
        renderer.render(canvas, pane);
      }
    }

    engine.rendering.overlayHooks.add(drawPanes);
    engine.rendering.render(ui.Canvas(ui.PictureRecorder()), const ui.Size(64, 48));
    engine.rendering.overlayHooks.remove(drawPanes);
  }

  group('render providers', () {
    late _PatchProvider provider;

    setUp(() {
      provider = _PatchProvider();
      engine.world.context.renderProviders.register(provider);
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
      engine.world.context.renderProviders.unregister(_Patch);
      patch();
      final renderer = service.sceneRenderer..update(view);
      expect(renderer.scene.batches, isEmpty);
      engine.world.context.renderProviders.register(provider);
      renderer.update(view);
      expect(renderer.scene.batches, hasLength(1));
    });

    test('one registered in its place builds its entities afresh', () {
      patch();
      final renderer = service.sceneRenderer..update(view);
      final old = renderer.scene.batches.single;
      final replacement = _PatchProvider();
      engine.world.context.renderProviders.register(replacement);
      renderer.update(view);
      expect(replacement.builds, 1);
      expect(renderer.scene.batches.single, isNot(same(old)));
      renderer.update(view);
      expect((provider.builds, replacement.builds), (1, 1));
    });

    test('a moving batch follows each move; rebuilt, only its own leave', () {
      final first = patch();
      final second = patch(at: Vector3(0, 0, 10), copies: 2);
      final renderer = service.sceneRenderer..update(view);
      final transform = first.getComponent<TransformComponent>()!;
      for (final x in [3.0, 7.0]) {
        transform.position.x = x;
        renderer.update(view);
        expect(renderer.scene.batches.first.bounds.min.x, x - 0.5);
      }
      final [moving, rebuilt] = renderer.scene.batches;
      second.getComponent<_Patch>()!.revision++;
      renderer.update(view);
      expect(renderer.scene.batches, hasLength(2));
      expect(renderer.scene.batches.first, same(moving));
      expect(renderer.scene.batches.last, isNot(same(rebuilt)), reason: 'the rebuilt one\'s old batch left');
      expect(renderer.scene.batches.last.count, 2);
      expect(renderer.scene.instances, hasLength(2));
    });

    test('each engine has its own', () {
      final context = engine.world.context;
      expect(context.renderProviders, same(context.renderProviders));
      expect(EngineContext().renderProviders, isNot(same(context.renderProviders)));
    });

    test('views drawn in one frame look the world over once', () {
      patch();
      final panes = [for (var i = 0; i < 3; i++) frameView(eye: Vector3(i.toDouble(), -3, -8))];
      drawFrame(panes);
      expect(engine.rendering.drawingFrame, isNull, reason: 'between frames');
      provider.looks = 0;
      drawFrame(panes);
      expect(provider.looks, 1, reason: 'the game view and three panes: one look');
      final e = engine.world.findEntityByName('patch')!;
      e.getComponent<TransformComponent>()!.position.x = 4;
      drawFrame(panes);
      expect(provider.looks, 2);
      expect(service.sceneRenderer.scene.batches.single.bounds.min.x, 3.5, reason: 'the next frame sees the move');
      service.sceneRenderer.update(panes.first);
      service.sceneRenderer.update(panes.last);
      expect(provider.looks, 4, reason: 'outside a frame, every view looks');
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
    late Graphics3DSceneRenderer renderer;
    late SceneEditorAids aids;
    final preview = frameView(eye: Vector3(0, -3, -8));

    setUp(() {
      low = engine.world.createEntity(name: 'low')
        ..addComponent(TransformComponent(position: Vector3(0, -0.5, 0)))
        ..addComponent(Cube3DComponent());
      high = engine.world.createEntity(name: 'high')
        ..addComponent(TransformComponent(position: Vector3(0, -5, 0)))
        ..addComponent(Cube3DComponent());
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

    test('in one frame, a plain view after an aided one shows what it hid', () {
      aids.drawFilter = (e) => e != high;
      aids.skippedViews.add(engine.rendering.view);
      drawFrame([view, preview]);
      expect(of(high).visible, isTrue, reason: 'the preview, drawn last, sees it');
      drawFrame([preview, view]);
      expect(of(high).visible, isFalse, reason: 'the aided view, drawn last, hides it');
      expect(of(low).visible, isTrue);
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
    final camera = OutputCamera();
    expect(camera.isPlanar, isTrue);
    camera.inSpace = true;
    expect(camera.isPlanar, isFalse);
  });
}
