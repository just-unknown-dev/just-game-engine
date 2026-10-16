// Between fixed updates the renderer draws an entity on the way from its
// previous pose to its pose when whatever moves it captured that previous
// pose in the last update (as physics does), and where it is otherwise: a
// transform only gameplay writes has a stale previous pose.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'fixtures.dart';

/// Moves [transform] 1 m along +X each update, capturing its previous pose
/// first while [capture] is set.
final class _Mover extends System {
  _Mover(this.transform, {this.capture = true});

  final TransformComponent transform;
  bool capture;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    if (capture) transform.capturePrevious();
    transform.position.x += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(config: EngineConfig(graphics3D: service));
    await engine.initialize();
  });
  tearDown(() => engine.dispose());

  final view = frameView(eye: Vector3(0, -3, -8));

  TransformComponent add(String name) {
    final transform = TransformComponent();
    engine.world.createEntity(name: name)
      ..addComponent(transform)
      ..addComponent(Cube3D());
    return transform;
  }

  double drawnX(int index) => service.sceneRenderer.debugShapeInstances[index]!.world.storage[12];

  test('a transform moved with its previous pose captured is drawn between the two', () {
    final transform = add('body');
    engine.world.addSystem(_Mover(transform));
    final renderer = service.sceneRenderer..update(view);

    engine.world.update(1 / 60);
    renderer.update(view..interpolation = 0.25);
    expect(drawnX(0), closeTo(0.25, 1e-9));

    // More frames before the next update, and a second view in the same
    // frame, keep drawing between the same two poses.
    renderer
      ..update(view..interpolation = 0.75)
      ..update(view);
    expect(drawnX(0), closeTo(0.75, 1e-9));

    renderer.update(view..interpolation = 1);
    expect(drawnX(0), 1);

    engine.world.update(1 / 60);
    renderer.update(view..interpolation = 0.5);
    expect(drawnX(0), closeTo(1.5, 1e-9));
  });

  test('a transform only gameplay writes is drawn where it is', () {
    final transform = add('prop');
    engine.world.addSystem(_Mover(transform, capture: false));
    final renderer = service.sceneRenderer..update(view);

    engine.world.update(1 / 60);
    renderer.update(view..interpolation = 0.25);
    expect(transform.prevPosition.x, 0, reason: 'stale: captured when it was made');
    expect(drawnX(0), 1);
  });

  test('once its mover stops capturing, it is drawn where it is again', () {
    final transform = add('body');
    final mover = _Mover(transform);
    engine.world.addSystem(mover);
    final renderer = service.sceneRenderer..update(view);

    engine.world.update(1 / 60);
    renderer.update(view..interpolation = 0.5);
    expect(drawnX(0), closeTo(0.5, 1e-9));

    mover.capture = false;
    engine.world.update(1 / 60);
    renderer.update(view);
    expect(drawnX(0), 2);
  });

  test('a rebuild of the scene keeps drawing it between its poses', () {
    final transform = add('body');
    engine.world.addSystem(_Mover(transform));
    final renderer = service.sceneRenderer..update(view);

    engine.world.update(1 / 60);
    add('newcomer');
    renderer.update(view..interpolation = 0.5);
    expect(renderer.debugShapeInstances, hasLength(2));
    expect(drawnX(0), closeTo(0.5, 1e-9));
    expect(drawnX(1), 0, reason: 'never captured since it was made');
  });

  test('turning is drawn between its rotations', () {
    final transform = add('body')..setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), 0.2));
    final renderer = service.sceneRenderer..update(view);

    transform
      ..capturePrevious()
      ..setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), 1.0));
    engine.world.update(1 / 60);
    renderer.update(view..interpolation = 0.5);
    final expected = Matrix4.identity()..setFromTrs(Vector3.zero(), Quaternion.axisAngle(Vector3(0, 1, 0), 0.6), Vector3(1, 1, 1));
    final drawn = renderer.debugShapeInstances.single!.world.storage;
    for (var i = 0; i < 16; i++) {
      expect(drawn[i], closeTo(expected.storage[i], 1e-9), reason: 'm[$i]');
    }
  });
}
