/// The engine's built-in components: every feature's own, which an
/// [Engine] installs into its context.
library;

import '../animation/animation_definitions.dart';
import '../audio/audio_definitions.dart';
import '../camera/camera_definitions.dart';
import '../ecs/engine_context.dart';
import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition_registry.dart';
import '../ecs/serialization/ecs_definitions.dart';
import '../effects/effect_definitions.dart';
import '../gameplay/gameplay_definitions.dart';
import '../input/input_definitions.dart';
import '../level_map/level_map_definitions.dart';
import '../graphics/graphics_2d/lighting/lighting_2d_definitions.dart';
import '../graphics/graphics_2d/materials/material_2d_definitions.dart';
import '../physics/physics_definitions.dart';
import '../physics/physics_2d/physics_2d_definitions.dart';
import '../rendering/rendering_definitions.dart';
import '../graphics/graphics_2d/shapes/shape_2d_definitions.dart';
import '../sprites/sprite_definitions.dart';
import '../timeline/timeline_definitions.dart';

/// Every component the engine's features define: sprites, shapes, 2-D
/// physics, cameras, timelines, level maps, materials, lights, audio and
/// the rest. The ECS core's own (the transform, the parent and children
/// links, tags) are in every [EngineContext] already; 3-D graphics and
/// physics bring theirs when the engine is given them.
///
/// An `Engine` installs [extension] into its context, so a game's scenes
/// load. A world made on its own starts with only the ECS core's
/// components; give it these when it reads or writes scenes:
///
/// ```dart
/// final world = World(extensions: [BuiltInComponents.extension]);
/// ```
abstract final class BuiltInComponents {
  /// Registers [all] into a context, and again after a hot reload.
  static const ContextExtension extension = _BuiltInComponentsExtension();

  /// A registry holding the ECS core's components and [all], for code that
  /// reads and writes components without a context.
  static ComponentDefinitionRegistry registry() => ComponentDefinitionRegistry()
    ..registerAll(EcsDefinitions.all, ifAbsent: true)
    ..registerAll(all, ifAbsent: true);

  /// Every feature's definitions, in the order an editor lists them.
  static List<ComponentCodec> get all => [
    Shape2DDefinitions.rectangle,
    Shape2DDefinitions.circle,
    Shape2DDefinitions.capsule,
    PhysicsDefinitions.velocity,
    GameplayDefinitions.health,
    GameplayDefinitions.lifetime,
    SpriteDefinitions.sprite,
    ...Physics2DDefinitions.all,
    ...CameraDefinitions.all,
    ...TimelineDefinitions.all,
    ...LevelMapDefinitions.all,
    GameplayDefinitions.spawn,
    InputDefinitions.input,
    EffectDefinitions.effect,
    InputDefinitions.simpleMovement,
    RenderingDefinitions.layer,
    Material2DDefinitions.material2D,
    Material2DDefinitions.screenMaterial,
    Lighting2DDefinitions.light2D,
    Lighting2DDefinitions.lighting2D,
    Lighting2DDefinitions.shadowCaster2D,
    GameplayDefinitions.checkpoint,
    Shape2DDefinitions.line,
    Shape2DDefinitions.polygon,
    SpriteDefinitions.spriteAnimation,
    AnimationDefinitions.animator,
    AudioDefinitions.audioSource,
    AudioDefinitions.audioListener,
    AudioDefinitions.audioStream,
  ];
}

final class _BuiltInComponentsExtension implements RefreshableExtension {
  const _BuiltInComponentsExtension();

  @override
  String get id => 'just_game_engine';

  @override
  void install(EngineContext context) =>
      context.definitions.registerAll(BuiltInComponents.all, ifAbsent: true);

  @override
  void refresh(EngineContext context) =>
      context.definitions.refresh(BuiltInComponents.all);
}
