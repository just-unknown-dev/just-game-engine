// Several players: one tag stands for all of them — the group frames every
// one, and a trigger fires for whichever walks in.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

void main() {
  late World world;
  late CameraSystem cameras;

  setUp(() {
    world = World();
    cameras = CameraSystem()..initialize();
    cameras.mainCamera.viewportSize = const Size(800, 600);
    cameras.brain.defaultBlend = CameraBlend.cut;
    registerCameraSystems(world, cameras);
  });
  tearDown(() => world.dispose());

  Entity at(Offset position, List<Component> components, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        ...components,
      ], name: name);

  Entity player(Offset position) => at(position, [TagComponent('player')]);

  test('a member by tag is every player, however many have joined', () {
    player(const Offset(0, 0));
    final group = at(Offset.zero, [
      CameraTargetGroupComponent(
        members: [CameraGroupMember(tag: 'player', radius: 10)],
      ),
    ], name: 'Players');
    world.update(_dt);
    expect(group.getComponent<CameraTargetGroupComponent>()!.resolved, 1);

    player(const Offset(200, 0));
    player(const Offset(100, 90));
    world.update(_dt);
    final framing = group.getComponent<CameraTargetGroupComponent>()!;
    expect(framing.resolved, 3);
    expect(
      group.getComponent<TransformComponent>()!.position.toOffset(),
      const Offset(100, 30),
    );
    expect(framing.bounds, const Rect.fromLTRB(-10, -10, 210, 100));
  });

  test('a player who has left the world is left out', () {
    player(const Offset(0, 0));
    final gone = player(const Offset(400, 0));
    final group = at(Offset.zero, [
      CameraTargetGroupComponent(members: [CameraGroupMember(tag: 'player')]),
    ]);
    gone.isActive = false;
    world.update(_dt);
    expect(group.getComponent<CameraTargetGroupComponent>()!.resolved, 1);
  });

  test('a name still means one entity, ahead of the tag', () {
    player(const Offset(0, 0));
    at(const Offset(500, 0), const [], name: 'Boss');
    final group = at(Offset.zero, [
      CameraTargetGroupComponent(
        members: [CameraGroupMember(name: 'Boss', tag: 'player')],
      ),
    ]);
    world.update(_dt);
    expect(
      group.getComponent<TransformComponent>()!.position.toOffset(),
      const Offset(500, 0),
    );
  });

  test('a trigger on the tag fires for any player inside', () {
    final one = player(const Offset(0, 0));
    final two = player(const Offset(1000, 0));
    final shot = at(Offset.zero, [
      VirtualCameraComponent(enabled: false, priority: 20),
    ], name: 'Shot');
    at(const Offset(600, 0), [
      CameraTriggerComponent(
        width: 200,
        height: 200,
        cameraName: 'Shot',
        targetTag: 'player',
      ),
    ]);
    final vcam = shot.getComponent<VirtualCameraComponent>()!;
    world.update(_dt);
    expect(vcam.enabled, isFalse);

    two.getComponent<TransformComponent>()!.setPositionXY(620, 0);
    world.update(_dt);
    expect(vcam.enabled, isTrue, reason: 'player 2 is in, player 1 is not');

    one.getComponent<TransformComponent>()!.setPositionXY(600, 10);
    two.getComponent<TransformComponent>()!.setPositionXY(1000, 0);
    world.update(_dt);
    expect(vcam.enabled, isTrue, reason: 'now player 1 is');
  });
}
