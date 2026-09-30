/// Built-in Components
///
/// Common component types that work with the engine's subsystems.
library;

// Core components
export 'core/transform_component.dart';
export 'core/euler_rotation.dart';
export 'core/velocity_component.dart';
export 'core/generated_entity_component.dart';

// Rendering components
export 'rendering/renderable_component.dart';
export 'rendering/render_items_component.dart';
export 'rendering/layer_component.dart';
export 'rendering/sprite_component.dart';
export 'rendering/sprite_animation_component.dart';
export 'rendering/parallax_component.dart';
export 'rendering/shader_component.dart';

// Physics components
export 'physics/physics_body_component.dart';
export 'physics/physics_body_ref_component.dart';
export 'physics/joints/distance_joint_component.dart';
export 'physics/joints/prismatic_joint_component.dart';
export 'physics/joints/weld_joint_component.dart';
export 'physics/joints/wheel_joint_component.dart';

// Gameplay components
export 'gameplay/health_component.dart';
export 'gameplay/checkpoint_component.dart';
export 'gameplay/spawn_component.dart';

// Hierarchy components
export 'hierarchy/parent_component.dart';
export 'hierarchy/children_component.dart';

// Input components
export 'input/input_component.dart';
export 'input/simple_movement_component.dart';

// Animation components
export 'animation/animation_event.dart';
export 'animation/timeline_player_component.dart';
export 'animation/timeline_trigger_component.dart';
export 'animation/animator_component.dart';

// Audio components
export 'audio/audio_components.dart';

// Shape components
export 'shapes/shapes.dart';

// Other components
export 'others/tag_component.dart';
export 'others/lifetime_component.dart';

// Level maps
export 'level_map/level_map_component.dart';
export 'level_map/map_body_component.dart';

// Camera components
export 'camera/virtual_camera_component.dart';
export 'camera/camera_framing_component.dart';
export 'camera/camera_confiner_components.dart';
export 'camera/camera_noise_components.dart';
export 'camera/camera_target_components.dart';
export 'camera/camera_manager_components.dart';

// Culling components
export 'culling/cull_state_component.dart';

// Navigation components
export 'navigation/navigation_obstacle_component.dart';

// Deterministic Effects components
export 'effects/effect_component.dart';

// Particle components
export 'rendering/particle_emitter_component.dart';

// Narrative / Dialogue components
export '../../subsystems/narrative/ecs/dialogue_component.dart';

// UI components live in just_ui_editor.
