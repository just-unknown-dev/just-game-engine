import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  late Camera camera;
  late ViewCullingSystem system;

  setUp(() {
    world = World();
    camera = Camera(position: Offset.zero, zoom: 1.0)
      ..viewportSize = const Size(800, 600);
    // render rect: 960x720 centered at origin -> x in (-480,480), y in (-360,360)
    // active rect: 1600x1200 centered at origin -> x in (-800,800), y in (-600,600)
    system = ViewCullingSystem(camera: camera);
    world.addSystem(system);
  });

  Entity spawnAt(double x, double y) {
    return world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(x, y)),
      CullStateComponent(),
      RenderableComponent(
        renderable: CircleRenderable(radius: 5, fillColor: Colors.red),
      ),
    ]);
  }

  test('entity near the camera is visible and active', () {
    final entity = spawnAt(0, 0);
    world.update(0.016);

    final cull = entity.getComponent<CullStateComponent>()!;
    expect(cull.isVisible, isTrue);
    expect(cull.isActive, isTrue);
    expect(
      entity.getComponent<RenderableComponent>()!.renderable.visible,
      isTrue,
    );
  });

  test(
    'entity beyond the render radius but within the active radius is active but not visible',
    () {
      final entity = spawnAt(700, 0); // outside 480 render edge, inside 800 active edge
      world.update(0.016);

      final cull = entity.getComponent<CullStateComponent>()!;
      expect(cull.isVisible, isFalse);
      expect(cull.isActive, isTrue);
      expect(
        entity.getComponent<RenderableComponent>()!.renderable.visible,
        isFalse,
      );
    },
  );

  test('entity beyond the active radius is neither visible nor active', () {
    final entity = spawnAt(900, 0); // outside both the 480 and 800 edges
    world.update(0.016);

    final cull = entity.getComponent<CullStateComponent>()!;
    expect(cull.isVisible, isFalse);
    expect(cull.isActive, isFalse);
  });

  test('entity far outside every grid cell is culled via the broad phase', () {
    final entity = spawnAt(50000, 50000);
    world.update(0.016);

    final cull = entity.getComponent<CullStateComponent>()!;
    expect(cull.isVisible, isFalse);
    expect(cull.isActive, isFalse);
  });

  test(
    'hysteresis keeps an already-visible entity visible just past the render edge',
    () {
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3.fromXY(470, 0)),
        CullStateComponent(),
      ]);

      world.update(0.016);
      expect(entity.getComponent<CullStateComponent>()!.isVisible, isTrue);

      // Move just past the plain render edge (480) but within the
      // hysteresis-inflated edge (480 + 24 = 504).
      entity.getComponent<TransformComponent>()!.position.x = 495;
      world.update(0.016);
      expect(
        entity.getComponent<CullStateComponent>()!.isVisible,
        isTrue,
        reason: 'should stay visible inside the hysteresis margin',
      );

      // Move beyond even the hysteresis edge.
      entity.getComponent<TransformComponent>()!.position.x = 520;
      world.update(0.016);
      expect(entity.getComponent<CullStateComponent>()!.isVisible, isFalse);
    },
  );

  test(
    'an entity newly appearing past the plain render edge (never visible before) is not visible, even within the hysteresis margin',
    () {
      final entity = spawnAt(495, 0); // within hysteresis edge, but was never visible
      world.update(0.016);

      expect(entity.getComponent<CullStateComponent>()!.isVisible, isFalse);
    },
  );

  test('entities without CullStateComponent are left untouched', () {
    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(50000, 50000)),
      RenderableComponent(
        renderable: CircleRenderable(radius: 5, fillColor: Colors.blue),
      ),
    ]);

    world.update(0.016);

    expect(
      entity.getComponent<RenderableComponent>()!.renderable.visible,
      isTrue,
    );
  });
}
