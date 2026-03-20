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
export 'src/features/rendering/rendering_engine.dart';
export 'src/features/rendering/renderable.dart';
export 'src/features/rendering/sprite.dart';
export 'src/features/rendering/particles.dart';
export 'src/features/rendering/camera.dart';
export 'src/features/rendering/game_widget.dart';
export 'src/features/rendering/ray_renderable.dart'; // Beam / laser / bullet-trail visuals

// Physics Engine - Movement, gravity, and collision
export 'src/features/physics/physics_engine.dart';

// Ray Casting & Ray Tracing - Hitscan, LOS, multi-bounce tracing
export 'src/features/physics/ray_casting.dart';

// Input Management - Keyboard, mouse, controller, and touch input
export 'src/features/input/input_management.dart';
export 'src/features/input/virtual_joystick.dart';

// Audio Engine - Sound effects and music
export 'src/features/audio/audio_engine.dart';
export 'src/features/audio/audio_components.dart';
export 'src/features/audio/audio_system.dart';

// Scene/Level Editor - Scene assembly and level design
export 'src/features/editor/scene_editor.dart';

// Animation System - Character and object animations
export 'src/features/animation/animation_system.dart';

// Asset Management - Loading and managing game assets
export 'src/features/assets/asset_management.dart';

// Networking - Multiplayer and server-client communication
export 'src/features/networking/networking.dart';

/// Entity-Component System (ECS)
/// A flexible architecture for organizing game logic where:
/// - Entities are containers for components (just an ID)
/// - Components are pure data (no logic)
/// - Systems process entities with specific components
export 'src/features/ecs/ecs.dart';
export 'src/features/ecs/entities/entities.dart';
export 'src/features/ecs/components/components.dart';
export 'src/features/ecs/systems/systems.dart';

// Cache Management - Storage and caching architecture
export 'src/features/cache/cache_manager.dart';

// Reactive ECS - Signal-driven wrappers for ECS types (requires just_signals)
export 'src/features/reactive/component_signal.dart';
export 'src/features/reactive/entity_signal.dart';
export 'src/features/reactive/world_signal.dart';
export 'src/features/reactive/reactive_system.dart';
export 'src/features/reactive/reactive_component.dart';
