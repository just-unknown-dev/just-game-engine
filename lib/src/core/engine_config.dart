/// How an [Engine] is built.
library;

import 'package:just_physics_engine/just_physics_engine.dart'
    show Physics2DEngine;

import 'register_default_systems.dart';
import '../audio/audio.dart';
import '../rendering/rendering_engine.dart';
import '../ecs/engine_context.dart';
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
  ///
  /// A service that is also a [ContextExtension] is installed into the
  /// engine's context as the engine is made, so its components are known
  /// before [Engine.initialize]. 3-D graphics and physics are such services
  /// (`package:just_game_engine/just_game_engine_3d.dart`):
  ///
  /// ```dart
  /// EngineConfig(services: [Graphics3D(), Physics3D()])
  /// ```
  ///
  /// Put `Graphics3D` before any service that loads models as it starts. A
  /// game without them is 2-D only, and its release build carries no 3-D
  /// code.
  final List<EngineService> services;

  /// Makes the audio engine — `AudioEngine.withBackend(...)` for a backend
  /// of your own, say. Null makes the standard one.
  final AudioEngine Function()? createAudio;

  /// Makes the 2-D physics engine (`engine.physics`). Null makes the
  /// standard one: native Box2D where the platform has it, the pure-Dart
  /// engine on the web. A world with no 2-D bodies costs nothing per step.
  final Physics2DEngine Function()? createPhysics;

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
