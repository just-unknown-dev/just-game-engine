/// The engine's standard systems, added in one call.
library;

import 'engine.dart';
import '../interfaces/game_camera.dart';
import '../ecs/ecs.dart';
import '../ecs/systems/animation/register_animation_systems.dart';
import '../ecs/systems/audio/audio_system.dart';
import '../ecs/systems/camera/camera_brain_system.dart';
import '../ecs/systems/core/movement_system.dart';
import '../ecs/systems/input/input_system.dart';
import '../ecs/systems/level_map/level_map_system.dart';
import '../ecs/systems/level_map/map_collision_system.dart';
import '../ecs/systems/physics/physics_system.dart';
import '../ecs/systems/rendering/parallax_render_system.dart';
import '../ecs/systems/rendering/render_system.dart';

/// One of the engine's standard sets of systems; see [registerDefaultSystems].
enum DefaultSystem {
  /// `InputSystem`: the engine's input actions onto input components.
  input,

  /// `PhysicsSystem`: steps the engine's physics and syncs bodies.
  physics,

  /// `MovementSystem`: velocities onto transforms.
  movement,

  /// `AudioSystem`: sound sources and the listener.
  audio,

  /// `RenderSystem`: draws the world through the camera; and
  /// `ParallaxRenderSystem`: `ParallaxComponent` backgrounds behind it.
  rendering,

  /// The sprite systems ([registerSpriteSystems]): sprites, animators, clips,
  /// timelines.
  sprites,

  /// `LevelMapSystem`: draws level maps.
  levelMaps,

  /// `MapCollisionSystem`: the bodies a level map's tiles stand for.
  mapCollision,

  /// The camera systems ([registerCameraSystems]): target groups, triggers
  /// and the brain.
  cameras,
}

/// Sets of [DefaultSystem]s.
abstract final class DefaultSystems {
  /// Everything a game's world usually runs.
  static const Set<DefaultSystem> all = {
    DefaultSystem.input,
    DefaultSystem.physics,
    DefaultSystem.movement,
    DefaultSystem.audio,
    DefaultSystem.rendering,
    DefaultSystem.sprites,
    DefaultSystem.levelMaps,
    DefaultSystem.mapCollision,
    DefaultSystem.cameras,
  };

  /// [all] but what draws and plays: a server, a simulation, a test.
  static const Set<DefaultSystem> headless = {
    DefaultSystem.input,
    DefaultSystem.physics,
    DefaultSystem.movement,
    DefaultSystem.sprites,
    DefaultSystem.levelMaps,
    DefaultSystem.mapCollision,
    DefaultSystem.cameras,
  };
}

/// Adds the engine's standard systems in [include] to [world] — the engine's
/// world, normally, or another world run with [engine]'s subsystems.
///
/// Each is added at most once: one already in [world] (a game's own
/// configured instance) is kept, so this can be called again safely. The
/// order they run in comes from their priorities, not from this call.
///
/// Systems that draw in world space get [camera] — the engine's main camera
/// when null. The input system copies the actions of [inputMaps].
///
/// `EngineConfig(defaultSystems: ...)` calls this as the engine initializes.
void registerDefaultSystems(
  World world,
  Engine engine, {
  Set<DefaultSystem> include = DefaultSystems.all,
  GameCamera? camera,
  List<String> inputMaps = const ['player'],
}) {
  final view = camera ?? engine.cameraSystem.mainCamera;
  void add<T extends System>(DefaultSystem which, T Function() make) {
    if (include.contains(which) && !world.hasSystem<T>()) {
      world.addSystem(make());
    }
  }

  add(DefaultSystem.input, () => InputSystem(engine.input, maps: inputMaps));
  add(DefaultSystem.physics, () => PhysicsSystem(engine.physics, camera: view));
  add(DefaultSystem.movement, MovementSystem.new);
  add(DefaultSystem.audio, () => AudioSystem(engine: engine.audio));
  add(
    DefaultSystem.rendering,
    () => RenderSystem(camera: view, statsSink: engine.rendering),
  );
  add(
    DefaultSystem.rendering,
    () => ParallaxRenderSystem(
      backgroundHooks: engine.rendering.backgroundHooks,
      camera: view,
    ),
  );
  if (include.contains(DefaultSystem.sprites)) registerSpriteSystems(world);
  add(DefaultSystem.levelMaps, LevelMapSystem.new);
  add(DefaultSystem.mapCollision, MapCollisionSystem.new);
  if (include.contains(DefaultSystem.cameras) &&
      !world.hasSystem<CameraBrainSystem>()) {
    registerCameraSystems(world, engine.cameraSystem);
  }
}
