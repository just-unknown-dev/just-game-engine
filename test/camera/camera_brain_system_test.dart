// The brain's system: on fixed updates it evaluates the brain; with the
// brain running per rendered frame it only samples the targets on fixed
// updates and evaluates in the frame phase, following them between
// updates.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late CameraEngine cameras;
  late TransformComponent player;

  setUp(() {
    world = World()..initialize();
    cameras = CameraEngine()..initialize();
    cameras.mainCamera.viewportSize = const Size(800, 600);
    registerCameraSystems(world, cameras);
    player = TransformComponent(position: Vector3.zero());
    world.createEntityWithComponents([player], name: 'Player');
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -3, -8)),
      VirtualCameraComponent(
        follow: const EntityTarget.name('Player'),
        projection: CameraProjection.perspective,
      ),
      OrbitFollowComponent(damping: 0),
    ]);
  });
  tearDown(() => world.dispose());

  double x() => cameras.mainCamera.position.dx;

  test('per frame: the update samples, the frame phase follows between', () {
    cameras.brain.updateMode = CameraUpdateMode.frame;
    world.update(_dt);
    world.frame(_dt, 1);
    final start = x();

    player.position.x = 1;
    world.update(_dt);
    expect(x(), start, reason: 'a fixed update only samples');
    world.frame(_dt / 2, 0.5);
    expect(x(), closeTo(start + 0.5, 1e-9), reason: 'half way');
    world.frame(_dt / 2, 1);
    expect(x(), closeTo(start + 1, 1e-9));
  });

  test('on fixed updates: the update evaluates, the frame phase does not', () {
    world.update(_dt);
    final start = x();
    player.position.x = 1;
    world.frame(_dt, 0.5);
    expect(x(), start);
    world.update(_dt);
    expect(x(), closeTo(start + 1, 1e-9));
  });
}
