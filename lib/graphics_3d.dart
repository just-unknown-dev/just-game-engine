/// 3-D graphics for just_game_engine, drawn by just_graphics_engine on
/// Flutter GPU.
///
/// - [Graphics3D]: give one to the engine (`EngineConfig(graphics3D:
///   Graphics3D())`) and it saves, loads and draws the components below. A
///   game without one is 2-D only: no GPU device, no shaders loaded.
/// - Components: [ModelComponent], [LightComponent], [EnvironmentComponent],
///   [AnimationPlayerComponent] and [SocketComponent], and the shapes
///   ([Primitive3D]: [Cube3D] to [Polygon3D]). Plain data, so scenes
///   holding them load everywhere, the web included.
/// - [GraphicsSceneRenderer], which draws the world from the engine's
///   camera; [GraphicsModels], the loaded models; [AnimationSystem3D],
///   which plays clips.
/// - just_graphics_engine itself, re-exported: the renderer
///   ([Renderer3D], [RenderScene]), model loading, the GPU layer and
///   [Scene3DView].
///
/// Units are metres; +Y is down, like the rest of the engine.
library;

export 'package:just_graphics_engine/just_graphics_engine.dart';

export 'src/graphics_3d/animation_system.dart' hide PlayerScratch, samplePlayer;
export 'src/graphics_3d/graphics_3d.dart';
export 'src/graphics_3d/graphics_components.dart';
export 'src/graphics_3d/graphics_definitions.dart';
export 'src/graphics_3d/graphics_models.dart';
export 'src/graphics_3d/graphics_scene_renderer.dart';
export 'src/graphics_3d/graphics_shapes.dart';
export 'src/graphics_3d/shapes/primitive_3d.dart';
export 'src/graphics_3d/shapes/shape_components.dart';
export 'src/graphics_3d/shapes/shape_definitions.dart';
export 'src/graphics_3d/skeletal_animation_target.dart';
export 'src/graphics_3d/skeletal_clip_track.dart';
