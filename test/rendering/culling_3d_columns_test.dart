// 3-D culling reads only the columns with an extent.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('3-D culling by the columns with an extent', () {
    late World world;
    setUp(() {
      world = World(extensions: [BuiltInComponents.extension]);
      world.addSystem(
        ViewCullingSystem(
          camera: OutputCamera(
            viewportSize: const Size(400, 400),
            z: -10,
            lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
          ),
        )..activeDistance = 1,
      );
    });
    tearDown(() => world.dispose());

    test('an entity outside the view but reaching into it is visible, and '
        'a size change is seen', () {
      // At x 200, far beyond the view's edge (10 at this distance) —
      // unless its rectangle reaches back into it.
      final rect = Rectangle2DComponent(width: 500, height: 4);
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        rect,
        TagComponent('wide'),
      ]);
      final cull = e.getComponent<CullStateComponent>()!;
      world.update(1 / 60);
      expect(cull.isVisible, isTrue);

      // A smaller rectangle in its place: out of view.
      e.addComponent(Rectangle2DComponent(width: 2, height: 2));
      world.update(1 / 60);
      expect(cull.isVisible, isFalse);
    });

    test('several shapes in one column are each measured', () {
      final wide = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        Rectangle2DComponent(width: 500, height: 4),
      ]);
      final round = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        Circle2DComponent(radius: 1),
      ]);
      world.update(1 / 60);
      expect(wide.getComponent<CullStateComponent>()!.isVisible, isTrue);
      expect(round.getComponent<CullStateComponent>()!.isVisible, isFalse);
    });
  });
}
