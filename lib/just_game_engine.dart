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

// Shared Interfaces - Abstract contracts between ECS and subsystems
export 'src/interfaces/interfaces.dart';

// Camera - Viewport control and camera transformations
export 'src/subsystems/camera/camera.dart';

// Rendering - Graphics, sprites, and game widget
export 'src/subsystems/rendering/rendering.dart';

// Post-Processing - Fullscreen shader effects
export 'src/subsystems/post_processing/post_processing.dart';

// Particles - Advanced particle effects system
export 'src/subsystems/particles/particles.dart';

// Parallax - Multi-layer scrolling backgrounds with depth illusion
export 'src/subsystems/parallax/parallax.dart';

// Physics - Movement, gravity, collision detection, and ray casting
export 'src/subsystems/physics/physics.dart';

// Input - Keyboard, mouse, controller, touch, and virtual joystick
export 'src/subsystems/input/input.dart';

// Audio - Sound effects, music, and ECS audio integration
export 'src/subsystems/audio/audio.dart';

// Animation - Sprite animations, tweening, sequences, and easing
export 'src/subsystems/animation/animation.dart';

// Asset Management - Loading, caching, and resource management
export 'src/subsystems/assets/assets.dart';

// Scene/Level Editor - Scene assembly and level design
export 'src/subsystems/editor/editor.dart';

// Networking - Multiplayer and server-client communication
// WARNING: This subsystem is a stub — all methods are unimplemented.
// It is exported for API visibility but should not be used in production.
export 'src/subsystems/networking/networking.dart';

// Entity-Component System (ECS) - Data-oriented game architecture
export 'src/ecs/ecs.dart';
export 'src/ecs/entities/entities.dart';
export 'src/ecs/components/components.dart';
export 'src/ecs/systems/systems.dart';

// Math - Mutable vector types for hot-path code
export 'src/math/math.dart';

// Memory Management - Object pooling and caching infrastructure
export 'src/memory/memory.dart';

// Sprite Atlas - Sprite-sheet parsing, named regions, and atlas animations
// Supports TexturePacker (JSON Array / Hash / multi-page) and Aseprite formats
export 'src/subsystems/sprite_atlas/sprite_atlas.dart';

// Deterministic Effects - Tick-based Move, Scale, Rotate, Fade, Shake, Path,
// Sequence, Parallel, Delay, Repeat; serializable for multiplayer.
export 'src/subsystems/effects/effects.dart';

// Reactive ECS - Signal-driven wrappers for ECS types
export 'src/reactive/reactive.dart';

// Localization - Engine-wide i18n: string tables, plurals, locale switching.
// Central service shared by all subsystems including Narrative/Dialogue.
export 'src/subsystems/localization/localization.dart';

// Narrative/Dialogue - Yarn Spinner parser, runner, localization, ECS & UI
// Supports linear, branching, hub-and-spoke, and cutscene dialogue patterns.
// File format: Yarn Spinner 2.x (.yarn); conditions/commands via Dart callbacks.
export 'src/subsystems/narrative/narrative.dart';
