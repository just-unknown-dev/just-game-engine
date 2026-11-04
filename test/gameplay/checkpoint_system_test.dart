// CheckpointSystem: respawn sends the player to the respawn point set by
// hand, then to the last checkpoint touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  late CheckpointSystem system;
  late Entity player;
  late List<PlayerRespawnEvent> respawns;

  setUp(() {
    world = World()..initialize();
    system = CheckpointSystem();
    world.addSystem(system);
    player = world.createEntityWithComponents([
      TransformComponent(position: Vector3(-500, 0, 0)),
      TagComponent('player'),
    ]);
    respawns = [];
    world.events.on<PlayerRespawnEvent>(respawns.add);
  });
  tearDown(() => world.dispose());

  Entity checkpointAt(double x, Vector3 respawn) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
        CheckpointComponent(respawnPosition: respawn, radius: 10),
      ]);

  void moveTo(double x) =>
      player.getComponent<TransformComponent>()!.position.x = x;

  test('respawn uses the point set by hand', () {
    system.setRespawnPoint(Vector3(5, 0, 0));
    system.respawn(player);
    expect(respawns, hasLength(1));
    expect(respawns.single.playerEntity, player);
    expect(respawns.single.respawnPosition.x, 5);
  });

  test('a checkpoint touched replaces it, and a later one wins', () {
    system.setRespawnPoint(Vector3(5, 0, 0));
    checkpointAt(100, Vector3(40, 0, 0));
    checkpointAt(300, Vector3(280, 0, 0));
    moveTo(100);
    world.update(1 / 60);
    system.respawn(player);
    expect(respawns.last.respawnPosition.x, 40);

    moveTo(300);
    world.update(1 / 60);
    system.respawn(player);
    expect(respawns.last.respawnPosition.x, 280);
    expect(system.currentRespawnPoint.x, 280);
  });

  test('setRespawnPoint keeps its own copy', () {
    final at = Vector3(5, 0, 0);
    system.setRespawnPoint(at);
    at.x = 99;
    expect(system.currentRespawnPoint.x, 5);
  });
}
