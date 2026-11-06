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
import '../ecs/serialization/field_type.dart';
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
/// the rest, and the field types they are saved through. The ECS core's
/// own (the transform, the parent and children links, tags, and the field
/// types in `FieldTypes`) are in every [EngineContext] already; 3-D
/// graphics and physics bring theirs when the engine is given them.
///
/// An `Engine` installs [extension] into its context, so a game's scenes
/// load. A world made on its own starts with only the ECS core's
/// components; give it these when it reads or writes scenes:
///
/// ```dart
/// final world = World(extensions: [BuiltInComponents.extension]);
/// ```
abstract final class BuiltInComponents {
  /// Registers [fieldTypes] and [all] into a context, and again after a
  /// hot reload.
  static const ContextExtension extension = _BuiltInComponentsExtension();

  /// The field types the features' components are saved through, beyond
  /// the ECS core's own: the physics layers and shapes, the 2-D material
  /// overrides, and the input actions.
  static List<FieldType> get fieldTypes => [
    ...PhysicsDefinitions.fieldTypes,
    ...Material2DDefinitions.fieldTypes,
    ...InputDefinitions.fieldTypes,
  ];

  /// A registry holding the ECS core's components and [all], for code that
  /// reads and writes components without a context.
  static ComponentDefinitionRegistry registry() {
    final registry = ComponentDefinitionRegistry()
      ..registerAll(EcsDefinitions.all, ifAbsent: true)
      ..registerAll(all, ifAbsent: true);
    _registerHints(registry);
    return registry;
  }

  /// The 3-D graphics components, which an engine knows only once it is
  /// given `Graphics3D()`. Named here — as strings, for core does not import
  /// 3-D — so a scene holding one, loaded without it, fails saying so
  /// (`UnknownComponentTypeException.hint`). Kept equal to what `Graphics3D`
  /// registers by its tests.
  static const List<String> graphics3DTypes = [
    'ModelComponent',
    'MaterialOverrides3DComponent',
    'Light3DComponent',
    'EnvironmentComponent',
    'AnimationPlayerComponent',
    'SocketComponent',
    'Cube3DComponent',
    'Sphere3DComponent',
    'Plane3DComponent',
    'Cylinder3DComponent',
    'Capsule3DComponent',
    'Cone3DComponent',
    'Torus3DComponent',
    'Ramp3DComponent',
    'Stairs3DComponent',
    'Arch3DComponent',
    'Polygon3DComponent',
  ];

  /// The 3-D physics components, which an engine knows only once it is
  /// given `Physics3D()`; see [graphics3DTypes].
  static const List<String> physics3DTypes = [
    'RigidBody3DComponent',
    'Collider3DComponent',
    'CharacterBody3DComponent',
    'FixedJoint3DComponent',
    'PointJoint3DComponent',
    'HingeJoint3DComponent',
    'SliderJoint3DComponent',
    'DistanceJoint3DComponent',
    'SixDofJoint3DComponent',
    'CameraCollision3DComponent',
  ];

  static const String _graphics3DHint =
      'It is a 3-D graphics component: give the engine '
      'EngineConfig(services: [Graphics3D()]) '
      '(package:just_game_engine/just_game_engine_3d.dart).';

  static const String _physics3DHint =
      'It is a 3-D physics component: give the engine '
      'EngineConfig(services: [Physics3D()]) '
      '(package:just_game_engine/just_game_engine_3d.dart).';

  /// Tells [registry] how to make each 3-D component known.
  static void _registerHints(ComponentDefinitionRegistry registry) {
    for (final type in graphics3DTypes) {
      registry.registerUnknownTypeHint(type, _graphics3DHint);
    }
    for (final type in physics3DTypes) {
      registry.registerUnknownTypeHint(type, _physics3DHint);
    }
  }

  /// Every feature's definitions, in the order an editor lists them: those
  /// named here first, then any other a feature's own `all` holds — so a
  /// definition added to a feature is installed even before it is placed
  /// in this list.
  static List<ComponentCodec> get all {
    final ordered = _ordered;
    final placed = {for (final codec in ordered) codec.type};
    return [
      ...ordered,
      for (final codec in _features)
        if (placed.add(codec.type)) codec,
    ];
  }

  /// Every feature's `all`.
  static List<ComponentCodec> get _features => [
    ...Shape2DDefinitions.all,
    ...PhysicsDefinitions.all,
    ...GameplayDefinitions.all,
    ...SpriteDefinitions.all,
    ...Physics2DDefinitions.all,
    ...CameraDefinitions.all,
    ...TimelineDefinitions.all,
    ...LevelMapDefinitions.all,
    ...InputDefinitions.all,
    ...EffectDefinitions.all,
    ...RenderingDefinitions.all,
    ...Material2DDefinitions.all,
    ...Lighting2DDefinitions.all,
    ...AnimationDefinitions.all,
    ...AudioDefinitions.all,
  ];

  static List<ComponentCodec> get _ordered => [
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
  void install(EngineContext context) {
    context.fieldTypes.registerAll(
      BuiltInComponents.fieldTypes,
      ifAbsent: true,
    );
    context.definitions.registerAll(BuiltInComponents.all, ifAbsent: true);
    BuiltInComponents._registerHints(context.definitions);
  }

  @override
  void refresh(EngineContext context) {
    context.fieldTypes.registerAll(
      BuiltInComponents.fieldTypes,
      ifAbsent: true,
    );
    context.definitions.refresh(BuiltInComponents.all);
    BuiltInComponents._registerHints(context.definitions);
  }
}
