/// How an [Engine] is built.
library;

import 'package:just_physics_engine/just_physics_engine.dart'
    show PhysicsEngine;

import 'register_default_systems.dart';
import '../graphics_3d/graphics_3d.dart' show Graphics3D;
import '../physics_3d/physics_3d.dart' show Physics3D;
import '../subsystems/audio/audio.dart';
import '../subsystems/rendering/rendering_engine.dart';
import '../ecs/base/engine_context.dart';
import 'engine_service.dart';

/// Choices made once, when an [Engine] is made: what it is taught
/// ([extensions]), what it runs beside the game ([services]), and how some
/// subsystems are built.
///
/// ```dart
/// final engine = Engine(
///   config: EngineConfig(
///     extensions: [MyKit.extension],
///     defaultSystems: DefaultSystems.all,
///     services: [MyTelemetry()],
///     createRendering: MyRenderingEngine.new,
///   ),
/// );
/// await engine.initialize();
/// ```
class EngineConfig {
  /// A configuration with no extensions, no services and no default
  /// systems; the rendering and audio engines are the standard ones unless
  /// [createRendering] or [createAudio] is given.
  const EngineConfig({
    this.createRendering,
    this.createAudio,
    this.createPhysics,
    this.physics3D,
    this.graphics3D,
    this.deferAudioUntilInput,
    this.extensions = const [],
    this.services = const [],
    this.defaultSystems = const {},
  });

  /// The engine's standard systems its world starts with — none unless
  /// asked for; [DefaultSystems.all] for a typical game. Added as the
  /// engine initializes ([registerDefaultSystems]); systems a game adds
  /// itself come after.
  final Set<DefaultSystem> defaultSystems;

  /// The services the engine runs — started in this order as it
  /// initializes, stopped in reverse as it disposes; see [EngineService].
  /// Found with `engine.service<T>()`.
  final List<EngineService> services;

  /// Makes the audio engine — `AudioEngine.withBackend(...)` for a backend
  /// of your own, say. Null makes the standard one.
  final AudioEngine Function()? createAudio;

  /// Makes the 2-D physics engine (`engine.physics`). Null makes the
  /// standard one: native Box2D where the platform has it, the pure-Dart
  /// engine on the web. A world with no 2-D bodies costs nothing per step.
  final PhysicsEngine Function()? createPhysics;

  /// 3-D physics (`package:just_game_engine/physics_3d.dart`): null for a
  /// 2-D-only game, whose release build then carries no 3-D code at all.
  ///
  /// ```dart
  /// EngineConfig(physics3D: Physics3D())
  /// ```
  ///
  /// The engine installs it (the 3-D components and the camera's collision
  /// stage) as it is made and starts it, after [services], as it
  /// initializes. Jolt must be built into the app (its pubspec:
  /// `hooks: user_defines: just_jolt: build: true`); where 3-D cannot run,
  /// initializing fails with a `Physics3DUnsupportedError`.
  final Physics3D? physics3D;

  /// 3-D graphics (`package:just_game_engine/graphics_3d.dart`): null for a
  /// 2-D-only game, which then makes no GPU device and loads no shaders.
  ///
  /// ```dart
  /// EngineConfig(graphics3D: Graphics3D())
  /// ```
  ///
  /// The engine installs it (the 3-D components, and how animator graphs
  /// and timelines play clips on a skeleton) as it is made and starts it,
  /// before [services], as it initializes. Flutter GPU must be switched on
  /// in each platform's runner; where it can't draw (the web, Android on
  /// OpenGL ES) the game runs anyway and the 3-D view says why.
  final Graphics3D? graphics3D;

  /// Whether audio starts at the first key or pointer press rather than in
  /// [Engine.initialize]. Browsers keep an audio context made before any
  /// user gesture suspended — silent — and the audio engine makes its
  /// context when it starts. Null means: on the web only.
  ///
  /// A sound played before then starts the audio engine early (it starts
  /// itself on first use), and a browser may then keep it silent.
  final bool? deferAudioUntilInput;

  /// What packages teach the engine — their component definitions and the
  /// rest (see [ContextExtension]) — installed into `engine.context`, in
  /// order, so every world the engine makes can read their components.
  final List<ContextExtension> extensions;

  /// Makes the rendering engine — a subclass of [RenderingEngine] that draws
  /// some other way, say. Null makes the standard one. To draw the world
  /// with another backend *alongside* the canvas, add a `SceneRenderer`
  /// instead.
  final RenderingEngine Function()? createRendering;
}
