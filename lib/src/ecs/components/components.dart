/// Built-in Components
///
/// Common component types that work with the engine's subsystems.
library;

// Core components
export 'core/transform_component.dart';
export 'core/velocity_component.dart';

// Rendering components
export 'rendering/renderable_component.dart';
export 'rendering/sprite_component.dart';
export 'rendering/parallax_component.dart';
export 'rendering/shader_component.dart';

// Physics components
export 'physics/physics_body_component.dart';
export 'physics/physics_body_ref_component.dart';

// Gameplay components
export 'gameplay/health_component.dart';

// Hierarchy components
export 'hierarchy/parent_component.dart';
export 'hierarchy/children_component.dart';

// Input components
export 'input/input_component.dart';
export 'input/joystick_input_component.dart';

// Animation components
export 'animation/animation_state_component.dart';

// Audio components
export 'audio/audio_components.dart';

// Other components
export 'others/tag_component.dart';
export 'others/lifetime_component.dart';

// Tiled Map Editor components
export 'tiled/tiled_components.dart';

// Camera components
export 'camera/camera_follow_component.dart';

// Deterministic Effects components
export 'effects/effect_component.dart';

// Particle components
export 'rendering/particle_emitter_component.dart';

// Narrative / Dialogue components
export '../../subsystems/narrative/ecs/dialogue_component.dart';

// UI Components - ECS data components for UI elements
export 'ui/ui_component.dart';
export 'ui/text_component.dart';
export 'ui/button_component.dart';
export 'ui/linear_progress_component.dart';
export 'ui/circular_progress_component.dart';
