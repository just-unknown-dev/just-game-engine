// Rendering and debug fixes from the 2.0.0 final pass: the collider
// debugger's body filters leave ray colliders alone (F2); RenderingEngine.stats
// count what the ECS RenderSystem draws (F43). (EntitySignal's are in
// reactive/entity_signal_test.dart.)

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts rectangles and circles drawn.
class _Counter extends TestRecordingCanvas {
  int rects = 0;
  int circles = 0;

  @override
  void drawRect(Rect rect, Paint paint) {
    rects++;
    super.drawRect(rect, paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles++;
    super.drawCircle(c, radius, paint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('filtering static bodies still outlines their ray colliders', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final debugger = ColliderDebuggerSystem(includeStaticBodies: false);
    world.addSystem(debugger);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(5, 5, 0)),
      PhysicsBodyRefComponent(
        PhysicsBody(
          position: Vector2(5, 5),
          shape: RectangleShape(10, 10),
          mass: 0,
        ),
      ),
      RaycastColliderComponent(radius: 4),
    ]);
    final canvas = _Counter();
    debugger.render(canvas, const Size(100, 100));
    expect(canvas.rects, 0, reason: 'the static body is filtered');
    expect(canvas.circles, 1, reason: 'its ray collider is not');
  });

  group('render stats count the ECS world', () {
    late World world;
    late RenderingEngine rendering;

    setUp(() {
      world = World()..initialize();
      rendering = RenderingEngine()
        ..camera = Camera(viewportSize: const Size(100, 100))
        ..initialize();
    });
    tearDown(() {
      world.dispose();
      rendering.dispose();
    });

    void shape(double x, {bool visible = true}) {
      final rect = Rectangle2DComponent(width: 10, height: 10);
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
        rect,
      ]);
      rect.renderable.visible = visible;
    }

    test('RenderSystem counts its own draws', () {
      final system = RenderSystem(statsSink: rendering);
      world.addSystem(system);
      shape(0);
      shape(20);
      shape(40, visible: false);
      system.render(TestRecordingCanvas(), const Size(100, 100));
      expect(system.stats, {
        'drawCalls': 2,
        'renderedObjects': 2,
        'culledObjects': 1,
        'batchedSprites': 0,
      });
    });

    test('RenderingEngine.stats fold them into the frame', () {
      final system = RenderSystem(statsSink: rendering);
      world.addSystem(system);
      shape(0);
      shape(20);
      rendering.overlayHooks.add(world.render);
      rendering.render(TestRecordingCanvas(), const Size(100, 100));
      final stats = rendering.stats;
      // The background clear, then the two shapes.
      expect(stats['drawCalls'], 3);
      expect(stats['renderedObjects'], 2);

      // Counts reported outside a frame are dropped when the next starts.
      system.render(TestRecordingCanvas(), const Size(100, 100));
      rendering.render(TestRecordingCanvas(), const Size(100, 100));
      expect(rendering.stats['drawCalls'], 3);
    });

    test('the default systems report to the engine\'s rendering', () async {
      final engine = Engine(
        config: const EngineConfig(defaultSystems: DefaultSystems.all),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(
        engine.world.getSystem<RenderSystem>()!.statsSink,
        same(engine.rendering),
      );
    });
  });
}
