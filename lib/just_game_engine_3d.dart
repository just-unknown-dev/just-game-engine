/// 3-D for just_game_engine: graphics drawn by just_graphics_engine on
/// Flutter GPU, and physics simulated by Jolt through just_physics_engine.
///
/// Give the engine the services a game uses:
/// `EngineConfig(services: [Graphics3D(), Physics3D()])`. A game without
/// them is 2-D only: no GPU device, no shaders, no Jolt — and the code here
/// is dropped from its build.
///
/// Graphics:
/// - [Graphics3D], the service that saves, loads and draws the components.
/// - Components: [ModelComponent], [AnimationPlayerComponent] and
///   [SocketComponent]; lights ([Light3DComponent], [EnvironmentComponent]);
///   [MaterialOverrides3DComponent]; and the shapes ([Primitive3DComponent]:
///   [Cube3DComponent] to [Polygon3DComponent]). Plain data, so scenes
///   holding them load everywhere, the web included.
/// - [GraphicsSceneRenderer], which draws the world from the engine's
///   camera; [GraphicsModels], the loaded models; [Material3DLibrary], the
///   material files; [Animation3DSystem], which plays clips.
/// - just_graphics_engine itself, re-exported: the renderer ([Renderer3D],
///   [RenderScene]), model loading, the GPU layer and [Scene3DView].
///
/// Physics:
/// - [Physics3D], the service that saves, loads and simulates the
///   components on Jolt Physics.
/// - Components: [RigidBody3DComponent], [Collider3DComponent],
///   [CharacterBody3DComponent], and the joints [FixedJoint3DComponent],
///   [PointJoint3DComponent], [HingeJoint3DComponent],
///   [SliderJoint3DComponent], [DistanceJoint3DComponent],
///   [SixDofJoint3DComponent].
/// - [Physics3DSystem], which steps the world, and its events on the
///   world's bus: [CollisionEnter3DEvent], [CollisionStay3DEvent],
///   [CollisionExit3DEvent], [SensorEnter3DEvent], [SensorExit3DEvent].
/// - [Physics3DQueries]: rays, sweeps and overlaps answered in entities.
/// - just_physics_engine's 3-D side: [PhysicsEngine3D], [PhysicsWorld3D],
///   shapes, settings and results.
///
/// Units are metres; +Y is down, like the rest of the engine, so gravity is
/// (0, +9.81, 0).
library;

export 'package:just_graphics_engine/just_graphics_engine.dart';
export 'package:just_physics_engine/physics_3d.dart' hide Quaternion, Vector3;

export 'src/graphics/graphics_3d/animation_3d_system.dart'
    hide PlayerScratch, samplePlayer;
export 'src/graphics/graphics_3d/graphics_3d.dart';
export 'src/graphics/graphics_3d/graphics_components.dart';
export 'src/graphics/graphics_3d/graphics_3d_definitions.dart';
export 'src/graphics/graphics_3d/graphics_models.dart';
export 'src/graphics/graphics_3d/graphics_scene_renderer.dart';
export 'src/graphics/graphics_3d/graphics_shapes.dart';
export 'src/graphics/graphics_3d/lighting/environment_component.dart';
export 'src/graphics/graphics_3d/lighting/light_3d_component.dart';
export 'src/graphics/graphics_3d/lighting/lighting_3d_definitions.dart';
export 'src/graphics/graphics_3d/materials/linear_color.dart';
export 'src/graphics/graphics_3d/materials/material_3d_definitions.dart';
export 'src/graphics/graphics_3d/materials/material_3d_library.dart';
export 'src/graphics/graphics_3d/materials/material_overrides_3d_component.dart';
export 'src/graphics/graphics_3d/material_slots.dart';
export 'src/graphics/graphics_3d/render_providers.dart';
export 'src/graphics/graphics_3d/shapes/primitive_3d.dart';
export 'src/graphics/graphics_3d/shapes/shape_components.dart';
export 'src/graphics/graphics_3d/shapes/shape_3d_definitions.dart';
export 'src/graphics/graphics_3d/skeletal_animation_target.dart';
export 'src/graphics/graphics_3d/skeletal_clip_track.dart';

export 'src/physics/physics_3d/camera_collision_3d_component.dart';
export 'src/physics/physics_3d/collider_3d_shapes.dart';
export 'src/physics/physics_3d/physics_3d.dart';
export 'src/physics/physics_3d/physics_3d_components.dart';
export 'src/physics/physics_3d/physics_3d_definitions.dart';
export 'src/physics/physics_3d/physics_3d_events.dart';
export 'src/physics/physics_3d/physics_3d_queries.dart';
export 'src/physics/physics_3d/physics_3d_system.dart';
