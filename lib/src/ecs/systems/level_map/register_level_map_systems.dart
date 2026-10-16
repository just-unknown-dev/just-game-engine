/// Registering the level map systems in one call.
library;

import '../../ecs.dart';
import 'map_collision_system.dart';
import 'level_map_system.dart';

/// Adds what level maps need to [world]: the system that loads and draws
/// them and the one that builds their collision. Skips any already there,
/// so calling it twice is harmless.
///
/// Draw with a `RenderSystem` too — map layers are its render items.
void registerLevelMapSystems(World world, {bool collision = true}) {
  if (!world.systems.any((s) => s is LevelMapSystem)) {
    world.addSystem(LevelMapSystem());
  }
  if (collision && !world.systems.any((s) => s is MapCollisionSystem)) {
    world.addSystem(MapCollisionSystem());
  }
}
