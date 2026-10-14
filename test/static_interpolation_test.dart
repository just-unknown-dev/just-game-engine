// A static physics body is drawn where it is. Its previous pose used to be
// left at the origin by a scene load or a play-snapshot restore, and render
// interpolation then threw it back and forth along the line from (0, 0) to
// where it stood, every frame, for as long as the game ran.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('a decoded transform starts with its previous pose at its pose', () {
    final registry = ComponentDefinitionRegistry.core();
    final t =
        registry.decode({
              'type': 'TransformComponent',
              'fields': {
                'position': {'x': -64.0, 'y': -214.0, 'z': 0.0},
                'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.5},
                'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
              },
            })
            as TransformComponent;
    expect(t.prevPosition.x, -64);
    expect(t.prevPosition.y, -214);
    expect(t.prevAngle, 0.5);
  });

  group('a static body', () {
    late PhysicsEngine physics;
    late World world;

    setUp(() {
      physics = PhysicsEngine()..initialize();
      world = World()..initialize();
      world.addSystem(PhysicsSystem(physics));
    });
    tearDown(() {
      world.dispose();
      physics.dispose();
    });

    Entity block({required bool isStatic}) => world.createEntityWithComponents([
      TransformComponent(position: Vector3(-64, -214, 0)),
      RectangleComponent(width: 64, height: 20),
      RigidBody2D(bodyType: isStatic ? BodyType.static : BodyType.dynamic),
      Collider2D(size: Vector2(64, 20)),
    ]);

    test('gets its previous pose back after something outside physics '
        'left it behind', () {
      final e = block(isStatic: true);
      world.update(1 / 60);
      final t = e.getComponent<TransformComponent>()!;
      // What a play-snapshot restore did: the pose kept, the previous pose
      // at the origin, and the body already made.
      t.prevPosition.setValues(0, 0, 0);
      world.update(1 / 60);
      expect(t.prevPosition.x, -64);
      expect(t.prevPosition.y, -214);
    });

    test('is drawn where it is, while a dynamic one is interpolated', () {
      final still = block(isStatic: true);
      final falling = block(isStatic: false);
      world.update(1 / 60);
      final render = RenderSystem()..interpolation = 0.5;
      world.addSystem(render);
      // Both previous poses left behind, as a restore leaves them.
      still.getComponent<TransformComponent>()!.prevPosition.setValues(0, 0, 0);
      final ft = falling.getComponent<TransformComponent>()!;
      ft.prevPosition.setValues(ft.position.x, ft.position.y - 10, 0);

      final recorder = PictureRecorder();
      render.render(Canvas(recorder), const Size(800, 600));
      recorder.endRecording();

      final stillAt = still.getComponent<RenderableComponent>()!.renderable;
      expect(stillAt.position.x, -64);
      expect(stillAt.position.y, -214);
      final fallingAt = falling.getComponent<RenderableComponent>()!.renderable;
      expect(fallingAt.position.y, closeTo(ft.position.y - 5, 1e-9));
    });
  });
}
