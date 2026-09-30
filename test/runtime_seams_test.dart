import 'dart:math' as math;
import 'dart:ui' show Canvas, Offset, PictureRecorder, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Recorder extends SceneRenderer {
  _Recorder(this.name, this.log, {this.order = 0});
  final String name;
  final List<String> log;
  @override
  final int order;
  bool on = true;
  Size? seen;
  @override
  bool get enabled => on;
  @override
  void render(Canvas canvas, RenderView view) {
    log.add(name);
    seen = view.viewportSize;
  }
}

class _Counting extends EnginePlugin {
  int draws = 0;
  @override
  String get id => 'counting';
  @override
  void renderOverlay(Canvas canvas, Size size) => draws++;
}

class _MyRendering extends RenderingEngine {}

RenderingEngine _rendering() => RenderingEngine()
  ..camera = Camera(viewportSize: const Size(640, 360))
  ..initialize();

void _frame(RenderingEngine r) =>
    r.render(Canvas(PictureRecorder()), const Size(640, 360));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scene renderers', () {
    test('run once a frame, in order, and not while disabled', () {
      final r = _rendering();
      final log = <String>[];
      final late = _Recorder('late', log, order: 5);
      final early = _Recorder('early', log, order: -1);
      r
        ..addSceneRenderer(late)
        ..addSceneRenderer(early)
        ..addSceneRenderer(early);
      expect(r.sceneRenderers, [early, late]);
      _frame(r);
      expect(log, ['early', 'late']);
      expect(early.seen, const Size(640, 360));
      late.on = false;
      _frame(r);
      expect(log, ['early', 'late', 'early']);
      expect(r.removeSceneRenderer(early), isTrue);
    });

    test('the frame\'s view is the camera, as matrices', () {
      final r = _rendering();
      r.camera
        ..position = const Offset(10, 20)
        ..zoom = 2;
      _frame(r);
      final view = r.view;
      expect(identical(view, r.view), isTrue, reason: 'reused');
      final expected = Matrix4.zero();
      r.camera.canvasMatrixInto(expected);
      for (var i = 0; i < 16; i++) {
        expect(view.canvas.storage[i], closeTo(expected.storage[i], 1e-12));
      }
      expect(view.isPlanar, isTrue);
      expect(view.visibleRect, r.camera.getVisibleBounds());
    });
  });

  group('the engine', () {
    setUp(Engine.resetInstance);
    tearDown(Engine.resetInstance);

    test('draws each plugin over the world exactly once a frame', () async {
      final engine = Engine();
      await engine.initialize();
      final plugin = _Counting();
      engine.plugins.register(plugin);
      engine.rendering.render(
        Canvas(PictureRecorder()),
        const Size(100, 100),
      );
      expect(plugin.draws, 1);
    });

    test('builds the rendering engine it is given', () async {
      final engine = Engine();
      await engine.initialize(
        config: EngineConfig(createRendering: _MyRendering.new),
      );
      expect(engine.rendering, isA<_MyRendering>());
    });
  });

  group('view volumes', () {
    test('a 2-D camera sees a rectangle at every depth', () {
      final camera = Camera(viewportSize: const Size(200, 100));
      final volume = camera.viewVolume;
      expect(volume, isA<PlanarViewVolume>());
      expect(volume.planarBounds, const Rect.fromLTRB(-100, -50, 100, 50));
      expect(
        volume.intersectsAabb(Aabb3()..setValues(50, 0, -500, 60, 10, 500)),
        isTrue,
      );
      expect(
        volume.intersectsAabb(Aabb3()..setValues(150, 0, 0, 160, 10, 0)),
        isFalse,
      );
    });

    test('a camera in space sees a frustum', () {
      final camera = Camera(
        viewportSize: const Size(100, 100),
        z: -10,
        lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
      );
      final volume = camera.viewVolume;
      expect(volume, isA<FrustumViewVolume>());
      // In front, in view.
      expect(
        volume.intersectsAabb(Aabb3()..setValues(-1, -1, -1, 1, 1, 1)),
        isTrue,
      );
      // Behind the camera.
      expect(
        volume.intersectsAabb(Aabb3()..setValues(-1, -1, -30, 1, 1, -20)),
        isFalse,
      );
      // Far off to the side.
      expect(
        volume.intersectsAabb(Aabb3()..setValues(100, 0, 0, 110, 1, 1)),
        isFalse,
      );
    });
  });

  test('a planar spatial index finds entities by their footprint', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final near = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 10, 0)),
    ]);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(1000, 1000, 0)),
    ]);
    final index = PlanarSpatialIndex(cellSize: 64)
      ..sync(world.entities, (e, out) {
        final p = e.getComponent<TransformComponent>()!.position;
        out.setValues(p.x - 5, p.y - 5, p.z, p.x + 5, p.y + 5, p.z);
      });
    final found = <Entity>[];
    index.query(Aabb3()..setValues(0, 0, -1, 50, 50, 1), found);
    expect(found, [near]);
  });

  test('the audio listener faces the world, with +X on its right', () {
    final listener = AudioListenerComponent();
    final forward = Vector3(
      listener.forwardX,
      listener.forwardY,
      listener.forwardZ,
    );
    final up = Vector3(listener.upX, listener.upY, listener.upZ);
    final right = forward.cross(up);
    // As before (forward (0,0,-1), up (0,1,0)): panning is unchanged.
    expect([right.x, right.y, right.z], [1, 0, 0]);
    expect([up.x, up.y, up.z], [0, -1, 0]);
  });

  test('a flat extent is a box with no depth', () {
    registerCoreCodecs();
    final def = ComponentDefinitionRegistry.instance.definitionByType(
      'RectangleComponent',
    )!;
    final box = Aabb3();
    expect(
      def.extent!.boundsInto(RectangleComponent(width: 40, height: 20), box),
      isTrue,
    );
    expect([box.min.x, box.max.x, box.min.y, box.max.y], [-20, 20, -10, 10]);
    expect(box.min.z, 0);
  });
}
