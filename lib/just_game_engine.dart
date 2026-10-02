/// Just Game Engine: a 2D game engine for Flutter.
///
/// This library is the engine and what hosts it in an app: `Engine` with
/// its subsystems and `EngineContext`; the ECS (`World`, `Entity`,
/// `Component`, `System`) with the engine's own components and systems;
/// scene loading (`SceneLoader`); level maps, sprites and animator graphs,
/// timelines, virtual cameras, physics, particles, effects, audio, input,
/// localization, dialogue and subtitles; and `GameWidget`, which shows a
/// game in a Flutter app, with `GameLayers` for widgets drawn over it.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final engine = Engine(
///     config: const EngineConfig(defaultSystems: DefaultSystems.all),
///   );
///   await engine.initialize(); // before the first frame
///   engine.world.createEntityWithComponents([
///     TransformComponent(),
///     CircleComponent(radius: 32),
///   ]);
///   engine.start();
///   runApp(MaterialApp(home: GameWidget(engine: engine)));
/// }
/// ```
///
/// Not in this library:
///
/// - Ready-made screen widgets — dialogue boxes, subtitles, localized text,
///   camera zoom controls, on-screen touch controls, rebinding lists — are
///   in `package:just_game_engine/widgets.dart`.
/// - Of the packages the engine is built on, only what a game uses through
///   the engine is re-exported: the run-time input API of `just_inputs`,
///   the math types of `just_dart`, the memory diagnostics of
///   `just_memory`, the audio types of `just_audio_engine` and the physics
///   types of `just_physics_engine`. For anything else, import the package.
/// - Achievements, sign-in, leaderboards, currency, inventory and ads are
///   in the package `just_game_services`, as opt-in `EngineService`s.
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

// Input - actions over keyboard, mouse, gamepads and touch; players and
// rebinding. What a game uses at run time: the service, actions, players,
// rebinding and the control-path names. The widgets (on-screen controls,
// rebinding lists) are in widgets.dart; the asset model (`...Def` types),
// validation and the interaction / processor / composite registries are in
// package:just_inputs itself.
export 'package:just_inputs/just_inputs.dart'
    show
        ActionValueType,
        BindingDisplay,
        BindingOverrides,
        DeviceChange,
        DeviceListener,
        GamepadControls,
        GamepadDevice,
        GamepadSource,
        InputAction,
        InputActionAsset,
        InputActionCallback,
        InputActionMap,
        InputActionPhase,
        InputActions,
        InputControl,
        InputDevice,
        InputEvent,
        InputOverrideStore,
        InputService,
        InputSubscription,
        JoinBehavior,
        JustGamepadsSource,
        KeyboardDevice,
        KeyboardKeys,
        MemoryInputOverrideStore,
        MouseControls,
        MouseDevice,
        OnScreenDevice,
        PlayerInput,
        PlayerInputManager,
        RawInputListener,
        RebindCanceled,
        RebindCompleted,
        RebindResult,
        RebindState,
        RebindingOperation,
        TouchscreenControls,
        TouchscreenDevice,
        rebindPlayer;
export 'src/subsystems/input/cache_input_override_store.dart';

// Audio - Sound effects, music, and ECS audio integration
export 'src/subsystems/audio/audio.dart';

// Animation - The animator graph (state machine over sprite clips)
export 'src/subsystems/animation/animation.dart';

// Asset Management - Loading, caching, and resource management
export 'src/subsystems/assets/assets.dart';

// Entity-Component System (ECS) - Data-oriented game architecture
export 'src/ecs/ecs.dart';
export 'src/ecs/components/components.dart';
export 'src/ecs/systems/systems.dart';
export 'src/ecs/spatial/spatial.dart';
export 'src/ecs/serialization/serialization.dart';

// Math - the vector, quaternion, matrix and volume types the engine's own
// signatures use, from just_dart (Quadtree and the rest: import just_dart).
export 'package:just_dart/just_dart.dart'
    show
        Aabb3,
        Frustum,
        JustMatrix4,
        Matrix4,
        Plane,
        Quaternion,
        Ray3,
        Vector2,
        Vector3;

// Memory Management - the engine's cache, the just_memory types its API
// returns (MemoryScope, profile snapshots) and the process-wide diagnostics
// (MemoryProfiler, PoolManager). Pools, arenas and budgeted caches for a
// game's own use: import just_memory.
export 'src/memory/cache_manager.dart';
export 'package:just_memory/just_memory.dart'
    show
        ArenaStats,
        CacheBudgetStats,
        DisposeCallback,
        MemoryCleanupResult,
        MemoryProfileSnapshot,
        MemoryProfiler,
        MemoryScope,
        MemoryStats,
        PoolManager,
        PoolStats,
        SystemMemorySnapshot;

// Sprite Atlas - Sprite-sheet parsing, named regions, and atlas animations
// Supports TexturePacker (JSON Array / Hash / multi-page) and Aseprite formats
export 'src/subsystems/sprite_atlas/sprite_atlas.dart';

// Timeline - Reusable timelines that animate any component field
export 'src/subsystems/timeline/timeline.dart';
// Level maps - layers of tiles, and entities on them; Tiled import/export
export 'src/subsystems/level_map/level_map.dart';

// In-game interface: package just_ui_editor, which registers itself
// through `engine.layers` and the definition registry.

// Deterministic Effects - Tick-based Move, Scale, Rotate, Fade, Shake, Path,
// Sequence, Parallel, Delay, Repeat; serializable for multiplayer.
export 'src/subsystems/effects/effects.dart';

// Reactive ECS - Signal-driven wrappers for ECS types
export 'src/reactive/reactive.dart';

// Localization - Engine-wide i18n: string tables, plurals, locale switching.
// Central service shared by all subsystems including Narrative/Dialogue.
export 'src/subsystems/localization/localization.dart';

// Narrative/Dialogue - Yarn Spinner parser, runner, localization and ECS
// (the dialogue widgets are in widgets.dart)
// Supports linear, branching, hub-and-spoke, and cutscene dialogue patterns.
// File format: Yarn Spinner 2.x (.yarn); conditions/commands via Dart callbacks.
export 'src/subsystems/narrative/narrative.dart';

// Subtitle - Timed subtitle cues, tracks and controller (the overlay widget
// is in widgets.dart).
// Integrates with LocalizationManager for locale-aware subtitle text.
export 'src/subsystems/subtitle/subtitle.dart';
