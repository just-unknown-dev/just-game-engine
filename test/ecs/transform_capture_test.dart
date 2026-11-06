// A transform remembers the world update its previous pose was last
// captured in — runtime state, never saved — so a renderer that sees it for
// the first time can tell a pose a fixed step just captured from one left
// long ago. Settling the previous pose (a static body placed) is not a
// capture.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Captures every transform's previous pose, then moves it, each update —
/// what a physics step does to a moving body.
class _Stepper extends System {
  @override
  List<Type> get requiredComponents => const [TransformComponent];

  bool stepping = true;

  @override
  void update(double deltaTime) {
    if (!stepping) return;
    forEach((e) {
      e.getComponent<TransformComponent>()!
        ..capturePrevious()
        ..position.x += 10;
    });
  }
}

void main() {
  late World world;
  late _Stepper stepper;

  setUp(() {
    world = World()..initialize();
    stepper = _Stepper();
    world.addSystem(stepper);
  });
  tearDown(() => world.dispose());

  test("a capture in an update remembers that update", () {
    final t = TransformComponent();
    world.createEntityWithComponents([t]);
    expect(t.capturedInUpdate, -1, reason: 'not captured on this world yet');
    world.update(1 / 60);
    expect(t.capturedInUpdate, world.updateCount);
    stepper.stepping = false;
    world.update(1 / 60);
    expect(t.capturedInUpdate, world.updateCount - 1);
  });

  test('a transform on no entity has no capture update', () {
    final t = TransformComponent()..capturePrevious();
    expect(t.captureCount, 1);
    expect(t.capturedInUpdate, -1);
  });

  test('it forgets the update once it leaves the world', () {
    final t = TransformComponent();
    final e = world.createEntityWithComponents([t]);
    world.update(1 / 60);
    expect(t.capturedInUpdate, isNot(-1));
    e.removeComponent<TransformComponent>();
    expect(t.capturedInUpdate, -1);
    t.capturePrevious();
    expect(t.capturedInUpdate, -1, reason: 'on no world');
  });

  test('settling the previous pose is not a capture', () {
    final t = TransformComponent(position: Vector3(5, 6, 0), angle: 0.3);
    world.createEntityWithComponents([t]);
    stepper.stepping = false;
    world.update(1 / 60);
    t
      ..prevPosition.setValues(0, 0, 0)
      ..prevAngle = 0
      ..settlePrevious();
    expect(t.prevPosition, Vector3(5, 6, 0));
    expect(t.prevAngle, 0.3);
    expect(t.captureCount, 0);
    expect(t.capturedInUpdate, -1);
  });

  test('the capture update is not saved', () {
    final t = TransformComponent(position: Vector3(1, 2, 3));
    world.createEntityWithComponents([t]);
    world.update(1 / 60);
    final json = EcsDefinitions.all
        .firstWhere((d) => d.type == 'TransformComponent')
        .encodeAny(t);
    expect(json.toString(), isNot(contains('captur')));
  });
}
