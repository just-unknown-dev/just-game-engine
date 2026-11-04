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
/// - [Graphics3DSceneRenderer], which draws the world from the engine's
///   camera; [Graphics3DModels], the loaded models; [Material3DLibrary], the
///   material files; [Animation3DSystem], which plays clips.
/// - What a game names of just_graphics_engine: the renderer
///   ([Renderer3D], [RenderScene], [Scene3DView]), its settings, model and
///   material data, mesh building, and the GPU device and resources the
///   engine hands out. The renderer's plumbing stays in that package.
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
/// - just_physics_engine's 3-D side: [Physics3DEngine], [Physics3DWorld],
///   shapes, settings and results.
///
/// Units are metres; +Y is down, like the rest of the engine, so gravity is
/// (0, +9.81, 0).
library;

// What a game names through the engine — and the math types the 3-D API
// takes, as the main library exports them; the renderer's plumbing
// (pipelines, GPU commands, cooking, test doubles) is left in
// just_graphics_engine.
export 'package:just_graphics_engine/just_graphics_engine.dart'
    show
        Aabb3,
        AlphaMode,
        BloomSettings,
        DirectionalLight,
        DynamicResolution,
        Environment,
        EnvironmentMapData,
        Frustum,
        GpuDevice,
        GpuEnvironmentMap,
        GpuMaterial,
        GpuModel,
        GpuPrimitive,
        GpuTexture,
        JustMatrix4,
        LightData,
        LightType,
        MaterialData,
        Matrix4,
        MaterialOverride,
        MeshBuilder,
        MeshData,
        MeshInstance,
        ModelData,
        ModelFetch,
        ModelImportSettings,
        ModelUploader,
        Plane,
        PrimitiveData,
        PunctualLight,
        Quaternion,
        Ray3,
        RenderScene,
        RenderStats,
        RenderViewMode,
        Renderer3D,
        SamplerData,
        Scene3DFrameCallback,
        Scene3DView,
        ShadowSettings,
        ShapeMesh,
        ShapeUv,
        TextureCompression,
        TextureData,
        TextureRef,
        UvMode,
        Vector2,
        Vector3,
        createGpuDevice,
        kSkinFloats,
        kVertexFloats,
        loadModelData;
export 'package:just_physics_engine/physics_3d.dart'
    show
        Body3DSettings,
        Body3DType,
        Box3DShape,
        Capsule3DShape,
        Character3DContact,
        Character3DSettings,
        Character3DState,
        Compound3DShape,
        ConvexHull3DShape,
        Cylinder3DShape,
        Ground3DState,
        HeightField3DShape,
        Joint3DKind,
        Joint3DSettings,
        JoltPhysicsEngine,
        Mesh3DShape,
        Motion3DQuality,
        Motor3DState,
        Physics3DEngine,
        Physics3DEvent,
        Physics3DEventType,
        Physics3DUnsupportedError,
        Physics3DWorld,
        Physics3DWorldSettings,
        Query3DFilter,
        Query3DHit,
        Shape3D,
        SixDofAxis3DMode,
        Sphere3DShape,
        Transformed3DShape;

// The 3-D material files' format, which the 3-D material library reads.
export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        Material3DAlpha,
        MaterialChain,
        Material3DFile,
        Material3DKind,
        Material3DUv;

export 'src/graphics/graphics_3d/animation_3d_system.dart'
    hide PlayerScratch, samplePlayer;
export 'src/graphics/graphics_3d/graphics_3d.dart';
export 'src/graphics/graphics_3d/model_components.dart';
export 'src/graphics/graphics_3d/graphics_3d_definitions.dart';
export 'src/graphics/graphics_3d/graphics_3d_models.dart';
export 'src/graphics/graphics_3d/graphics_3d_scene_renderer.dart';
export 'src/graphics/graphics_3d/graphics_3d_shapes.dart';
export 'src/graphics/graphics_3d/lighting/environment_component.dart';
export 'src/graphics/graphics_3d/lighting/light_3d_component.dart';
export 'src/graphics/graphics_3d/lighting/lighting_3d_definitions.dart';
export 'src/graphics/graphics_3d/materials/linear_color.dart';
export 'src/graphics/graphics_3d/materials/material_3d_definitions.dart';
export 'src/graphics/graphics_3d/materials/material_3d_library.dart';
export 'src/graphics/graphics_3d/materials/material_3d_overrides_field_type.dart';
export 'src/graphics/graphics_3d/materials/material_overrides_3d_component.dart';
export 'src/graphics/graphics_3d/material_slots.dart';
export 'src/graphics/graphics_3d/render_providers.dart';
export 'src/graphics/graphics_3d/shapes/primitive_3d_component.dart'
    hide ShapeValues;
export 'src/graphics/graphics_3d/shapes/shape_3d_components.dart';
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
