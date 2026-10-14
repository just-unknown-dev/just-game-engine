/// Built-in Systems
///
/// Common system implementations that work with built-in components.
library;

// Priorities
export '../base/system_priorities.dart';

// Core systems
export 'core/movement_system.dart';

// Rendering systems
export 'rendering/render_system.dart';
export 'rendering/post_process_system.dart';
export 'rendering/parallax_render_system.dart';

// Physics systems
export 'physics/collider_geometry.dart';
export 'physics/physics_system.dart';
export 'physics/physics_joint_binding_system.dart';
export 'physics/physics_characters_2d.dart';
export 'physics/physics_events_2d.dart';
export 'physics/physics_queries_2d.dart';
export 'physics/ray_casting.dart';

// Input systems
export 'input/input_system.dart';
export 'input/simple_movement_system.dart';

// Hierarchy systems
export 'hierarchy/hierarchy_system.dart';
export '../base/transform/transform_hierarchy.dart';

// Gameplay systems
export 'gameplay/health_system.dart';
export 'gameplay/checkpoint_system.dart';
export 'gameplay/checkpoint_event.dart';

// Animation systems
export 'animation/timeline_system.dart';
export 'animation/timeline_trigger_system.dart';
export 'animation/animator_system.dart';
export 'animation/register_animation_systems.dart';
export 'rendering/sprite_systems.dart';

// Audio systems
export 'audio/audio_system.dart';

// Other systems
export 'others/lifetime_system.dart';
export 'others/boundary_system.dart';

// Level maps
export 'level_map/level_map_system.dart';
export 'level_map/map_collision_system.dart';
export 'level_map/register_level_map_systems.dart';

// Camera systems
export 'camera/camera_brain_system.dart';
export 'camera/camera_target_systems.dart';
export 'camera/camera_system.dart';
export 'camera/camera_brain.dart';
export 'camera/camera_stage.dart';
export 'camera/camera_targets.dart';
export 'camera/stages/framing_stage.dart';
export 'camera/stages/extension_stages.dart';
export 'camera/stages/group_framing_stage.dart';
export 'camera/stages/dolly_stage.dart';
export 'camera/stages/rig_3d_stages.dart';
export 'camera/camera_manager.dart';
export 'camera/managers/built_in_managers.dart';

// Culling systems
export 'culling/view_culling_system.dart';

// Navigation systems
export 'navigation/flow_field_system.dart';

// Deterministic Effects system
export 'effects/effect_system_ecs.dart';

// Particle system
export 'rendering/particle_system_ecs.dart';

// Narrative / Dialogue system
export 'narrative/dialogue_system.dart';

// Debug systems
export 'debug/collider_debugger_system.dart';
