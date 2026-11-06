// A camera trigger system taken out of the world gives back what its
// triggers borrowed: boosts come off and cameras held on go off again, so
// the cameras' saved fields are as authored.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

void main() {
  late World world;
  late CameraTriggerSystem triggers;

  setUp(() {
    world = World();
    triggers = CameraTriggerSystem();
    world.addSystem(triggers);
  });
  tearDown(() => world.dispose());

  Entity at(Offset position, List<Component> components, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        ...components,
      ], name: name);

  test('removed, it takes back every boost and lets go of every camera', () {
    at(Offset.zero, [TagComponent('player')]);
    final boosted = VirtualCameraComponent(priority: 10);
    final held = VirtualCameraComponent(priority: 10, enabled: false);
    at(Offset.zero, [boosted], name: 'Boosted');
    at(Offset.zero, [held], name: 'Held');
    final boost = CameraTriggerComponent(
      cameraName: 'Boosted',
      mode: CameraTriggerMode.boostPriority,
      amount: 50,
    );
    at(Offset.zero, [boost]);
    at(Offset.zero, [CameraTriggerComponent(cameraName: 'Held')]);
    world.update(_dt);
    expect(boosted.priority, 60);
    expect(held.enabled, isTrue);
    expect(boost.isBoosted, isTrue);

    world.removeSystem(triggers);
    expect(boosted.priority, 10);
    expect(held.enabled, isFalse);
    expect(boost.isBoosted, isFalse);
  });

  test('clearing the systems gives them back too', () {
    at(Offset.zero, [TagComponent('player')]);
    final boosted = VirtualCameraComponent(priority: 1);
    at(Offset.zero, [boosted], name: 'Cam');
    at(Offset.zero, [
      CameraTriggerComponent(
        cameraName: 'Cam',
        mode: CameraTriggerMode.boostPriority,
        amount: 7,
      ),
    ]);
    world.update(_dt);
    expect(boosted.priority, 8);
    world.clearSystems();
    expect(boosted.priority, 1);
  });
}
