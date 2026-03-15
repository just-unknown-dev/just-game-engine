/// Just Game Engine for Flutter
///
/// A comprehensive game engine package for Flutter providing core game development features.
///
/// This is the main entry point for the Just Game Engine. Import this library to access
/// all engine functionality.
///
/// Example usage:
/// ```dart
/// import 'package:just_game_engine/just_game_engine.dart';
///
/// void main() async {
///   final engine = Engine();
///   await engine.initialize();
///   engine.start();
/// }
/// ```
library;

// Core Engine - Main engine, game loop, and time management
export 'src/core/core.dart';

// Rendering Engine - Graphics and visual representation
export 'src/rendering/rendering_engine.dart';
export 'src/rendering/renderable.dart';
export 'src/rendering/sprite.dart';
export 'src/rendering/particles.dart';
export 'src/rendering/camera.dart';
export 'src/rendering/game_widget.dart';
export 'src/rendering/ray_renderable.dart'; // Beam / laser / bullet-trail visuals

// Physics Engine - Movement, gravity, and collision
export 'src/physics/physics_engine.dart';

// Ray Casting & Ray Tracing - Hitscan, LOS, multi-bounce tracing
export 'src/physics/ray_casting.dart';

// Input Management - Keyboard, mouse, controller, and touch input
export 'src/input/input_management.dart';

// Audio Engine - Sound effects and music
export 'src/audio/audio_engine.dart';
export 'src/audio/audio_components.dart';
export 'src/audio/audio_system.dart';

// Scene/Level Editor - Scene assembly and level design
export 'src/editor/scene_editor.dart';

// Animation System - Character and object animations
export 'src/animation/animation_system.dart';

// Asset Management - Loading and managing game assets
export 'src/assets/asset_management.dart';

// Networking - Multiplayer and server-client communication
export 'src/networking/networking.dart';

// Entity-Component System - Flexible entity architecture
export 'src/ecs/ecs.dart';
export 'src/ecs/components.dart';
export 'src/ecs/systems.dart';

// Cache Management - Storage and caching architecture
export 'src/cache/cache_manager.dart';

// Reactive ECS - Signal-driven wrappers for ECS types (requires just_signals)
export 'src/reactive/component_signal.dart';
export 'src/reactive/entity_signal.dart';
export 'src/reactive/world_signal.dart';
export 'src/reactive/reactive_system.dart';
export 'src/reactive/reactive_component.dart';

// Tiled Map Editor Integration - ECS components, factory, and systems
export 'src/ecs/tiled_components.dart';
export 'src/ecs/tiled_map_factory.dart';
export 'src/ecs/tiled_render_system.dart';
export 'src/ecs/tiled_collision_system.dart';
