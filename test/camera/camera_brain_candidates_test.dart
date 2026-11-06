// Which cameras the brain picks from, and what it remembers between
// evaluations: a manager's children never compete on their own, even while
// the manager is switched off; a world emptied for a restart starts with a
// cut, not a blend from the old level's shot; and a camera's first frame
// is a snap for every stage, a damped confiner included.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

void main() {
  late World world;
  late OutputCamera output;
  late CameraBrain brain;

  setUp(() {
    world = World();
    output = OutputCamera(viewportSize: _view);
    brain = CameraBrain(output)..defaultBlend = CameraBlend.cut;
  });
  tearDown(() => world.dispose());

  Entity at(Offset position, List<Component> components, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        ...components,
      ], name: name);

  Entity shot(String name, Offset position, {int priority = 10}) =>
      at(position, [VirtualCameraComponent(priority: priority)], name: name);

  void adopt(Entity parent, List<Entity> children) {
    final list = ChildrenComponent();
    parent.addComponent(list);
    for (final child in children) {
      child.addComponent(ParentComponent(parentId: parent.id));
      list.addChild(child.id);
    }
  }

  group("a switched-off manager's children", () {
    late Entity rig;

    setUp(() {
      shot('Main', const Offset(-1, 0), priority: 50);
      rig = at(Offset.zero, [
        VirtualCameraComponent(priority: 60),
        CameraMixerComponent(weights: {'Loud': 1}),
      ], name: 'Rig');
      adopt(rig, [shot('Loud', const Offset(999, 0), priority: 9999)]);
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Rig');
    });

    test('do not go live in its place', () {
      rig.getComponent<VirtualCameraComponent>()!.enabled = false;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Main');
      expect(output.position.dx, -1);
    });

    test('do not win a tie as cameras seen for the first time', () {
      final main = world.findEntityByName('Main')!;
      main.getComponent<VirtualCameraComponent>()!.priority = 9999;
      rig.getComponent<VirtualCameraComponent>()!.enabled = false;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Main');
    });

    test('come back with their manager', () {
      final mixer = rig.getComponent<VirtualCameraComponent>()!;
      mixer.enabled = false;
      brain.evaluate(world, _dt);
      mixer.enabled = true;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Rig');
      expect(output.position.dx, 999);
    });
  });

  test('a world emptied and filled again starts with a cut', () {
    brain.defaultBlend = const CameraBlend(duration: 0.5);
    shot('End', const Offset(5000, 0));
    brain.evaluate(world, _dt);
    expect(output.position.dx, 5000);
    brain.emitImpulse(
      CameraImpulse(position: const Offset(5000, 0), amplitude: 50),
    );

    // A restart: everything goes, the level loads again, then it runs.
    world.destroyAllEntities();
    shot('Spawn', Offset.zero);
    brain.evaluate(world, _dt);
    expect(brain.liveCamera?.name, 'Spawn');
    expect(brain.activeBlend, isNull, reason: 'nothing left to blend from');
    expect(output.position, Offset.zero);
  });

  test('a camera destroyed while others stay still blends away', () {
    brain.defaultBlend = const CameraBlend(duration: 0.5);
    shot('Wide', Offset.zero);
    final close = shot('Close', const Offset(100, 0), priority: 20);
    brain.evaluate(world, _dt);
    expect(brain.liveCamera?.name, 'Close');
    world.destroyEntity(close);
    brain.evaluate(world, _dt);
    expect(brain.liveCamera?.name, 'Wide');
    expect(brain.activeBlend, isNotNull);
  });

  test("a damped confiner is already inside the bounds on a camera's first "
      'frame', () {
    at(Offset.zero, [
      CameraBoundsComponent(width: 1000, height: 1000),
    ], name: 'Room');
    // Near the room's right edge: the view (800 wide) must be pushed in.
    at(const Offset(450, 0), [
      VirtualCameraComponent(),
      CameraConfinerComponent(boundsName: 'Room', damping: 0.3),
    ]);
    brain.evaluate(world, _dt);
    expect(output.position.dx, closeTo(100, 1e-9));
  });
}
